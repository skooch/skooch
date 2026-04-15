#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import shlex
import shutil
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

HOME_CODEX_DIR = Path.home() / ".codex"
SIGNAL_DIR = HOME_CODEX_DIR / "signals"
INBOX_DIR = HOME_CODEX_DIR / "inbox"
COMMAND_SIGNAL_LOG = SIGNAL_DIR / "command-signals.jsonl"
PERMISSION_SIGNAL_LOG = SIGNAL_DIR / "permission-signals.jsonl"
PERMISSION_DIGEST_MD = INBOX_DIR / "permission-digest.md"
PERMISSION_DIGEST_LOG = INBOX_DIR / "permission-digest.json"
RULES_PATH = HOME_CODEX_DIR / "rules" / "default.rules"

GENERATED_RULES_START = "# >>> HOME AUTO-GENERATED COMMAND RULES >>>"
GENERATED_RULES_END = "# <<< HOME AUTO-GENERATED COMMAND RULES <<<"
COMMAND_SIGNAL_SCHEMA_VERSION = 4
PERMISSION_SIGNAL_SCHEMA_VERSION = 2
PROMOTION_WINDOW_DAYS = 30
PROMOTION_MIN_HITS = 3
PROMOTION_MIN_DAYS = 2
PROMOTION_MIN_SESSIONS = 2

GENERIC_PERMISSION_NOTE = (
    "The user has granted broad edit permission for this Codex environment. "
    "Treat ordinary file edits, refactors, generated-file updates, and routine cleanup as authorized. "
    "Ask only before destructive changes, writes outside this home scope, or anything that would exceed the user's stated scope."
)

BROAD_EDIT_PATTERNS = (
    re.compile(r"\bediting anything here is fine\b", re.IGNORECASE),
    re.compile(r"\bedit(?:ing)? anything here is fine\b", re.IGNORECASE),
    re.compile(r"\banything here is fine\b", re.IGNORECASE),
    re.compile(r"\byou can edit anything\b", re.IGNORECASE),
    re.compile(r"\byou may edit anything\b", re.IGNORECASE),
    re.compile(r"\bfeel free to edit\b", re.IGNORECASE),
    re.compile(r"\bfeel free to make changes\b", re.IGNORECASE),
    re.compile(r"\bmake changes as needed\b", re.IGNORECASE),
    re.compile(r"\bbroad edit permission\b", re.IGNORECASE),
    re.compile(r"\bfull edit permission\b", re.IGNORECASE),
    re.compile(r"\bmodify anything here\b", re.IGNORECASE),
)

APPROVAL_PATTERNS = (
    re.compile(r"\bgrant write access\b", re.IGNORECASE),
    re.compile(r"\bwrite access\b", re.IGNORECASE),
    re.compile(r"\bpermission\b", re.IGNORECASE),
    re.compile(r"\bapproval\b", re.IGNORECASE),
    re.compile(r"\bcould you grant\b", re.IGNORECASE),
    re.compile(r"\bplease approve\b", re.IGNORECASE),
    re.compile(r"\bcan you approve\b", re.IGNORECASE),
    re.compile(r"\ballow me to write\b", re.IGNORECASE),
    re.compile(r"\bsandbox\b", re.IGNORECASE),
)

DANGEROUS_BASH_PATTERNS = (
    re.compile(r"\brm\s+-rf\b", re.IGNORECASE),
    re.compile(r"\bgit\s+reset\s+--hard\b", re.IGNORECASE),
    re.compile(r"\bgit\s+checkout\s+--\b", re.IGNORECASE),
    re.compile(r"\bgit\s+clean\s+-fdx?\b", re.IGNORECASE),
    re.compile(r"\bdd\s+if=", re.IGNORECASE),
    re.compile(r"\bmkfs(?:\.\w+)?\b", re.IGNORECASE),
    re.compile(r"\bchmod\s+-R\s+777\b", re.IGNORECASE),
    re.compile(r"\bsudo\b", re.IGNORECASE),
    re.compile(r"\bshutdown\b", re.IGNORECASE),
    re.compile(r"\breboot\b", re.IGNORECASE),
    re.compile(r"\bkill\s+-9\b", re.IGNORECASE),
)

ENV_ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=.*$")

COMMON_OPTION_ARGUMENTS = {
    "-C",
    "-c",
    "--common-dir",
    "--config",
    "--config-file",
    "--directory",
    "--exec-path",
    "--git-dir",
    "--manifest-path",
    "--namespace",
    "--object-directory",
    "--project",
    "--super-prefix",
    "--work-tree",
}

PROMOTABLE_COMMAND_FAMILIES: set[tuple[str, ...]] = {
    ("git", "config", "--get"),
    ("git", "diff"),
    ("git", "fetch"),
    ("git", "ls-files"),
    ("git", "log"),
    ("git", "rev-parse"),
    ("git", "show"),
    ("git", "stash", "list"),
    ("git", "stash", "show"),
    ("git", "status"),
    ("cargo", "build"),
    ("cargo", "check"),
    ("cargo", "clippy"),
    ("cargo", "fmt"),
    ("cargo", "test"),
    ("gh", "--version"),
    ("gh", "repo", "view"),
    ("gh", "search"),
    ("python3", "--version"),
    ("python3", "-m", "py_compile"),
    ("python3", "-m", "pytest"),
    ("pytest",),
    ("tdeck", "build"),
    ("tdeck", "monitor"),
    ("tdeck", "preview"),
    ("tdeck", "run"),
    ("uv", "pip", "compile"),
    ("uv", "pip", "install"),
    ("uv", "pip", "sync"),
    ("uv", "run"),
    ("uv", "tool", "install"),
    ("base64",),
}

COMMAND_NAME_ALLOWED_CHARS = frozenset(
    "abcdefghijklmnopqrstuvwxyz"
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "0123456789"
    "_./+@~-[]"
)
SHELL_BUILTINS = {
    "[",
    "command",
    "echo",
    "false",
    "printf",
    "pwd",
    "test",
    "true",
    "which",
}

UNSAFE_PROMOTION_MARKERS = ("<", ">", "`", "$(", "${", "*", "?")


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def write_text_if_changed(path: Path, text: str) -> bool:
    if path.exists():
        try:
            if path.read_text(encoding="utf-8") == text:
                return False
        except Exception:
            pass
    ensure_dir(path.parent)
    path.write_text(text, encoding="utf-8")
    return True


def append_jsonl(path: Path, record: dict[str, object]) -> None:
    ensure_dir(path.parent)
    with path.open("a", encoding="utf-8") as handle:
        json.dump(record, handle, ensure_ascii=True)
        handle.write("\n")


def matches_any(text: str, patterns: tuple[re.Pattern[str], ...]) -> bool:
    return any(pattern.search(text) for pattern in patterns)


def emit_json(payload: dict[str, object]) -> None:
    json.dump(payload, sys.stdout, ensure_ascii=True)
    sys.stdout.write("\n")


def context_path() -> Path:
    return HOME_CODEX_DIR / "permission-context.md"


def permission_signal_path() -> Path:
    return PERMISSION_SIGNAL_LOG


def command_signal_path() -> Path:
    return COMMAND_SIGNAL_LOG


def permission_digest_path() -> Path:
    return PERMISSION_DIGEST_LOG


def permission_digest_markdown_path() -> Path:
    return PERMISSION_DIGEST_MD


def current_cwd(payload: dict[str, object]) -> Path:
    raw_cwd = payload.get("cwd")
    if raw_cwd:
        return Path(str(raw_cwd)).expanduser().resolve()
    return Path.cwd().resolve()


def timestamp() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def payload_value(payload: dict[str, object], *keys: str) -> object | None:
    for key in keys:
        if key in payload and payload[key] is not None:
            return payload[key]
    return None


def payload_text(payload: dict[str, object], *keys: str) -> str:
    value = payload_value(payload, *keys)
    return "" if value is None else str(value)


def current_session_id(payload: dict[str, object]) -> str | None:
    session_id = payload_text(
        payload,
        "session_id",
        "sessionId",
        "conversation_id",
        "conversationId",
        "thread_id",
        "threadId",
    )
    return session_id or None


def record_signal(log_path: Path, event: str, cwd: Path, **fields: object) -> None:
    record: dict[str, object] = {
        "ts": timestamp(),
        "event": event,
        "cwd": str(cwd),
    }
    record.update(fields)
    append_jsonl(log_path, record)


def shell_segments(command: str) -> list[str]:
    segments: list[str] = []
    current: list[str] = []
    quote: str | None = None
    escape = False
    index = 0

    while index < len(command):
        char = command[index]
        if escape:
            current.append(char)
            escape = False
            index += 1
            continue
        if char == "\\":
            current.append(char)
            escape = True
            index += 1
            continue
        if quote is not None:
            current.append(char)
            if char == quote:
                quote = None
            index += 1
            continue
        if char in ("'", '"'):
            current.append(char)
            quote = char
            index += 1
            continue
        if char in ("\n", ";"):
            segment = "".join(current).strip()
            if segment:
                segments.append(segment)
            current = []
            index += 1
            continue
        if char == "&" and index + 1 < len(command) and command[index + 1] == "&":
            segment = "".join(current).strip()
            if segment:
                segments.append(segment)
            current = []
            index += 2
            continue
        if char == "|" and index + 1 < len(command) and command[index + 1] == "|":
            segment = "".join(current).strip()
            if segment:
                segments.append(segment)
            current = []
            index += 2
            continue
        if char == "|":
            segment = "".join(current).strip()
            if segment:
                segments.append(segment)
            current = []
            index += 1
            continue
        current.append(char)
        index += 1

    tail = "".join(current).strip()
    if tail:
        segments.append(tail)
    return segments


def tokenize_segment(segment: str) -> list[str]:
    try:
        return shlex.split(segment, posix=True)
    except ValueError:
        return segment.split()


def has_leading_assignments(tokens: list[str]) -> bool:
    index = 0
    while index < len(tokens) and ENV_ASSIGNMENT.match(tokens[index]):
        return True
    if tokens and Path(tokens[0]).name == "env":
        for token in tokens[1:]:
            if ENV_ASSIGNMENT.match(token):
                return True
            break
    return False


def strip_leading_assignments(tokens: list[str]) -> list[str]:
    index = 0
    while index < len(tokens) and ENV_ASSIGNMENT.match(tokens[index]):
        index += 1
    if index < len(tokens) and Path(tokens[index]).name == "env":
        index += 1
        while index < len(tokens) and ENV_ASSIGNMENT.match(tokens[index]):
            index += 1
    return tokens[index:]


def segment_has_unpromotable_syntax(segment: str) -> bool:
    return any(marker in segment for marker in UNSAFE_PROMOTION_MARKERS)


def normalized_tokens_for_promotion(tokens: list[str]) -> list[str]:
    normalized: list[str] = []
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if token in COMMON_OPTION_ARGUMENTS:
            index += 2 if index + 1 < len(tokens) else 1
            continue
        normalized.append(Path(token).name if index == 0 else token)
        index += 1
    return normalized


def strip_common_options(tokens: list[str]) -> list[str]:
    stripped: list[str] = []
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if token in COMMON_OPTION_ARGUMENTS:
            index += 2 if index + 1 < len(tokens) else 1
            continue
        if token.startswith("-") and token != "-":
            index += 1
            continue
        stripped.append(token)
        index += 1
    return stripped


def next_significant_token(
    tokens: list[str],
    start: int = 0,
    *,
    preserve_flags: bool = False,
) -> tuple[str | None, int]:
    index = start
    while index < len(tokens):
        token = tokens[index]
        if token in COMMON_OPTION_ARGUMENTS:
            index += 2 if index + 1 < len(tokens) else 1
            continue
        if not preserve_flags and token.startswith("-") and token != "-":
            index += 1
            continue
        return token, index
    return None, len(tokens)


def looks_like_command_token(token: str) -> bool:
    if not token:
        return False
    if token in SHELL_BUILTINS:
        return True
    if any(character not in COMMAND_NAME_ALLOWED_CHARS for character in token):
        return False
    if "/" in token or token.startswith(".") or token.startswith("~"):
        return True
    return shutil.which(token) is not None


def unwrap_shell_wrapper(tokens: list[str]) -> str | None:
    if not tokens:
        return None

    first = Path(tokens[0]).name
    if first in {"bash", "zsh", "sh"}:
        for index, token in enumerate(tokens[1:], start=1):
            if token.startswith("-") and "c" in token:
                return " ".join(tokens[index + 1 :])
    if first == "env":
        shell_index = None
        for index, token in enumerate(tokens[1:], start=1):
            if Path(token).name in {"bash", "zsh", "sh"}:
                shell_index = index
                break
        if shell_index is not None:
            for index, token in enumerate(tokens[shell_index + 1 :], start=shell_index + 1):
                if token.startswith("-") and "c" in token:
                    return " ".join(tokens[index + 1 :])
    return None


def canonical_git_family(tokens: list[str]) -> list[str]:
    family = ["git"]
    subcommand, index = next_significant_token(tokens, 1)
    if subcommand is None:
        return family

    if subcommand == "stash":
        family.append("stash")
        nested, _ = next_significant_token(tokens, index + 1)
        if nested in {"list", "pop", "push", "save", "show", "apply", "branch"}:
            family.append(nested)
        return family

    if subcommand == "config":
        family.append("config")
        nested, _ = next_significant_token(tokens, index + 1, preserve_flags=True)
        if nested == "--get":
            family.append(nested)
        return family

    if subcommand == "submodule":
        family.append("submodule")
        nested, _ = next_significant_token(tokens, index + 1)
        if nested == "update":
            family.append(nested)
        return family

    if subcommand == "worktree":
        family.append("worktree")
        nested, _ = next_significant_token(tokens, index + 1)
        if nested in {"add", "list", "prune", "remove"}:
            family.append(nested)
        return family

    if subcommand == "remote":
        family.append("remote")
        nested, _ = next_significant_token(tokens, index + 1)
        if nested in {"add", "remove", "rename", "set-url", "get-url", "show", "prune"}:
            family.append(nested)
        return family

    family.append(subcommand)
    return family


def canonical_family(tokens: list[str]) -> list[str]:
    if not tokens:
        return []

    base = Path(tokens[0]).name
    if base == "git":
        return canonical_git_family(tokens)

    if base == "defaults":
        subcommand, _ = next_significant_token(tokens, 1)
        if subcommand == "read":
            return ["defaults", "read"]
        if subcommand == "write":
            return ["defaults", "write"]
        return ["defaults"]

    if base == "gh":
        subcommand, index = next_significant_token(tokens, 1, preserve_flags=True)
        if subcommand is None:
            return ["gh"]
        if subcommand == "--version":
            return ["gh", "--version"]
        if subcommand == "repo":
            nested, _ = next_significant_token(tokens, index + 1)
            if nested is not None:
                return ["gh", "repo", nested]
            return ["gh", "repo"]
        return ["gh", subcommand]

    if base == "python3":
        subcommand, index = next_significant_token(tokens, 1, preserve_flags=True)
        if subcommand is None:
            return ["python3"]
        if subcommand == "--version":
            return ["python3", "--version"]
        if subcommand == "-m":
            module, _ = next_significant_token(tokens, index + 1, preserve_flags=True)
            if module is not None:
                return ["python3", "-m", module]
            return ["python3", "-m"]
        return ["python3"]

    if base in {"cargo", "brew", "mise", "tdeck", "uv"}:
        subcommand, index = next_significant_token(tokens, 1)
        if subcommand is None:
            return [base]

        if base == "uv" and subcommand in {"pip", "tool"}:
            nested, _ = next_significant_token(tokens, index + 1)
            if nested is not None:
                return [base, subcommand, nested]
            return [base, subcommand]

        if base == "tdeck" and subcommand in {"qemu", "openocd"}:
            nested, _ = next_significant_token(tokens, index + 1)
            if nested is not None:
                return [base, subcommand, nested]
            return [base, subcommand]

        if base == "mise" and subcommand == "env":
            nested, _ = next_significant_token(tokens, index + 1)
            if nested is not None:
                return [base, subcommand, nested]
            return [base, subcommand]

        return [base, subcommand]

    return [base]


def promotion_has_safe_shape(segment: str, tokens: list[str], family: list[str]) -> bool:
    if not tokens or not family:
        return False
    if segment_has_unpromotable_syntax(segment):
        return False

    normalized_tokens = normalized_tokens_for_promotion(tokens)
    if len(normalized_tokens) < len(family):
        return False
    if normalized_tokens[: len(family)] != family:
        return False

    extras = normalized_tokens[len(family) :]
    if not extras:
        return True

    for token in extras:
        if token == "--":
            return False
        if token.startswith("-"):
            continue
        return False
    return True


def command_family_records(command: str) -> list[dict[str, object]]:
    records: list[dict[str, object]] = []
    seen: set[tuple[str, ...]] = set()

    for segment in shell_segments(command):
        segment_records = command_family_records_from_segment(segment)
        for record in segment_records:
            family = tuple(str(part) for part in record["family"])  # type: ignore[index]
            if family in seen:
                continue
            seen.add(family)
            records.append(record)

    return records


def command_family_records_from_segment(segment: str) -> list[dict[str, object]]:
    tokens = tokenize_segment(segment)
    if not tokens:
        return []

    wrapper = unwrap_shell_wrapper(tokens)
    if wrapper is not None:
        return command_family_records(wrapper)

    had_leading_assignments = has_leading_assignments(tokens)
    tokens = strip_leading_assignments(tokens)
    if not tokens:
        return []

    if tokens[0] == "command" and len(tokens) > 1:
        lookup_mode, _ = next_significant_token(tokens, 1, preserve_flags=True)
        if lookup_mode in {"-v", "-V"}:
            return []
        tokens = tokens[1:]

    if tokens[0] in {"cd", "eval", "source", "export", "unset"}:
        return []
    if not looks_like_command_token(tokens[0]):
        return []

    family = canonical_family(tokens)
    if not family:
        return []

    family_tuple = tuple(family)
    promotable = (
        family_tuple in PROMOTABLE_COMMAND_FAMILIES
        and not had_leading_assignments
        and promotion_has_safe_shape(segment, tokens, family)
    )
    has_extra_args = len(tokens) > len(family)
    pattern_hint = " ".join(family + ["*"]) if has_extra_args else " ".join(family)

    return [
        {
            "family": family,
            "family_text": " ".join(family),
            "pattern_hint": pattern_hint,
            "promotable": promotable,
        }
    ]


def handle_session_start(payload: dict[str, object]) -> int:
    note_path = context_path()
    if not note_path.exists():
        return 0

    note = note_path.read_text(encoding="utf-8").strip()
    if not note:
        return 0

    emit_json(
        {
            "hookSpecificOutput": {
                "hookEventName": "SessionStart",
                "additionalContext": note,
            }
        }
    )
    return 0


def handle_user_prompt_submit(payload: dict[str, object]) -> int:
    prompt = payload_text(payload, "prompt", "userPrompt")
    if not matches_any(prompt, BROAD_EDIT_PATTERNS):
        return 0

    cwd = current_cwd(payload)
    note_path = context_path()
    write_text_if_changed(note_path, GENERIC_PERMISSION_NOTE + "\n")
    record_signal(
        permission_signal_path(),
        "broad_edit_prompt",
        cwd,
        schema_version=PERMISSION_SIGNAL_SCHEMA_VERSION,
        session_id=current_session_id(payload),
    )

    emit_json(
        {
            "systemMessage": "Broad edit permission detected for this Codex environment; ordinary file edits are authorized.",
            "hookSpecificOutput": {
                "hookEventName": "UserPromptSubmit",
                "additionalContext": GENERIC_PERMISSION_NOTE,
            },
        }
    )
    return 0


def handle_pre_tool_use(payload: dict[str, object]) -> int:
    tool_name = payload_text(payload, "tool_name", "toolName", "tool")
    if tool_name and Path(tool_name).name.lower() != "bash":
        return 0

    tool_input = payload_value(payload, "tool_input", "toolInput", "tool_args", "toolArgs")
    tool_input_mapping = tool_input if isinstance(tool_input, dict) else {}
    command = ""
    if isinstance(tool_input, str):
        command = tool_input
    elif tool_input_mapping:
        command = (
            str(tool_input_mapping.get("command") or "")
            or str(tool_input_mapping.get("cmd") or "")
            or str(tool_input_mapping.get("text") or "")
            or str(tool_input_mapping.get("input") or "")
        )
    if not command:
        command = payload_text(payload, "command", "cmd", "text")
    if not command:
        return 0

    cwd = current_cwd(payload)
    session_id = current_session_id(payload)
    families = command_family_records(command)
    blocked = matches_any(command, DANGEROUS_BASH_PATTERNS)

    record_signal(
        command_signal_path(),
        "command_observed",
        cwd,
        schema_version=COMMAND_SIGNAL_SCHEMA_VERSION,
        session_id=session_id,
        tool_name=tool_name or "Bash",
        blocked=blocked,
        families=families,
    )

    if not blocked:
        return 0

    record_signal(
        permission_signal_path(),
        "destructive_bash_blocked",
        cwd,
        schema_version=PERMISSION_SIGNAL_SCHEMA_VERSION,
        session_id=session_id,
        families=families,
    )

    emit_json(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": "Blocked by Codex hook: destructive shell command.",
            }
        }
    )
    return 0


def handle_hook() -> int:
    payload = json.load(sys.stdin)
    if not isinstance(payload, dict):
        return 0

    event = payload_text(payload, "hook_event_name", "hookEventName")
    if event == "SessionStart":
        return handle_session_start(payload)
    if event == "UserPromptSubmit":
        return handle_user_prompt_submit(payload)
    if event == "PreToolUse":
        return handle_pre_tool_use(payload)
    return 0


def handle_notify() -> int:
    raw = sys.argv[-1]
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return 0

    if not isinstance(payload, dict):
        return 0

    if payload_text(payload, "type") != "agent-turn-complete":
        return 0

    last_message = payload_text(payload, "last-assistant-message")
    if not matches_any(last_message, APPROVAL_PATTERNS):
        return 0

    record_signal(
        permission_signal_path(),
        "approval_like_completion",
        Path.cwd().resolve(),
        schema_version=PERMISSION_SIGNAL_SCHEMA_VERSION,
        turn_id=payload_text(payload, "turn-id", "turnId", "turn_id") or "unknown",
    )
    return 0


def load_jsonl(path: Path) -> list[dict[str, object]]:
    if not path.exists():
        return []

    records: list[dict[str, object]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(record, dict):
                records.append(record)
    return records


def load_permission_digest() -> dict[str, object] | None:
    path = permission_digest_path()
    if not path.exists():
        return None

    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None

    return payload if isinstance(payload, dict) else None


def parse_timestamp(raw: object) -> datetime | None:
    if not isinstance(raw, str) or not raw:
        return None
    try:
        return datetime.fromisoformat(raw)
    except ValueError:
        return None


def meets_promotion_threshold(hits: int, active_days: int, active_sessions: int) -> bool:
    return hits >= PROMOTION_MIN_HITS and (
        active_days >= PROMOTION_MIN_DAYS or active_sessions >= PROMOTION_MIN_SESSIONS
    )


def text_without_managed_block(existing_text: str) -> str:
    start = existing_text.find(GENERATED_RULES_START)
    end = existing_text.find(GENERATED_RULES_END)
    if start == -1 or end == -1 or end <= start:
        return existing_text

    before = existing_text[:start].rstrip()
    after = existing_text[end + len(GENERATED_RULES_END):].lstrip("\n")
    pieces: list[str] = []
    if before:
        pieces.append(before)
    if after:
        pieces.append(after.rstrip())
    return "\n\n".join(pieces).rstrip() + "\n" if pieces else ""


def extract_rule_pattern_literal(line: str) -> str | None:
    pattern_match = re.search(r"\bpattern\s*=", line)
    if not pattern_match:
        return None

    start = line.find("[", pattern_match.end())
    if start == -1:
        return None

    depth = 0
    quote: str | None = None
    escape = False
    for index in range(start, len(line)):
        char = line[index]
        if escape:
            escape = False
            continue
        if quote is not None:
            if char == "\\":
                escape = True
            elif char == quote:
                quote = None
            continue
        if char in ("'", '"'):
            quote = char
            continue
        if char == "[":
            depth += 1
            continue
        if char == "]":
            depth -= 1
            if depth == 0:
                return line[start : index + 1]
    return None


def allow_patterns_from_text(text: str) -> set[tuple[str, ...]]:
    patterns: set[tuple[str, ...]] = set()
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line.startswith("prefix_rule("):
            continue
        decision_match = re.search(r'\bdecision\s*=\s*"([^"]+)"', line)
        if not decision_match or decision_match.group(1) != "allow":
            continue
        pattern_literal = extract_rule_pattern_literal(line)
        if pattern_literal is None:
            continue
        try:
            pattern = json.loads(pattern_literal)
        except json.JSONDecodeError:
            continue
        if isinstance(pattern, list) and pattern and all(isinstance(token, str) for token in pattern):
            patterns.add(tuple(pattern))
    return patterns


def family_covered_by_allow_patterns(
    family: tuple[str, ...],
    allow_patterns: set[tuple[str, ...]],
) -> bool:
    for pattern in allow_patterns:
        if len(pattern) > len(family):
            continue
        if family[: len(pattern)] == pattern:
            return True
    return False


def family_has_exact_allow_pattern(
    family: tuple[str, ...],
    allow_patterns: set[tuple[str, ...]],
) -> bool:
    return family in allow_patterns


_HOST_SCOPED_PATH_PREFIXES = ("/Users/", "/home/", "/private/var/folders/")


def family_contains_host_scoped_path(family: tuple[str, ...]) -> bool:
    """Reject promotion of families whose argv carries an absolute home-scoped path.

    These rules are inherently per-host (worktree names, cargo target dirs,
    ephemeral plan files) and promoting them leaks host identity into the
    committed profile. Repeatedly typing the same such command across sessions
    is not evidence that it should be a global allow rule.
    """
    for token in family:
        if any(token.startswith(prefix) for prefix in _HOST_SCOPED_PATH_PREFIXES):
            return True
    return False


def consolidation_candidates_from_stats(
    stats: dict[tuple[str, ...], dict[str, object]],
    base_allow_patterns: set[tuple[str, ...]],
) -> tuple[list[dict[str, object]], set[tuple[str, ...]]]:
    prefix_members: dict[tuple[str, ...], set[tuple[str, ...]]] = defaultdict(set)
    family_hits: dict[tuple[str, ...], int] = {}

    for family, family_stats in stats.items():
        hits = int(family_stats["hits"])
        active_days = len(family_stats["days"]) if isinstance(family_stats["days"], set) else 0
        active_sessions = len(family_stats["sessions"]) if isinstance(family_stats["sessions"], set) else 0
        if len(family) < 2 or not meets_promotion_threshold(hits, active_days, active_sessions):
            continue
        if family_covered_by_allow_patterns(family, base_allow_patterns):
            continue

        family_hits[family] = hits
        for prefix_length in range(1, len(family)):
            prefix = family[:prefix_length]
            if family_covered_by_allow_patterns(prefix, base_allow_patterns):
                continue
            prefix_members[prefix].add(family)

    ranked_candidates: list[tuple[tuple[str, ...], set[tuple[str, ...]], int]] = []
    for prefix, members in prefix_members.items():
        if len(members) < 2:
            continue
        total_hits = sum(family_hits[family] for family in members)
        ranked_candidates.append((prefix, members, total_hits))

    ranked_candidates.sort(key=lambda item: (-len(item[0]), -len(item[1]), -item[2], item[0]))

    selected_candidates: list[dict[str, object]] = []
    assigned_families: set[tuple[str, ...]] = set()
    for prefix, members, _ in ranked_candidates:
        unassigned_members = sorted(
            (family for family in members if family not in assigned_families),
            key=lambda family: (-family_hits[family], family),
        )
        if len(unassigned_members) < 2:
            continue

        assigned_families.update(unassigned_members)
        selected_candidates.append(
            {
                "pattern": list(prefix),
                "decision": "ask-user",
                "justification": (
                    f"{len(unassigned_members)} repeated subcommand families could be consolidated "
                    "into a broader allow"
                ),
                "member_families": [list(family) for family in unassigned_members],
                "observed_count": sum(family_hits[family] for family in unassigned_members),
            }
        )

    return selected_candidates, assigned_families


def family_signature(family: tuple[str, ...]) -> str:
    tokens = ", ".join(json.dumps(token) for token in family)
    return f"pattern = [{tokens}]"


def line_exists(text: str, family: tuple[str, ...]) -> bool:
    signature = family_signature(family)
    compact = signature.replace("pattern = ", "pattern=").replace(", ", ",")
    return signature in text or compact in text


def render_rule_line(family: tuple[str, ...], hits: int) -> str:
    tokens = ", ".join(json.dumps(token) for token in family)
    justification = json.dumps(f"Observed repeated home-scoped command pattern ({hits} hits)")
    return f'prefix_rule(pattern = [{tokens}], decision = "allow", justification = {justification})'


def managed_block_lines(existing_text: str) -> list[str]:
    start = existing_text.find(GENERATED_RULES_START)
    end = existing_text.find(GENERATED_RULES_END)
    if start == -1 or end == -1 or end <= start:
        return []

    block = existing_text[start + len(GENERATED_RULES_START):end]
    lines: list[str] = []
    for raw_line in block.splitlines():
        line = raw_line.strip()
        if line.startswith("prefix_rule("):
            lines.append(line)
    return lines


def build_managed_block(existing_text: str, new_lines: list[str]) -> tuple[str, list[str]]:
    combined: list[str] = []
    seen: set[str] = set()
    for line in new_lines:
        if line in seen:
            continue
        seen.add(line)
        combined.append(line)

    block_parts = [
        GENERATED_RULES_START,
        "# Managed by ~/.codex/hooks/permission_bridge.py sync-rules.",
        "# This block only promotes repeated safe command families observed home-wide.",
    ]
    block_parts.extend(combined)
    block_parts.append(GENERATED_RULES_END)
    block_text = "\n".join(block_parts) + "\n"

    start = existing_text.find(GENERATED_RULES_START)
    end = existing_text.find(GENERATED_RULES_END)
    if start != -1 and end != -1 and end > start:
        before = existing_text[:start].rstrip()
        after = existing_text[end + len(GENERATED_RULES_END):].lstrip("\n")
        pieces: list[str] = []
        if before:
            pieces.append(before)
        pieces.append(block_text.rstrip("\n"))
        if after:
            pieces.append(after.rstrip())
        updated_text = "\n\n".join(pieces).rstrip() + "\n"
    else:
        stripped = existing_text.rstrip()
        if stripped:
            updated_text = stripped + "\n\n" + block_text
        else:
            updated_text = block_text

    return updated_text, combined


def promoted_family_stats() -> dict[tuple[str, ...], dict[str, object]]:
    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(days=PROMOTION_WINDOW_DAYS)
    stats: dict[tuple[str, ...], dict[str, object]] = defaultdict(
        lambda: {"hits": 0, "days": set(), "sessions": set(), "first_seen": None, "last_seen": None}
    )

    for record in load_jsonl(command_signal_path()):
        if record.get("event") != "command_observed":
            continue
        if record.get("blocked"):
            continue

        record_time = parse_timestamp(record.get("ts"))
        if record_time is None:
            continue
        if record_time.tzinfo is None:
            record_time = record_time.replace(tzinfo=timezone.utc)
        if record_time < cutoff:
            continue

        families = record.get("families")
        if not isinstance(families, list):
            continue
        for family_record in families:
            if not isinstance(family_record, dict):
                continue
            if not family_record.get("promotable"):
                continue
            family = family_record.get("family")
            if not isinstance(family, list) or not family:
                continue
            family_tuple = tuple(str(token) for token in family)
            if family_tuple not in PROMOTABLE_COMMAND_FAMILIES:
                continue
            family_stats = stats[family_tuple]
            family_stats["hits"] = int(family_stats["hits"]) + 1
            days = family_stats["days"]
            if isinstance(days, set):
                days.add(record_time.date().isoformat())
            timestamp = record_time.astimezone(timezone.utc).isoformat(timespec="seconds")
            first_seen = family_stats.get("first_seen")
            last_seen = family_stats.get("last_seen")
            if not isinstance(first_seen, str) or timestamp < first_seen:
                family_stats["first_seen"] = timestamp
            if not isinstance(last_seen, str) or timestamp > last_seen:
                family_stats["last_seen"] = timestamp
            session_id = record.get("session_id")
            if isinstance(session_id, str) and session_id:
                sessions = family_stats["sessions"]
                if isinstance(sessions, set):
                    sessions.add(session_id)
    return stats


def permission_event_summary() -> dict[str, object]:
    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(days=PROMOTION_WINDOW_DAYS)
    counts: dict[str, int] = defaultdict(int)
    sessions: set[str] = set()

    for record in load_jsonl(permission_signal_path()):
        record_time = parse_timestamp(record.get("ts"))
        if record_time is None:
            continue
        if record_time.tzinfo is None:
            record_time = record_time.replace(tzinfo=timezone.utc)
        if record_time < cutoff:
            continue

        event = record.get("event")
        if isinstance(event, str) and event:
            counts[event] += 1

        session_id = record.get("session_id")
        if isinstance(session_id, str) and session_id:
            sessions.add(session_id)

    return {"counts": counts, "sessions": sessions}


def build_permission_digest() -> dict[str, object]:
    family_stats = promoted_family_stats()
    permission_summary = permission_event_summary()
    permission_counts = permission_summary.get("counts")
    permission_sessions = permission_summary.get("sessions")
    if not isinstance(permission_counts, dict):
        permission_counts = {}
    if not isinstance(permission_sessions, set):
        permission_sessions = set()

    rules_text = RULES_PATH.read_text(encoding="utf-8") if RULES_PATH.exists() else ""
    allow_patterns = allow_patterns_from_text(rules_text)
    base_allow_patterns = allow_patterns_from_text(text_without_managed_block(rules_text))
    consolidation_candidates, consolidation_members = consolidation_candidates_from_stats(
        family_stats,
        base_allow_patterns,
    )

    observations: list[dict[str, object]] = []
    candidate_rules: list[dict[str, object]] = []
    session_ids: set[str] = set(permission_sessions)
    covered_repeated_families = 0

    for family, family_stats in sorted(
        family_stats.items(),
        key=lambda item: (-int(item[1]["hits"]), item[0]),
    ):
        hits = int(family_stats["hits"])
        active_days = len(family_stats["days"]) if isinstance(family_stats["days"], set) else 0
        active_sessions = len(family_stats["sessions"]) if isinstance(family_stats["sessions"], set) else 0
        first_seen = family_stats.get("first_seen")
        last_seen = family_stats.get("last_seen")
        if isinstance(family_stats.get("sessions"), set):
            session_ids.update(str(session_id) for session_id in family_stats["sessions"] if isinstance(session_id, str))

        repeated_enough = meets_promotion_threshold(hits, active_days, active_sessions)
        if family in consolidation_members:
            status = "consolidate"
        elif repeated_enough and family_covered_by_allow_patterns(family, allow_patterns):
            status = "covered"
            covered_repeated_families += 1
        elif repeated_enough:
            status = "candidate"
        else:
            status = "observed"
        family_text = " ".join(family)
        observations.append(
            {
                "family": list(family),
                "count": hits,
                "session_count": active_sessions,
                "first_seen": first_seen,
                "last_seen": last_seen,
                "risk": "low",
                "status": status,
            }
        )
        if status == "candidate":
            candidate_rules.append(
                {
                    "pattern": list(family),
                    "decision": "allow",
                    "justification": f"Observed repeated home-scoped command pattern ({hits} hits)",
                    "observed_count": hits,
                }
            )

    summary_notes = [
        "Permission events: "
        + ", ".join(
            f"{event}={int(permission_counts.get(event, 0))}"
            for event in ("broad_edit_prompt", "approval_like_completion", "destructive_bash_blocked")
        ),
    ]
    if covered_repeated_families:
        summary_notes.append(
            f"Repeated families already covered by existing allow rules: {covered_repeated_families}"
        )
    if consolidation_candidates:
        summary_notes.append(
            f"Broader allow confirmations needed: {len(consolidation_candidates)}"
        )
    if not candidate_rules:
        summary_notes.append("No uncovered command family qualified for promotion.")

    generated_at = timestamp()
    digest = {
        "generated_at": generated_at,
        "window_days": PROMOTION_WINDOW_DAYS,
        "source_files": [
            str(permission_signal_path()),
            str(command_signal_path()),
        ],
        "session_count": len(session_ids),
        "observations": observations,
        "candidate_rules": candidate_rules,
        "consolidation_candidates": consolidation_candidates,
        "notes": summary_notes,
    }
    return digest


def render_permission_digest_markdown(digest: dict[str, object]) -> str:
    observations = digest.get("observations")
    if not isinstance(observations, list):
        observations = []
    candidate_rules = digest.get("candidate_rules")
    if not isinstance(candidate_rules, list):
        candidate_rules = []
    consolidation_candidates = digest.get("consolidation_candidates")
    if not isinstance(consolidation_candidates, list):
        consolidation_candidates = []
    notes = digest.get("notes")
    if not isinstance(notes, list):
        notes = []

    lines: list[str] = [
        "# Permission Digest",
        "",
        "## Summary",
        f"- Window: last {int(digest.get('window_days', PROMOTION_WINDOW_DAYS))} days.",
        f"- Sessions: {int(digest.get('session_count', 0))}.",
        f"- Observed families: {len(observations)}.",
        f"- Candidate rules: {len(candidate_rules)}.",
        f"- Consolidation asks: {len(consolidation_candidates)}.",
        "",
        "## Observations",
    ]
    if observations:
        for observation in observations:
            if not isinstance(observation, dict):
                continue
            family = observation.get("family")
            if isinstance(family, list):
                family_text = " ".join(str(token) for token in family)
            else:
                family_text = "unknown"
            lines.append(
                "- `"
                + family_text
                + f"`: count={int(observation.get('count', 0))}, sessions={int(observation.get('session_count', 0))}, "
                + f"first_seen={observation.get('first_seen')}, last_seen={observation.get('last_seen')}, "
                + f"risk={observation.get('risk')}, status={observation.get('status')}"
            )
    else:
        lines.append("- No qualifying command families were observed.")

    lines.extend(["", "## Candidate Rules"])
    if candidate_rules:
        for rule in candidate_rules:
            if not isinstance(rule, dict):
                continue
            pattern = rule.get("pattern")
            if isinstance(pattern, list):
                pattern_text = json.dumps(pattern, ensure_ascii=True)
            else:
                pattern_text = "[]"
            lines.append(
                f"- `{pattern_text}` -> {rule.get('decision', 'allow')} ({rule.get('justification', '')})"
            )
    else:
        lines.append("- No rules qualified for promotion.")

    lines.extend(["", "## Consolidation Candidates"])
    if consolidation_candidates:
        for candidate in consolidation_candidates:
            if not isinstance(candidate, dict):
                continue
            pattern = candidate.get("pattern")
            members = candidate.get("member_families")
            if isinstance(pattern, list):
                pattern_text = json.dumps(pattern, ensure_ascii=True)
            else:
                pattern_text = "[]"
            member_labels: list[str] = []
            if isinstance(members, list):
                for member in members:
                    if isinstance(member, list):
                        member_labels.append(" ".join(str(token) for token in member))
            member_text = f"; members={', '.join(member_labels)}" if member_labels else ""
            lines.append(
                f"- `{pattern_text}` -> ask user before broadening ({candidate.get('justification', '')}{member_text})"
            )
    else:
        lines.append("- No broader allow consolidations need confirmation.")

    lines.extend(["", "## Notes"])
    if notes:
        for note in notes:
            lines.append(f"- {note}")
    else:
        lines.append("- No notes.")

    return "\n".join(lines) + "\n"


def write_permission_digest() -> dict[str, object]:
    digest = build_permission_digest()
    markdown_text = render_permission_digest_markdown(digest)
    json_text = json.dumps(digest, ensure_ascii=True, indent=2, sort_keys=True) + "\n"
    md_changed = write_text_if_changed(permission_digest_markdown_path(), markdown_text)
    json_changed = write_text_if_changed(permission_digest_path(), json_text)
    return {
        "status": "ok",
        "updated": md_changed or json_changed,
        "markdown_path": str(permission_digest_markdown_path()),
        "json_path": str(permission_digest_path()),
        "session_count": digest.get("session_count", 0),
        "candidate_rule_count": len(digest.get("candidate_rules", []))
        if isinstance(digest.get("candidate_rules"), list)
        else 0,
        "consolidation_candidate_count": len(digest.get("consolidation_candidates", []))
        if isinstance(digest.get("consolidation_candidates"), list)
        else 0,
    }


def handle_digest() -> int:
    write_permission_digest()
    return 0


def digest_candidate_suggestions() -> list[dict[str, object]]:
    digest = load_permission_digest()
    if not digest:
        return []

    raw_candidates = digest.get("candidate_rules")
    if not isinstance(raw_candidates, list):
        return []

    suggestions: list[dict[str, object]] = []
    for candidate in raw_candidates:
        if not isinstance(candidate, dict):
            continue

        pattern = candidate.get("pattern")
        if not isinstance(pattern, list) or not pattern:
            continue

        family_tuple = tuple(str(token) for token in pattern)
        if family_tuple not in PROMOTABLE_COMMAND_FAMILIES:
            continue

        observed_count_raw = candidate.get("observed_count")
        try:
            observed_count = int(observed_count_raw)
        except (TypeError, ValueError):
            continue
        if observed_count <= 0:
            continue

        suggestions.append(
            {
                "family": family_tuple,
                "hits": observed_count,
            }
        )

    return suggestions


def sync_rules(output_path: Path | None = None) -> dict[str, object]:
    ensure_dir(RULES_PATH.parent)
    existing_text = RULES_PATH.read_text(encoding="utf-8") if RULES_PATH.exists() else ""
    current_managed_text = "\n".join(managed_block_lines(existing_text))
    base_text = text_without_managed_block(existing_text)
    base_allow_patterns = allow_patterns_from_text(base_text)
    managed_allow_patterns = allow_patterns_from_text(current_managed_text)
    stats = promoted_family_stats()
    consolidation_candidates, consolidation_members = consolidation_candidates_from_stats(
        stats,
        base_allow_patterns,
    )
    digest_suggestions = digest_candidate_suggestions()

    candidate_lines: list[str] = []
    promoted_families: list[str] = []
    retained_managed: list[str] = []
    skipped_consolidation: list[str] = []
    skipped_threshold: list[str] = []
    skipped_covered: list[str] = []
    skipped_unsafe: list[str] = []
    skipped_host_scoped: list[str] = []

    for family, family_stats in sorted(
        stats.items(),
        key=lambda item: (-int(item[1]["hits"]), item[0]),
    ):
        hits = int(family_stats["hits"])
        active_days = len(family_stats["days"]) if isinstance(family_stats["days"], set) else 0
        active_sessions = len(family_stats["sessions"]) if isinstance(family_stats["sessions"], set) else 0
        family_text = " ".join(family)
        if not meets_promotion_threshold(hits, active_days, active_sessions):
            skipped_threshold.append(family_text)
            continue
        if family in consolidation_members:
            skipped_consolidation.append(family_text)
            continue
        if family_covered_by_allow_patterns(family, base_allow_patterns):
            skipped_covered.append(family_text)
            continue
        if family_contains_host_scoped_path(family):
            skipped_host_scoped.append(family_text)
            continue
        if family_has_exact_allow_pattern(family, managed_allow_patterns):
            candidate_lines.append(render_rule_line(family, hits))
            retained_managed.append(family_text)
            continue
        candidate_lines.append(render_rule_line(family, hits))
        promoted_families.append(family_text)

    for suggestion in digest_suggestions:
        family = suggestion["family"]
        if not isinstance(family, tuple):
            continue
        family_text = " ".join(family)
        if family in stats:
            retained_managed.append(family_text)
            continue

        hits = int(suggestion["hits"])
        if family_covered_by_allow_patterns(family, base_allow_patterns):
            skipped_covered.append(family_text)
            continue
        if family_contains_host_scoped_path(family):
            skipped_host_scoped.append(family_text)
            continue
        if family_has_exact_allow_pattern(family, managed_allow_patterns):
            candidate_lines.append(render_rule_line(family, hits))
            retained_managed.append(family_text)
            continue
        candidate_lines.append(render_rule_line(family, hits))
        promoted_families.append(family_text)

    if candidate_lines:
        updated_text, merged_lines = build_managed_block(existing_text, candidate_lines)
    else:
        updated_text, merged_lines = build_managed_block(existing_text, [])

    changed = updated_text != existing_text
    output_path_str = None
    if output_path is not None:
        ensure_dir(output_path.parent)
        output_path.write_text(updated_text, encoding="utf-8")
        output_path_str = str(output_path)

    return {
        "status": "ok",
        "updated": changed,
        "rules_path": str(RULES_PATH),
        "output_path": output_path_str,
        "promoted": promoted_families,
        "retained_managed": retained_managed,
        "skipped_consolidation": skipped_consolidation,
        "skipped_threshold": skipped_threshold,
        "skipped_covered": skipped_covered,
        "skipped_unsafe": skipped_unsafe,
        "skipped_host_scoped": skipped_host_scoped,
        "rule_count": len(merged_lines),
        "observed_count": sum(int(family_stats["hits"]) for family_stats in stats.values()),
        "observed_families": sorted(" ".join(family) for family in stats),
        "consolidation_candidates": consolidation_candidates,
        "digest_candidate_families": sorted(
            {
                " ".join(suggestion["family"])
                for suggestion in digest_suggestions
                if isinstance(suggestion.get("family"), tuple)
            }
        ),
        "window_days": PROMOTION_WINDOW_DAYS,
    }


def handle_sync_rules() -> int:
    output_path = Path(sys.argv[2]).expanduser() if len(sys.argv) > 2 else None
    emit_json(sync_rules(output_path=output_path))
    return 0


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "hook"
    if mode == "notify":
        return handle_notify()
    if mode == "sync-rules":
        return handle_sync_rules()
    if mode == "digest":
        return handle_digest()
    return handle_hook()


if __name__ == "__main__":
    raise SystemExit(main())

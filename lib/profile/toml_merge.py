#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
import math
import sys
from datetime import date, datetime, time
from pathlib import Path
from typing import Any

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib  # type: ignore[no-redef]


def load_toml(path: Path) -> dict[str, Any]:
    with path.open("rb") as handle:
        data = tomllib.load(handle)
    if not isinstance(data, dict):
        raise TypeError(f"{path} did not parse to a table")
    return data


def deep_merge(left: dict[str, Any], right: dict[str, Any]) -> dict[str, Any]:
    merged = copy.deepcopy(left)
    for key, value in right.items():
        if isinstance(merged.get(key), dict) and isinstance(value, dict):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = copy.deepcopy(value)
    return merged


def format_key_segment(segment: str) -> str:
    if segment and all(char.isalnum() or char in "-_" for char in segment):
        return segment
    return json.dumps(segment, ensure_ascii=False)


def format_key_path(parts: tuple[str, ...]) -> str:
    return ".".join(format_key_segment(part) for part in parts)


def format_inline_table(value: dict[str, Any]) -> str:
    items = []
    for key in sorted(value):
        items.append(f"{format_key_segment(key)} = {format_value(value[key])}")
    return "{ " + ", ".join(items) + " }"


def format_list(values: list[Any]) -> str:
    rendered = ", ".join(format_value(value) for value in values)
    return f"[{rendered}]"


def format_float(value: float) -> str:
    if math.isnan(value) or math.isinf(value):
        raise TypeError("NaN and infinity are not supported in TOML output")
    return repr(value)


def format_value(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return format_float(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, time):
        return value.isoformat()
    if isinstance(value, list):
        return format_list(value)
    if isinstance(value, dict):
        return format_inline_table(value)
    raise TypeError(f"Unsupported TOML value type: {type(value).__name__}")


def emit_table(lines: list[str], table_path: tuple[str, ...], table: dict[str, Any]) -> None:
    scalar_items = []
    nested_tables = []

    for key in sorted(table):
        value = table[key]
        if isinstance(value, dict):
            nested_tables.append((key, value))
        else:
            scalar_items.append((key, value))

    if table_path:
        lines.append(f"[{format_key_path(table_path)}]")

    for key, value in scalar_items:
        lines.append(f"{format_key_segment(key)} = {format_value(value)}")

    if table_path and (scalar_items or nested_tables):
        lines.append("")

    for index, (key, value) in enumerate(nested_tables):
        emit_table(lines, table_path + (key,), value)
        if index != len(nested_tables) - 1 and lines and lines[-1] != "":
            lines.append("")


def dump_toml(data: dict[str, Any]) -> str:
    lines: list[str] = []

    top_scalars = {}
    top_tables = {}
    for key in sorted(data):
        value = data[key]
        if isinstance(value, dict):
            top_tables[key] = value
        else:
            top_scalars[key] = value

    for key in sorted(top_scalars):
        lines.append(f"{format_key_segment(key)} = {format_value(top_scalars[key])}")

    if top_scalars and top_tables:
        lines.append("")

    for index, key in enumerate(sorted(top_tables)):
        emit_table(lines, (key,), top_tables[key])
        if index != len(top_tables) - 1 and lines and lines[-1] != "":
            lines.append("")

    while lines and lines[-1] == "":
        lines.pop()

    return "\n".join(lines) + "\n"


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("Usage: toml_merge.py OUTPUT INPUT...", file=sys.stderr)
        return 1

    output_path = Path(argv[1])
    input_paths = [Path(argument) for argument in argv[2:]]

    merged: dict[str, Any] = {}
    for input_path in input_paths:
        merged = deep_merge(merged, load_toml(input_path))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(dump_toml(merged), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

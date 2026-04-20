# Our-Side Inventory Queries

The "Us" column in the comparison table and the "Our gap" field in each idea entry must be grounded in the actual current codebase, not prose memory or training-data recall. Use the codebase-memory MCP tools first, and only fall back to direct file tools when the graph is insufficient.

## First step: make sure the graph is indexed

If `search_graph` returns nothing for obvious queries, the project hasn't been indexed. Run `index_repository` once before continuing.

## Query patterns by subsystem

These are starting points. Adjust `name_pattern` and `label` to the project's actual naming.

### Power management

```
search_graph(name_pattern=".*[Pp]ower.*", label="Function")
search_graph(name_pattern=".*[Ss]leep.*", label="Function")
search_graph(name_pattern=".*[Ww]ake.*", label="Function")
get_architecture(aspects=["power", "sleep"])
```

Files worth reading directly if the graph is thin: any `src/power/`, `src/sleep/`, `src/pm/`, platform-specific `rtc.rs` or `pmu.rs`.

### IPC and synchronization

```
search_graph(name_pattern=".*[Cc]hannel.*", label="Type")
search_graph(name_pattern=".*[Ss]ignal.*", label="Type")
search_graph(name_pattern=".*[Ww]atch.*", label="Type")
search_graph(name_pattern=".*[Mm]utex.*", label="Type")
```

### Logging and observability

```
search_graph(name_pattern=".*[Ll]og.*", label="Function")
search_graph(name_pattern=".*[Tt]race.*", label="Function")
```

Look for `defmt`, `log`, `tracing`, `slog` imports in dependency manifest to identify the logging stack.

### State machines

```
search_graph(name_pattern=".*[Ss]tate.*", label="Enum")
search_graph(name_pattern=".*[Ff][Ss]m.*", label="Type")
trace_path(function_name="<central state function>", mode="calls")
```

### Storage / persistence

```
search_graph(name_pattern=".*[Pp]ref.*")
search_graph(name_pattern=".*[Ss]torage.*")
search_graph(name_pattern=".*[Pp]artition.*")
```

### Driver model

```
search_graph(label="Trait")   # Rust projects often have per-peripheral traits
search_graph(label="Interface")  # Kotlin/Java/TS
search_graph(label="Struct", name_pattern=".*Driver.*")
```

### Task / scheduling

```
search_graph(name_pattern=".*[Tt]ask.*")
search_graph(name_pattern=".*[Ss]upervisor.*")
search_graph(name_pattern=".*[Ss]pawn.*")
```

## When the graph is insufficient

Fall back to direct tools in this order:

1. **Glob** — find files by convention (`**/power/**`, `**/sleep/**`, etc.).
2. **Grep** — search for specific string literals, error messages, or non-code references.
3. **Read** — read the specific file you already identified.

If you're reaching for Grep before trying the graph, stop and try the graph first. The graph has structure the text search can't replicate.

## What a "grounded" claim looks like

Every "Us" cell and every "Our gap" field must cite *something*. Acceptable forms:

- `` `src/power/rails.rs:42` `` — specific file and line.
- `` `src/power/rails.rs` — `RailManager` `` — specific file and type.
- `` `power::RailManager` from the graph `` — graph node reference.

Unacceptable:

- "We don't have this" (no citation — prove it).
- "We have X somewhere" (vague).
- "Based on my understanding of the codebase" (prose memory).

If you can't produce a citation after a real search pass, write "Absent — no match for `<pattern>` in graph or codebase" and treat that as the evidence. That's honest and load-bearing; fabricated claims are not.

## Project-context detection

Before any subsystem queries, read these files to learn the project's stack:

- `CLAUDE.md` and `.claude/CLAUDE.md` — conventions, stack, constraints.
- `AGENTS.md` if present.
- The package/dependency manifest (`Cargo.toml`, `package.json`, `pyproject.toml`, `build.gradle`).
- `README.md` for the elevator pitch.
- `docs/architecture/` index if present.

Use the detected language, runtime, and hardware target when writing the "Proposed" fields — never hardcode a stack assumption.

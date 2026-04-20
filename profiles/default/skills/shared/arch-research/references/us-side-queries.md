# Our-Side Inventory Queries

The "Us" column in the comparison table and the "Our gap" field in each idea entry must be grounded in the actual current project, not prose memory or training-data recall. Use the project's code-intelligence tools first, and only fall back to direct file tools when the structured tools are insufficient.

## Tool preference order

1. **Codebase knowledge graph** — `codebase-memory-mcp`, Sourcegraph, LSIF, or whatever the project provides. Start here.
2. **Language server / LSP** — `workspaceSymbol`, `documentSymbol`, `findReferences`, `goToDefinition`. Use for precise symbol navigation when the graph is missing or thin.
3. **Direct file tools** — `Glob`, `Grep`, `Read`. Fall back when the graph returns insufficient results or the target is a non-code file (config, schema, docs, fixtures).

If the graph returns nothing for obvious queries, the project hasn't been indexed. Run `index_repository` (or equivalent) once before continuing.

## Query patterns by concern category

These are starting points. Adjust `name_pattern` and `label` to the project's actual naming. Pick the categories that apply to the focus lens — not every project has every category.

### Data model and persistence

```
search_graph(label="Struct")                # or Type, Class, Record, Model
search_graph(name_pattern=".*[Ss]tore.*")
search_graph(name_pattern=".*[Rr]epository.*")
search_graph(name_pattern=".*[Dd]ao.*")
search_graph(name_pattern=".*[Ss]chema.*")
```

Direct-read fallbacks: migrations directory, ORM model files, schema definitions (`.sql`, `.proto`, `.graphql`, `schema.rb`, `models.py`).

### Error handling and result types

```
search_graph(name_pattern=".*Error.*", label="Type")
search_graph(name_pattern=".*Result.*", label="Type")
search_graph(name_pattern=".*Exception.*", label="Type")
search_graph(name_pattern=".*handle_.*error.*", label="Function")
```

Direct-read fallbacks: central error module, `errors.rs`, `exceptions.py`, top-level error middleware.

### Request/response lifecycle or entry points

```
search_graph(label="Route")                 # HTTP/RPC handlers
search_graph(label="Endpoint")
search_graph(name_pattern=".*[Hh]andler.*")
search_graph(name_pattern="main|run|start", label="Function")
get_architecture(aspects=["entrypoints"])
```

### Configuration and feature flags

```
search_graph(name_pattern=".*[Cc]onfig.*", label="Type")
search_graph(name_pattern=".*[Ff]lag.*")
search_graph(name_pattern=".*[Ss]etting.*")
```

Direct-read fallbacks: `config/`, `settings.py`, `.env.example`, feature-flag definitions.

### Concurrency and coordination

```
search_graph(name_pattern=".*[Cc]hannel.*", label="Type")
search_graph(name_pattern=".*[Mm]utex.*|.*[Ll]ock.*", label="Type")
search_graph(name_pattern=".*[Qq]ueue.*", label="Type")
search_graph(name_pattern=".*[Tt]ask.*|.*[Ww]orker.*")
search_graph(name_pattern=".*[Aa]ctor.*")
```

### State machines and lifecycle

```
search_graph(label="Enum")                  # state enums are often here
search_graph(name_pattern=".*[Ss]tate.*", label="Type")
search_graph(name_pattern=".*[Ff][Ss]m.*")
trace_path(function_name="<central transition function>", mode="calls")
```

### Plugin / extension / registry systems

```
search_graph(name_pattern=".*[Rr]egistry.*")
search_graph(name_pattern=".*[Pp]lugin.*")
search_graph(name_pattern=".*[Ee]xtension.*")
search_graph(name_pattern=".*register_.*", label="Function")
```

### Testing and verification surface

```
search_graph(name_pattern=".*[Tt]est.*", label="Function")
search_graph(name_pattern=".*[Ff]ixture.*")
search_graph(name_pattern=".*[Mm]ock.*")
```

Direct-read fallbacks: `tests/`, `__tests__/`, `spec/`, CI config (`.github/workflows/`, `.gitlab-ci.yml`).

### Logging, tracing, metrics

```
search_graph(name_pattern=".*[Ll]og.*", label="Function")
search_graph(name_pattern=".*[Tt]race.*|.*[Ss]pan.*")
search_graph(name_pattern=".*[Mm]etric.*|.*[Ss]tat.*")
```

Direct-read fallbacks: dependency manifest to identify the logging stack (`slog`, `tracing`, `pino`, `winston`, `structlog`, `logrus`, etc.).

### Domain-specific categories

Don't stop at the generic list — the focus lens drives what to query for. Examples:

- **Rendering / UI**: search for `Component`, `Layout`, `Renderer`, `Paint`, `Widget`.
- **Data pipeline**: search for `Source`, `Sink`, `Operator`, `Stream`, `Batch`.
- **Document conversion**: search for `Parser`, `Encoder`, `Decoder`, `Transformer`, `Codec`.
- **Build system**: search for `Rule`, `Target`, `Dependency`, `Cache`, `Action`.
- **Query engine**: search for `Plan`, `Expression`, `Scan`, `Optimizer`.

Pick 3–5 categories that best match the focus lens for each invocation — don't run every query above.

## What a "grounded" claim looks like

Every "Us" cell and every "Our gap" field must cite *something*. Acceptable forms:

- `` `src/path/to/file.ext:42` `` — specific file and line.
- `` `src/path/to/file.ext` — `SymbolName` `` — specific file and symbol.
- `` `module::path::Symbol` (from the graph) `` — graph node reference.

Unacceptable:

- "We don't have this" (no citation — prove it).
- "We have X somewhere" (vague).
- "Based on my understanding of the codebase" (prose memory).

If you can't produce a citation after a real search pass, write "Absent — no match for `<pattern>` in graph or codebase" and treat that as the evidence. That's honest and load-bearing; fabricated claims are not.

## Project-context detection

Before any subsystem queries, read these files to learn the project's stack and domain:

- `CLAUDE.md` and `.claude/CLAUDE.md` — conventions, stack, constraints.
- `AGENTS.md` if present.
- The package/dependency manifest (`Cargo.toml`, `package.json`, `pyproject.toml`, `build.gradle`, `pom.xml`, `mix.exs`, `go.mod`, `Gemfile`, etc.).
- `README.md` for the elevator pitch.
- `docs/architecture/` or equivalent, if present.

Use the detected language, runtime, framework, and domain when writing the "Proposed" fields. The "Us" cells should reference actual project-specific types and modules, not generic placeholders — `HttpHandler` is better than "the request handler", `UserRepository` is better than "the user store".

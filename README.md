# sv-skill

SystemVerilog RTL house style, as three coupled deliverables:

- **`src/svstyle/rules.toml`** — the rules database, single source of truth.
- **`svstyle`** — a ruff-like CLI: `svstyle check` / `svstyle fix` / `svstyle rules`.
  It owns the comment/header rules no existing tool covers and orchestrates
  `verible-verilog-format`, `verible-verilog-lint` and `verilator --lint-only`
  behind one report with rule IDs.
- **`skill/systemverilog-rtl/`** — the Claude Code skill, whose rule references
  are generated from the same TOML so the two never drift.

Style lineage: lowRISC (`_i/_o`, `clk_i`, `rst_ni`, `_q/_d`, CamelCase params,
100 columns; 4-space indent is ours).

## Status

All phases and the [roadmap](docs/roadmap.md) done: with the skill 9/9 evals pass every
check (100%, vs. 52% without). Design spec:
[`docs/superpowers/specs/2026-09-22-sv-skill-design.md`](docs/superpowers/specs/2026-09-22-sv-skill-design.md).

## Development

```sh
uv sync --extra dev
uv run pytest
uv run svstyle --help
```

## Install as a tool

```sh
uvx --from /path/to/sv-skill svstyle check rtl/*.sv
```

External tools used when present: `verible-verilog-format` / `verible-verilog-lint`
(pinned `v0.0-3946`), `verilator`. `svstyle check --no-external` skips them.

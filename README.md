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

Ready for new RTL written with the skill: on 35 classic and hard blocks the
skill's RTL is functionally correct and one `svstyle fix` closes the style
(round 11: 5/5). Running `svstyle` over existing third-party code works but
is noisy and has known gaps; see the [roadmap](docs/roadmap.md). Design spec:
[`docs/superpowers/specs/2026-09-22-sv-skill-design.md`](docs/superpowers/specs/2026-09-22-sv-skill-design.md).

## Development

```sh
uv sync --extra dev
uv run pytest
uv run svstyle --help
```

## Install

The CLI, editable so it tracks the repo:

```sh
uv tool install --editable /path/to/sv-skill
```

The skill, as a symlink so the skill can find the repo (and `svstyle`) from
its real path:

```sh
ln -s /path/to/sv-skill/skill/systemverilog-rtl ~/.claude/skills/systemverilog-rtl
```

Claude Code then loads it for any SystemVerilog request ("design a 2-flop
synchroniser", "review this FIFO"), no need to name it.

External tools used when present: `verible-verilog-format` / `verible-verilog-lint`
(pinned `v0.0-3946`), `verilator`, and `yosys` for `--synth`.
`svstyle check --no-external` skips them; `fix` needs Verible.

## Usage

```sh
svstyle check rtl/                # report; exit 1 on any MUST finding
svstyle fix rtl/ --diff           # show what fix would change; exit 1 if anything
svstyle fix rtl/                  # format, add header/comments, modernise legacy code
svstyle check rtl/ --synth        # also run Yosys (combinational loops)
svstyle rules --id PRT-003        # one rule in full
```

```
rtl/fifo.sv:14:1: DOC-003 `rst_ni` has no trailing // comment [fix available]
2 findings (MUST 1, SHOULD 1)
```

Per-project `select` / `ignore` / `include` go in `.svstyle.toml`; a finding is
waived inline with `// svstyle: waive DOC-004 <reason>`.

More:

- [`tooling.md`](skill/systemverilog-rtl/references/tooling.md) — every
  option, JSON output, exit codes, which tool enforces which rule, waivers.
- [`style-guide.html`](docs/style-guide.html) — all rules with rationale
  (generated from `rules.toml`).

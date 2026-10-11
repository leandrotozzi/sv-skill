# sv-skill

[![ci](https://github.com/leandrotozzi/sv-skill/actions/workflows/ci.yml/badge.svg)](https://github.com/leandrotozzi/sv-skill/actions/workflows/ci.yml)

SystemVerilog RTL house style, as three coupled deliverables:

- **`src/svstyle/rules.toml`**: the rules database (82 rules), single source of truth.
- **`svstyle`**: a ruff-like CLI: `svstyle check` / `svstyle fix` / `svstyle rules`.
  It owns the comment/header rules no existing tool covers and runs
  `verible-verilog-format`, `verible-verilog-lint`, `verilator --lint-only` and
  Yosys behind one report with rule IDs.
- **`skill/systemverilog-rtl/`**: the Claude Code skill, whose rule references
  are generated from the same TOML so the two never drift.

Style lineage: lowRISC (`_i/_o`, `clk_i`, `rst_ni`, `_q/_d`, CamelCase params,
100 columns; 4-space indent is ours).

## Why not just Verible?

| | Verible alone | svstyle |
|---|---|---|
| Rule IDs you can cite and waive | tool rule names | `PRT-003`, waivers need a reason |
| Headers, port/declaration/block comments | no | checked, and inserted by `fix` |
| Verilator `-Wall`, Yosys loops/drivers | separate tools | one report, same IDs |
| Legacy `reg`/`always @*` to `logic`/`always_comb` | no | only where the token edit keeps the meaning |
| Rules, docs and the AI skill in sync | n/a | generated from one TOML, CI drift gate |

## Status

On 25 classic blocks, three runs each (75 runs), RTL written with the skill
was functionally correct 74/75 against self-checking testbenches, and its
first `svstyle check` was clean 72/75. The Yosys subset in the skill is
backed by 149 one-construct probes proved with `sat`. Running `svstyle` over
existing third-party code works but is noisy; see the [roadmap](https://github.com/leandrotozzi/sv-skill/blob/main/docs/roadmap.md).

## Install

The skill, as a Claude Code plugin (from inside Claude Code):

```
/plugin marketplace add leandrotozzi/sv-skill
/plugin install systemverilog-rtl@sv-skill
```

Claude Code then loads it for any SystemVerilog request ("design a 2-flop
synchroniser", "review this FIFO"), no need to name it. The plugin also adds a
non-blocking hook that runs `svstyle check --no-external` after each `.sv`
edit. Without the plugin system, copy or symlink `skill/systemverilog-rtl`
into `~/.claude/skills/`.

The CLI:

```sh
uv tool install svstyle        # or: pipx install svstyle
uvx svstyle check rtl/         # or run it once without installing
```

External tools used when present: `verible-verilog-format` / `verible-verilog-lint`
(pinned `v0.0-3946`), `verilator`, and `yosys` for `--synth`.
`svstyle check --no-external` skips them; `fix` needs Verible.

With [pre-commit](https://pre-commit.com):

```yaml
- repo: https://github.com/leandrotozzi/sv-skill
  rev: v0.1.0
  hooks:
    - id: svstyle-check   # and/or svstyle-fix
```

## Development

```sh
uv sync --extra dev
uv run pytest -n auto
uv run svstyle rules --check
```

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

- [`tooling.md`](https://github.com/leandrotozzi/sv-skill/blob/main/skill/systemverilog-rtl/references/tooling.md) — every
  option, JSON output, exit codes, which tool enforces which rule, waivers.
- [`style-guide.html`](https://leandrotozzi.github.io/sv-skill/) — all rules with rationale
  (generated from `rules.toml`).

## Licence

MIT, see [LICENSE](https://github.com/leandrotozzi/sv-skill/blob/main/LICENSE).

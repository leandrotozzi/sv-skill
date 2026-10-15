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

What the skill buys is style and clean synthesis, not more correct RTL:

| | without skill | with skill |
|---|---|---|
| VerilogEval v2, pass@1 (155 problems, adjudicated) | 149 | 147, equal after review |
| VerilogEval v2, `svstyle check` clean | 0 | 155 |
| VerilogEval v2, cost per problem | $0.10 | $0.35 |
| Classic blocks, Yosys synthesis with no warning and no latch | 22/24 | 35/35 |

The two synthesis rows count different sets (24 classics were run without
the skill, 35 with it), and the two misses are not bugs: fir and cordic
keep a memory as a list of flops instead of inferring a RAM.

On 25 of those classics, three runs each, RTL written with the skill was
functionally correct 74/75 against self-checking testbenches. The Yosys
subset in the skill is backed by 149 one-construct probes proved with `sat`,
four of which synthesise wrong with no error. Running `svstyle` over existing
third-party code works but is noisy. Open work is in the
[roadmap](https://github.com/leandrotozzi/sv-skill/blob/main/docs/roadmap.md),
every measurement in the
[history](https://github.com/leandrotozzi/sv-skill/blob/main/docs/history.md).

## What it looks like

One prompt, Opus 5.5, with and without the skill (eval `updown-counter`,
round 1): *"Write an up/down counter in SystemVerilog, updown_counter.sv.
Parameter Width (default 8). Ports: clk_i, rst_ni (asynchronous, active low),
en_i, load_i, load_val_i[Width-1:0], up_i, count_o[Width-1:0]. ..."* Both
match the reference model cycle for cycle.

Without the skill: correct, and `svstyle check` reports 13 findings (11 MUST)
-- no header, no comments, 2-space indent, no `` `default_nettype none``.

```systemverilog
// Up/down counter with synchronous load, wrapping modulo 2**Width.
module updown_counter #(
  parameter int unsigned Width = 8
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic             en_i,
  input  logic             load_i,
  input  logic [Width-1:0] load_val_i,
  input  logic             up_i,
  output logic [Width-1:0] count_o
);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      count_o <= '0;
    end else if (load_i) begin
      count_o <= load_val_i;
    end else if (en_i) begin
      count_o <= up_i ? count_o + 1'b1 : count_o - 1'b1;
    end
  end

endmodule
```

With the skill: the first `check` reports one SHOULD, the `<Company>`
placeholder, which a `.svstyle.toml` with `company = "..."` fills in.

```systemverilog
// Copyright (c) 2026 <Company>
// All rights reserved
//
// Description:
//   Loadable up/down counter. Each clock, load_i loads load_val_i (load has
//   priority over enable); otherwise en_i steps the count up by one when up_i
//   is high and down by one when it is low, wrapping modulo 2**Width.
//   count_o is the register itself: it changes one cycle after the inputs.
//   Reset clears the count to zero.

`default_nettype none

`include "assert_macros.svh"

module updown_counter #(
    parameter int unsigned Width = 8  // Counter width in bits; at least 1
) (
    input  logic             clk_i,       // System clock
    input  logic             rst_ni,      // Asynchronous reset, active-low
    input  logic             en_i,        // Step the count this cycle (ignored while load_i)
    input  logic             load_i,      // Load load_val_i this cycle; wins over en_i
    input  logic [Width-1:0] load_val_i,  // Value loaded when load_i is high
    input  logic             up_i,        // Step direction: 1 counts up, 0 counts down
    output logic [Width-1:0] count_o      // Current count, registered
);
    // Width must be positive: a zero-width counter has no meaning.
    if (Width < 1) begin : gen_width_check
        $error("Width must be at least 1");
    end

    logic [Width-1:0] count_q, count_d;  // Count register and its next value

    // Next count: load has priority, then a wrapping step in the chosen direction.
    always_comb begin
        count_d = count_q;
        if (load_i) begin
            count_d = load_val_i;
        end else if (en_i) begin
            if (up_i) begin
                count_d = count_q + Width'(1);
            end else begin
                count_d = count_q - Width'(1);
            end
        end
    end

    // Count register, cleared by reset.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            count_q <= '0;
        end else begin
            count_q <= count_d;
        end
    end

    assign count_o = count_q;

    // The count is never X once out of reset (VER-002).
    `ASSERT_KNOWN(CountKnown_A, count_o)
endmodule

`resetall
```

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
`svstyle check --no-external` skips them; `fix` needs Verible. Where nothing
can be installed (claude.ai, the API), the skill still writes to the rules
and says that nothing was checked.

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
waived inline with `// svstyle: waive DOC-004 <reason>`. To adopt the style
gradually, start without the comment and header rules:

```toml
# .svstyle.toml
ignore = ["DOC-001", "DOC-003", "DOC-004", "DOC-005", "DOC-006"]
```

More:

- [`tooling.md`](https://github.com/leandrotozzi/sv-skill/blob/main/skill/systemverilog-rtl/references/tooling.md) — every
  option, JSON output, exit codes, which tool enforces which rule, waivers.
- [`style-guide.html`](https://leandrotozzi.github.io/sv-skill/) — all rules with rationale
  (generated from `rules.toml`).

## Licence

MIT, see [LICENSE](https://github.com/leandrotozzi/sv-skill/blob/main/LICENSE).

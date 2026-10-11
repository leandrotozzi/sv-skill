# Changelog

## Unreleased

- The skill simulates before it is done: `assets/skeleton_tb.sv`, a
  self-checking Verilator testbench template, `references/testbench-verilator.md`,
  and a bounded "Simulate" step and "Done means" item in `SKILL.md`.
- The PostToolUse hook skips testbenches (`tb/` and `*_tb.sv`).
- Evals: 15 planted bugs for five classics in `evals/files/classics/bugs/`,
  and `grade.py`'s `tb_catches` runs the output's own testbench against them.
- `evals/run.py`: run and grade any eval through `claude -p`, with and
  without the skill; `evals/README.md`.

## 0.1.0 — 2026-10-10

First release.

- `rules.toml`: 82 rules in 12 categories, the single source for the CLI, the
  skill's rule references and `docs/style-guide.html`; `svstyle rules --check`
  keeps the three in sync.
- `svstyle check`: house checks plus Verible lint, Verilator `-Wall` and,
  with `--synth`, Yosys, in one report with rule IDs; JSON output, baselines,
  inline waivers with a required reason, `.svstyle.toml`.
- `svstyle fix`: Verible formatting, headers and comments, and legacy
  Verilog modernised (`reg`/`wire` to `logic`, `always_ff`/`always_comb`)
  only where the token edit provably keeps the meaning.
- The `systemverilog-rtl` Claude Code skill: templates that pass the
  checker, the Yosys subset, fixed-interface and review workflows.
- Evals: 35 designs graded by self-checking testbenches, 149 Yosys probes.

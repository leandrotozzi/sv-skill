# Changelog

## Unreleased

- `svstyle fix` honours `select` / `ignore` in `.svstyle.toml`: it no longer
  inserts headers or comments for rules `check` ignores.
- The skill says what to do without the tools: write to the rules, format by
  hand, and report that nothing was run; name any tool `check` skipped.
- `docs/roadmap.md` holds open work only; the record moved to `docs/history.md`.
- The skill skips the testbench for a small block (one clock, no memory,
  no protocol, simple logic, under about 40 lines) and says so.
- The skill loads less up front: reviewing and legacy code moved to
  `references/existing-code.md`, multi-clock guidance to
  `references/multi-clock.md`, and the CDC rules to a generated
  `references/rules-cdc.md`; `SKILL.md` says when to read each.
- The skill simulates before it is done: `assets/skeleton_tb.sv`, a
  self-checking Verilator testbench template, `references/testbench-verilator.md`,
  and a bounded "Simulate" step and "Done means" item in `SKILL.md`.
- The PostToolUse hook skips testbenches (`tb/` and `*_tb.sv`).
- Evals: 15 planted bugs for five classics in `evals/files/classics/bugs/`,
  and `grade.py`'s `tb_catches` runs the output's own testbench against them.
- `evals/run.py`: run and grade any eval through `claude -p`, with and
  without the skill; `evals/README.md`.
- `synth = "yosys-slang"` in `.svstyle.toml`: `check` reads with the
  yosys-slang plugin (`read_slang`), and the skill loads the much shorter
  `references/synth-yosys-slang.md`.
- CI runs the 149 Yosys probes on both frontends, and a non-blocking job
  checks the `fix` goldens against the latest Verible.

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

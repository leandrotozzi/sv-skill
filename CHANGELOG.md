# Changelog

## Unreleased

- `check --github` prints findings as GitHub Actions annotations, so they show
  on the pull request's diff (MUST an error, SHOULD a warning).
- pyslang 12 is supported (`pyslang>=11,<13`): the whole suite passes on it.
- Verible `v0.0-4296` is accepted beside `v0.0-3946`: neither warns of drift,
  and CI runs the whole suite on both.
- `check --synth` with yosys-slang reports a read error on its line, not
  line 1: the slang run no longer passes `-q`, which hid slang's diagnostics.
- The README gives the skill's cost as a fixed part per session plus a
  part per module, measured both ways.

## 0.1.0 — 2026-10-15

First release.

- The skill simulates a small block that promises fairness or ordering (an
  arbiter, a scheduler) instead of skipping its testbench, and never writes
  one comment above a group of declarations.
- `ASSERT`'s reset-pulse guard is tested on `##n` properties too; the macro
  comment no longer says they are exposed.
- LNG-001 no longer reads a closing `` `default_nettype wire`` as a `wire`
  declaration; `fix` replaces that line with `` `resetall`` instead of
  appending one that Verible joined onto it.
- `check` and `fix` are faster again: `parse` visits the tree once, indexes
  children instead of iterating them (pyslang's iterator is the slow part),
  and skips macro/include lookups where they cannot matter; Verible's
  format check runs files in parallel; startup imports less. On 256 Ibex
  files `check` 21 s to 9 s and `fix` 30 s to 21 s; on one file `check`
  0.39 s to 0.32 s. Output unchanged on 538 files.
- `fix` is about a third faster: a pass reuses the previous pass's parse,
  the last pass neither reformats nor reparses, and the token invariant skips
  the alignment when no token changed. Output unchanged on 173 sample files.
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

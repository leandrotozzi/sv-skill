# Evals

| File | What |
|---|---|
| `evals.json` | skill evals 1–13: prompts, input files, per-eval checks |
| `classics.json` | 35 classic blocks (101–), each graded against a reference by `files/classics/<name>_tb.sv` |
| `files/classics/bugs/` | planted-bug variants of five classics; `tb_catches` runs the output's own testbench on them |
| `run.py` | runs evals through `claude -p`, with and without the skill, grades, prints a table |
| `grade.py` | every check by a tool: `svstyle`, Verilator, Yosys, equivalence and review checks |
| `verilogeval.py` | VerilogEval v2 spec-to-RTL subset, same runner, graded by the dataset's testbenches |
| `cost.py`, `compare.py` | cost from transcripts and side-by-side HTML of skill-creator iterations |
| `trigger_evals.json` | skill-description trigger evals |
| `yosys-probes/` | one-construct Yosys probes behind `synth-yosys.md` |

## Run

```sh
uv run python evals/run.py classics --ids 101,105 --runs 3
uv run python evals/run.py evals --ids 10,11,12 --configs with_skill
```

Each run starts in an empty directory outside the repo (`--out`, default
`$TMPDIR/sv-evals`) with `--setting-sources project`, so no user skill, hook
or `CLAUDE.md` leaks in; `with_skill` adds this repo with `--plugin-dir`.
Inside the repo it would not work: Claude Code refuses writes into a plugin
directory. Input files are copied to the path the prompt names.

```
OUT/eval-<name>/eval_metadata.json
OUT/eval-<name>/<config>/run-N/outputs/       what the model wrote, plus claude.json
                                              (result, cost) and transcript.jsonl
OUT/eval-<name>/<config>/run-N/grading.json   every check, with evidence
OUT/eval-<name>/<config>/run-N/timing.json    cost (USD), turns, seconds
OUT/results.md                                one row per eval and config
```

`grading.json` also holds `metrics`: `depth`, the cells on the longest
flop-to-flop path of the flattened design (`ltp -noff`), and `transistors`
(`stat -tech cmos`). They are numbers, not checks. `results.md` gives their
median over the runs whose RTL matches the reference, and with_skill over
without_skill per eval and as a geomean, marked a regression above 1.25 for
one eval or 1.10 overall. Why this metric and not STA:
[`docs/research/timing-metric.md`](../docs/research/timing-metric.md).

`--synth yosys-slang` writes that key to each run's `.svstyle.toml`, as a
project would: the skill loads `synth-yosys-slang.md`, and both `svstyle` and
the grader's own Yosys check read with `read_slang` (put a Yosys with the
plugin, e.g. the OSS CAD Suite's, first on `PATH`).

`grade.py DIR` also grades a skill-creator iteration (`<config>/outputs`
moved to `run-1/outputs`).

## Tools

Results depend on these; record them with any number you publish.

| Tool | Local | CI (OSS CAD Suite 2026-10-07) |
|---|---|---|
| Verible | v0.0-3946 | v0.0-3946 and v0.0-4296 |
| Verilator | 5.052 | 5.053 |
| Yosys | 0.66 | 0.69 |
| Icarus Verilog | 13.0 (VerilogEval only; see `verilogeval.py`) | — |

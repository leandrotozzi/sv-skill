# Testbenches for Verilator

The "Simulate" step in `SKILL.md`: one self-checking testbench per top
module, built and run once with Verilator 5. It is not RTL: the house rules
and `svstyle` do not apply to it.

## Where it lives

`tb/<name>_tb.sv`, module `<name>_tb`, started from `assets/skeleton_tb.sv`.
Keep `svstyle` off it: check the RTL by name (`svstyle check --synth rtl/*.sv`),
and if the project walks directories, add `exclude = ["tb/*"]` to
`.svstyle.toml`. Do not "fix" a testbench into the house style.

## What a testbench may use that RTL may not

`initial`, delays (`#5`, `@(negedge clk_i)`), tasks and functions that wait,
`automatic`, `int`, `string`, `$display`/`$sformatf`, `$urandom`/`$urandom_range`,
`$value$plusargs`, queues and dynamic arrays, unpacked structs and arrays,
`$fatal`, bare SVA. No classes, `randomize()` or covergroups: Verilator's
support is partial, and none of it is needed here.

## What it checks

- **A model, not the RTL again.** Predict every output from the spec: a
  behavioural model inside the testbench (a few lines of `always` or of
  `step`), or golden vectors when the spec gives them. Write it from the
  prompt, never by copying the RTL's logic, or both share the same bug.
- **Every cycle, with `!==`.** Compare each output on every check, so X and a
  wrong cycle both fail; compare data only while its valid says it is
  meaningful.
- **Edges first, then random.** Directed cases for what the spec names:
  reset, full, empty, overflow, wrap, the maximum and minimum values,
  back-to-back transfers, a stall. Then a few thousand random cycles
  (`$urandom_range` to bias toward the interesting cases), with a reset in
  the middle.
- **Drive at the negedge**, as `step()` does: inputs never change at the
  edge that samples them, so there are no races.
- **A fixed seed.** `+seed=N` (default 1) seeds `$urandom`; the PASS or
  FAIL line prints it, so a failure reruns identically.

## Build and run

```sh
verilator --binary --timing --assert -Wno-fatal --x-assign unique --x-initial unique \
    -I<dir of assert_macros.svh> -Mdir build/tb --top-module <name>_tb rtl/*.sv tb/<name>_tb.sv
build/tb/V<name>_tb +verilator+rand+reset+2
```

`-Wno-fatal` keeps lint warnings from stopping the build (lint is
`svstyle check`'s job). `--x-initial unique` with `+verilator+rand+reset+2`
starts every unreset flop at a random value instead of 0, so a design that
reads one before loading it fails instead of passing by luck. Packages go
first in the file list, as for `check`.

The command above, as written, must build it: no `-D` or `-G` of its own.
To cover several parameter values, instance the DUT once per value inside
the testbench, each with its own model.

## Reading the result

| Output | Meaning |
|---|---|
| `PASS: N checks, seed S`, exit 0 | every check matched and no assertion fired |
| `%Fatal: ... FAIL: E of N checks, seed S, first at cycle C: ...`, exit non-zero | the model and the DUT disagree; the message names the first output that did |
| `%Error: file:line: Assertion failed in <tb>.<dut>.<Name_A>`, then `$stop` | an `` `ASSERT`` in the RTL fired at the time in brackets; the run stops at the first one |
| a build error | the testbench or the RTL does not elaborate together; fix it before reading anything else |

A FAIL is a disagreement, not yet a verdict: read the spec at that cycle and
decide whether the RTL or the model is wrong. Fix that one and rerun once.
If it still fails, stop and report the failing line and your reading of it
to the user; do not keep iterating on the testbench until it passes.

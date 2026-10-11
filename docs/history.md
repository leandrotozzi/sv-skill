# History

What was measured and decided, round by round, from the 2026-09-28 review
on. Open work lives in [`roadmap.md`](roadmap.md); this file is the record
behind it: eval numbers, costs, and why things were or were not done.

Findings from the 2026-09-28 project review, ordered by what lets bad RTL
through today. Each item names the finding and the fix.

## M1 — `check` must not pass broken RTL

- [x] **1. Verilator errors without a code are dropped.** `VERILATOR_RE`
  requires `%Error-CODE:`; elaboration errors print `%Error: file:line:col:`
  and vanish, and Verilator's exit code is ignored. A typo under
  `` `default_nettype none`` exits 0. Fix: match `%Error:` lines as
  `EXT-VLTR-ERROR` at MUST (coded errors too, except MODMISSING); a non-zero
  exit with no located `%Error` becomes an `EXT-VLTR-ERROR` MUST. Verible's
  own syntax errors surface as `EXT-VL-syntax` SHOULD instead of vanishing.
- [x] **2. Synthesis-relevant Verilator warnings are SHOULD.** Only BLKSEQ,
  COMBDLY, MULTIDRIVEN, LATCH, SYNCASYNCNET are mapped; WIDTH*, UNOPTFLAT,
  UNDRIVEN, CASEINCOMPLETE, CASEOVERLAP, PINMISSING, IMPLICIT, SELRANGE,
  ALWCOMBORDER pass as `EXT-VLTR-*` SHOULD, contradicting VER-003. Fix: map
  them to house rules (new ones where none fits).
- [x] **3. `enforcement` holds a single tool.** LNG-007 (CASEINCOMPLETE),
  LNG-008 (WIDTH), LNG-014 (IMPLICIT), STR-001 (DECLFILENAME), PRT-004
  (PINMISSING) cannot name their second enforcer. Fix: optional
  `[rule.also]` table (`verilator = [...]`) of secondary enforcers; new rules
  LNG-015 (widths/selects), LNG-016 (undriven), LNG-017 (unused).
- [x] **1b. The drift gate failed daily.** The generated HTML stamped
  today's date, so `rules --check` (CI) failed on any day after `--gen`.
  Fix: no date in generated output.
- Note: `--lint-only` does not report UNOPTFLAT, so combinational loops wait
  for `check --synth` (item 15).

## M2 — Skill bugs

- [x] **4. `skeleton.sv` asserts KNOWN on an unreset register.**
  `ASSERT_KNOWN(DataKnown_A, data_o)` fires out of reset before the first
  `valid_i`. Fix: `valid_o |-> !$isunknown(data_o)`.
- [x] **5. `tooling.md` waiver example uses `/* */`**, which DOC-007 forbids.
  Fix: `// verilator lint_off UNUSEDSIGNAL`.

## M3 — The DB maps to reality

- [x] **6. `autofix` is wrong outside svstyle rules.** FMT-001/FMT-002 are
  fixed by `svstyle fix` (Verible) but declare `autofix = false`.
- [x] **7. No rule → test link.** Add a test: every rule not enforced by
  `review` has a violation fixture that triggers its ID.
  Done as `tests/test_rule_coverage.py`: one snippet per rule, run end to
  end through `svstyle check`.

## M4 — Mechanise cheap `review` rules (pyslang)

- [x] **8.** LNG-001 (`reg`/`wire`), LNG-009 (`casex`), SYN-001
  (`full_case`/`parallel_case`), PRT-002 (clock then reset first), NAM-003
  (`_in`/`_on`), STR-005 (file-scope import), RST-001 (reset style).
  PRT-004 comes with M1 via PINMISSING, LNG-009 via CASEX. Probed on 194
  Ibex/prim files: one finding, a deliberate synchronous reset. PRT-002
  groups ports per clock domain, as lowRISC CDC modules do.

## M5 — Missing rules for clean synthesis

- [x] **9.** Combinational loops, signed/unsigned mixing and width extension,
  default-`'x` policy, `initial` in RTL, memory inference, unused/undriven
  signals. Done: SYN-005 loops (Yosys, `--synth`), LNG-015 widths/selects,
  LNG-016 undriven, LNG-017 unused (Verilator), LNG-018 signed mixing
  (review: no tool reports it), SYN-006 `initial` (svstyle, SHOULD).
  Not added: a default-`'x` rule (practice genuinely differs; X-optimism is
  a verification-flow decision) and a memory-inference rule (RST-004 plus the
  NAM-004 memory exemption already cover the style side; an inferred-RAM
  eval covers the rest, item 16).

## M6 — `fix` for legacy code

- [x] **10. Token-rewriting fixes.** Keep the token-signature invariant but
  allow a whitelist of substitutions per fix: `reg`→`logic`,
  `always @(*)`→`always_comb`, `always @(posedge …)`→`always_ff` (only when
  every assignment is `<=`), `begin`/`end` insertion (FMT-003), `` `endif``
  labels (DOC-010), drop `generate`/`endgenerate` (GEN-002), add `automatic`.
  Invariant is now a token-edit whitelist; safety is decided from the tree.
  Verified: Yosys formal equivalence on a legacy module (test), 194-file
  Ibex/prim corpus fixed with no invariant breach, idempotent, identical
  Verilator lint before/after. Clocked `always` and `always @(list)` were
  not reported by anyone before; now LNG-002/LNG-003 via svstyle.

## M7 — CLI UX

- [x] **11.** Directories and `-f files.f` filelists as inputs.
- [x] **12.** `.svstyle.toml`: `select`, `ignore`, `include`.
- [x] **13.** Inline waiver for svstyle-owned rules
  (`// svstyle: waive DOC-004 <reason>`), as DOC-009 requires. Covers
  Verible and Verilator findings too; a waiver without a reason is ignored.
- [x] **14.** `fix --diff` exits non-zero when it would change a file.
- [x] **15.** Optional `check --synth` (Yosys `hierarchy -check; proc;
  check -assert`).

## M8 — Evals

- [x] **16.** Brownfield evals: migrate a Verilog-2001 file; find a planted
  latch / width / bit-wise-CDC bug; async FIFO with Gray pointers; ready/valid
  skid buffer (PRT-007); inferred RAM. Written as evals 5-9 with per-eval
  checks in `grade.py` (cycle-for-cycle equivalence testbench, Yosys memory
  inference, regexes), each validated against a passing and a failing
  sample. Run 2026-09-28 (iteration 3, Opus): 100% with the skill, 52%
  without. Functional checks pass in both; the gap is style and tooling.
- [x] **16b. NAM-004 forced filler `_d` signals** (found building eval 6 and
  in the eval runs: skid buffer, RAM read, pulse sync). The rule now checks
  the output side only -- every flop is `_q` -- and never demands a `_d` on
  the right. Corpus: 373 -> 197 findings on Ibex/prim, zero new ones; evals
  unchanged with the skill (100%).
- [x] **16c. NAM-004 false positives on the corpus.** Of 197 findings on
  Ibex/prim, 91 were not violations: 29 output ports registered in place
  (lowRISC does not carry `_q` to the boundary) and 62 optional registers, a
  `_q` flop in one generate branch tied off with `assign` in the other. Both
  are now accepted; 119 findings remain, nearly all flops without `_q`.

## Spec follow-ups (decided 2026-09-28)

- **Verible upgrade: stays on `v0.0-3946`.** It is the newest this Intel Mac
  can run: every macOS release asset from 3946 up to 4296 is arm64-only, and
  the Homebrew tap builds from source pinned at 3946. Going newer means a
  local Bazel build or validating only in CI; revisit when there is a bug to
  fix or an arm64/Linux dev machine.
- **Domain reference files (CDC, handshakes, FSM): not written.** Evals pass
  their functional checks with and without the skill; add one when an eval
  fails on design, not style.
- **Configurable header template: not needed.** `company` in
  `.svstyle.toml` is the only per-project setting anyone has asked for.

## Classic designs, one-pass style (2026-10-05)

Ten classic blocks (`evals/classics.json`: FSM, counter, FIR, fixed-point
add/mul, arbiter, CORDIC, CRC-32, divider, UART RX), each with a reference
model or self-checking testbench validated against planted bugs. Opus 5.5,
one run per configuration. Functionally correct 10/10 with and without the
skill; the skill's value is the house style, at about +$0.08 and +20 s per
block. Goal: the RTL the skill writes is close enough that one `svstyle fix`
closes the style, with no second LLM round.

| Round | Change | Style closed in the first `fix` + `check` |
|---|---|---|
| 1 | -- | 6/10 |
| 2 | `references/synth-yosys.md`, loaded when `synth = "yosys"` | 8/10 |
| 3 | DOC-004 accepts the comment above a multi-line or overlong declaration; LNG-017 note | 7/10 |
| 4 | `fix` moves a lone comment above a short declaration to its end; rounding idiom | **10/10** |

Round 5 adds five variants (`lzc` combinational with no clock, `debounce-bank`
two modules and a generate loop from a Spanish prompt, `csr-block` with a
company name, `alu-pkg` enum and packed-struct ports from a package, `lfsr`
restricted parameter), with skill only: 5/5 correct and every check passed;
style closed in the first `fix` + `check` 4/5, about $0.33 and 80 s per block.
`csr-block` created `.svstyle.toml`, so its header names the company. The
miss, `alu-pkg`, found two gaps, both fixed: Yosys rejects struct assignment
patterns (`'{f: a}`, `'{a, b}`; now in `synth-yosys.md`), and Verible's
NAM-004 flagged a struct flop written field by field (`s_q.f <=`; now
accepted). Rerun of `alu-pkg` after both fixes: one `check`, 10/10, so 5/5.
`lzc` carries no `ASSERT_KNOWN`: the macros need a clock.

Left open: a single comment above two declarations still leaves the second
with a `TODO` (no mechanical fix without inventing text); `<Company>` stays a
SHOULD until the project has a `.svstyle.toml`.

Round 6 (2026-10-06) adds ten harder blocks, skill only, each graded by a
self-checking testbench validated against five to nine planted bugs:
`async-fifo` (Gray pointers, unrelated clocks), `fwft-fifo` (BRAM with a
registered read, full throughput), `axil-regs` (AXI4-Lite slave),
`spi-master` (all four modes), `axis-downsizer` (32 to 8 with tkeep),
`pkt-arbiter` (round-robin per packet), `secded` (72,64), `fp32-mul` (RNE,
flush to zero), `sort8` (pipelined network), `booth-mul` (radix 4). First
pass: 9/10 correct, style closed in one `check` 6/10 (the extra rounds were
SHOULDs), about $0.53 and 165 s per block. The miss, `async-fifo`, came from
the skill itself: RST-002's reset synchroniser releases two cycles after the
input, and `wfull_o` reset to 0 accepted writes the FIFO then dropped. The
reset checklist in `SKILL.md` now says to reset full/ready flags to their
blocking value; rerun 10/10, so 10/10. `grade.py`'s `yosys_memory` check no
longer fails a design because a small side array (a prefetch buffer) became
flops; a `$mem` cell is enough.

Round 7 closes the three MUSTs that cost an extra `check` in round 6:
`assets/sync_ff.sv`, a synchroniser rank (`NumFlops` 2 or 3, also the reset
synchroniser with `d_i` tied to 1), replaces the hand-written reset
synchronisers that tripped NAM-004 and RST-005; NAM-004 accepts `_nq`, the
active-low flop name NAM-003 asks for (`cs_nq`); and the skill says to keep
each `` `ASSERT`` within 100 columns, since Verible neither wraps nor keeps a
split macro argument. Reruns of `async-fifo`, `spi-master` and
`axis-downsizer`: 10/10 each, one `check` each, so the style closed in the
first `check` 9/10; `axil-regs` ran a second `check` after a clean first.

Round 8 (2026-10-06): all 25 blocks, three fresh runs each with the round-7
skill (75 runs, about $32, 150 s per run). Correct 74/75; the miss,
`cordic` run 3, put a reset synchroniser inside a single-clock block and
dropped the first inputs after reset (`uart-rx` did the same twice and passed
only because its testbench waits). The first `check` that ran on the files
was clean 61/75. The raw count of `check` calls says 42/75, but it counts a
first call that failed on a wrong relative path to `assets/` (the extra
`run-N/` level) and clean re-checks before finishing. The 14 misses fall in
four groups: LNG-017 unused bits (ignored address bits, a last-stage
register nobody reads, an `int` index slicing a narrow vector), Yosys
(`-W'(x)` read as a negative cast; a generate-local signal read from another
iteration), `EXT-VLTR-CMPCONST` on an assertion a power-of-two counter
already guarantees, and LNG-015 index widths. All but LNG-015 now have a line
in `SKILL.md` or `synth-yosys.md`, as do where the reset synchroniser goes
and how to copy the assets. `grade.py`'s Verilator check now honours
`svstyle: waive` lines, which it failed `axil-regs` run 1 for; `cost.py`
reads `run-N/outputs`.

Round 9 (2026-10-06): the same 75 runs with the round-8 skill (about $33,
140 s per run). Correct 74/75; first `check` clean 72/75, up from 61/75. No
LNG-017, `EXT-VLTR-CMPCONST` or misplaced reset synchroniser left. The miss,
`lfsr` run 3, asserted a nonzero seed the spec allows; `SKILL.md` now says
not to assert against legal inputs. The three unclean first checks were all
`sort8`: twice Yosys on a two-dimensional packed array declared inside a
generate or `begin` block (it fails even when read only in that block, so
the old "read from another iteration" line missed it; `synth-yosys.md` now
says so), once LNG-015 on a `localparam` set from a slice.

Rather than keep finding Yosys gaps one eval at a time, `evals/yosys-probes/`
now holds 148 one-construct probes drawn from the Yosys manual, its parser
and the sv-tests results, each proved against a plain-Verilog reference with
`sat`; `run.sh` reruns them on a new Yosys. `synth-yosys.md` is rewritten
from them. Four constructs synthesise wrong with no message: an indexed
typedef of two or more packed dimensions, a packed array of packed structs,
`unique case` without `default` after a default assignment, and a
module-level variable with a non-constant initializer.

Rerun of `sort8` and `lfsr`, three runs each, with that skill: 6/6 correct.
`lfsr` documents the zero-seed lock instead of asserting against it (3/3);
`sort8` hit no Yosys error (0/3, was 2/3) and its first `check` was clean
2/3. The miss was LNG-015 again, a 3-bit table slice stored in a
`localparam int`; `SKILL.md` now says to cast it.

Round 10 (2026-10-06): five new blocks, `isqrt`, `cic-decim`, `pwm-bank`,
`bin2bcd` and `barrel-shift`, each with a testbench validated against 7 to 12
planted bugs and a second correct design. One run with and one without the
skill; a failing run gets the CI report back until it passes. All ten were
correct on the first try. With the skill 4/5 passed in one iteration (6 in
all; `bin2bcd` left a `TODO: describe` under a three-line comment that
`check` does not flag), without it 0/5 (13 in all, and two of those runs read
the repo's rules). One `svstyle fix` on the drafts without the skill passed
0/5: it cannot write the missing comments. Cost without vs. with: $3.59 vs.
$2.12, 4.6 M vs. 2.5 M tokens, 25 vs. 11 minutes. Since then `check` flags a
leftover `TODO: describe` with no fix (only the author can write it), and
`fix` drops the `wire` from `wire logic x` before Verible, which cannot parse
it. `grade.py` builds the equivalence
testbench with `-Wno-fatal`, so a warning such as UNOPTFLAT no longer fails a
correct design.

Round 11 (2026-10-07): five harder blocks, `fp32-add` (RNE, subnormals,
flags), `i2c-master` (clock stretching, repeated START), `systolic-mm` (PE
grid), `pkt-drop-fifo` (store and forward in RAM, drops bad and too-long
packets) and `irq-ctrl` (PLIC-style claim/complete). Each testbench was
validated against 12 to 15 planted bugs and a second correct design. The
question: does the skill plus one `svstyle fix` close everything, with no
second LLM round? The designer wrote once with the skill and ran no tool.
Before `fix` 1/5 passed the style checks, every miss FMT-001/002; after one
`fix` 5/5. Correct 4/5: `pkt-drop-fifo` was right but its own `|=>`
assertion fired on a reset pulse between two edges, since Verilator samples
`disable iff` only at edges. `ASSERT` now also disables on a reset seen since
the last edge (one-cycle properties; `##2` and longer remain exposed), and
`check` skips what the `ASSERT*` macros expand to. Regraded: 5/5 on
everything. The `irq-ctrl` testbench was too strict on a pending read the
edge after a complete, which the spec leaves open; fixed. Open: line 8 of
`assets/sync_ff.sv` is 115 columns, and FMT-001 misses long comment-only
lines (Verible's line-length skips them).

## Review of 2026-10-07: ready for use on new RTL

A code review and a stress test on five outside codebases (pulp
common_cells, verilog-axis, the Kilts labs, two local projects) found bugs
that also hit RTL the skill writes. Fixed, each with a test:

- `fix` turned a resolved net (two `assign`s, or one driving `z`) from
  `wire` into `logic`, which is illegal; such nets now stay `wire`. A
  clocked `always` that an `initial` also writes no longer becomes
  `always_ff`.
- Verible joins consecutive directive lines, and `` `timescale `` then
  swallows the next one (`` `timescale 1ns / 1ps `default_nettype none ``
  does not compile; every verilog-axis file broke). `fix` gives a bare
  `` `timescale `` a trailing comment, the one thing that keeps it on its
  own line, and DOC/`default_nettype` looks for the directive in the
  leading directive lines instead of as a whole line (this also ends the
  exit 4 on empty or comment-only files).
- A non-ASCII character anywhere shifted every rewrite: slang offsets are
  bytes, Python's are characters. Mapped in `parse.py`.
- `check --synth` passed silently on a path with a space, or on any Yosys
  failure without a location; files are now quoted and a non-zero exit is an
  `EXT-YOSYS-read` MUST.
- A non-UTF-8 file crashed with exit 1 (read as "violations"); now exit 2.
  External tools time out after 600 s (exit 2), and `fix` writes through a
  temporary file and a rename.
- `assets/sync_ff.sv` fits 100 columns; a test keeps every template there.

On the 35 eval designs, `check --synth` and `fix --diff` give the same
output before and after.

Then the items left open for existing code, each with a test:

- **Baseline.** `check --baseline FILE [--write-baseline]` reports only
  findings not recorded in FILE, keyed by file, rule and line text (not the
  line number), counted.
- **`.v` files stay Verilog.** `fix` gives them no `logic`, `always_comb` or
  `always_ff`; the findings say to rename to `.sv` first. A directory still
  means its `*.sv`, and the "no input files" error now says so.
- **Licence headers are kept.** A file opening with a comment block that
  names a copyright, licence or SPDX identifier gets a `Description:` block
  appended to it instead of our header stacked on top (DOC-001 text updated).
- **Packages first** for Verilator too, as for Yosys: a package type in a port
  failed to elaborate when the module sorted first. On the 35 eval designs
  this removes a false `EXT-VLTR-ERROR` on `alu.sv`, and Verilator, now
  elaborating further, reports 22 findings it used to hide.
- **NAM-003** no longer advises `_ni` for `x_in`: it offers `x_ni` if
  active-low, `x_i` if not.
- **A `wire` on an `inout` of another file** stays a `wire`: `parse` records
  every module's ports (ANSI and non-ANSI), and `fix` reads all its input
  files first. `.*` connections are not followed.
- **FMT-001 on comment-only lines**, which Verible's line-length skips:
  an svstyle check under `[rule.also]`.
- **Yosys "no driver" is SHOULD on a partial design**, like Verilator's
  MODMISSING, when a module the files instantiate is not among them.
- **`rules --gen/--check` refuse outside a checkout** (exit 2) instead of
  writing into site-packages; the dead Phase 2/3 branches are gone.

Rerunning `fix` on the five outside codebases found three more problems,
now fixed: a `bind` took its DOC-006 comment above the module name, so every
run added another `TODO`; the fix loop stopped once tokens settled, but a moved
comment lets Verible realign and free room for the next one (one more pass
when a comment moved); and `` `default_nettype none `` broke files that use
implicit nets (now not inserted, the finding names them) and bind files, whose
target-scope names Verilator reads as implicit nets (not inserted there either).
After that, on all five: no exit 4, no file Verilator reads worse than
before, every file idempotent. What `fix` still refuses: files that need `-I`
to parse (exit 3) and five that Verible itself cannot format (exit 2).

Then the rest of the list:

- **Speed.** Verible was never the cost (0.3 s of 8 s on a 900-line file):
  `parse` checked "is this node in a macro / does it hold a directive" by
  walking each node's subtree, quadratic in nesting. Now a bisect over
  positions collected once (an `` `include`` counts at its own line); on 522
  corpus files the old and new answers agree on all 185k nodes. And files run
  on every core. `fix` on verilog-axis 61 s -> 12 s, common_cells 35 s -> 6 s;
  `check --no-external` 8 s -> 2 s and 5 s -> 1 s.
- **PRT-003 / PRT-005 duplicates.** Verible's `module-port` (named ports) was
  mapped to PRT-005 (named parameters) and `module-parameter` to LNG-011
  (parameter declarations). Both are off now: svstyle reports ports by
  position under PRT-003 and, new, any parameter by position under PRT-005,
  one finding each (Verible only flagged two or more).
- **`exclude` globs** in `.svstyle.toml`, for files found in a directory or
  filelist; a file named on the command line is always checked.
- **Verible findings name their identifier** (`` `wKeyReg`: Signal name does
  not match ...``), so one line with three bad names is three readable
  findings, not three identical ones.
- **Small ones:** a missing `-I` directory is an error; a Verible parse
  failure in `fix` says "Verible cannot parse line N (slang can)" instead of
  `<stdin>:N`; the summary after an error says so instead of a bare
  "0 findings".

Still open: the difflib alignment in the token invariant is now the largest
cost in `fix` (about a third); `fix` runs `parse` several times per pass.

## Round 12 (2026-10-08): the round-11 blocks with the current skill

The same five blocks and protocol as round 11 (the designer writes once with
the skill and runs no tool; then one `svstyle fix`), after this review's
changes to `check`, `fix` and `SKILL.md`. Before `fix`, 1/5 passed the style
checks, and three of the four misses were FMT-002 alone. After one `fix`, 4/5
passed everything, functional testbench included. The miss, `fp32-add`, named
a signal `small`, a SystemVerilog keyword (charge strength), so the file did
not parse and neither `fix` nor the testbench could run. With the name changed
by hand (not counted) it scored 10/10. Fixed twice: a parse error now names a
keyword used as an identifier, and `SKILL.md` lists the reserved words that
catch people out. The `fp32-add` rerun scored 10/10 after one `fix`, so 5/5.
One caveat on the rerun: its designer read the grader's testbench header to
settle the latency question, which the first run had already answered right.

CI now runs, on GitHub (private repo), with Verilator and Yosys from a pinned
OSS CAD Suite build (Verilator 5.053-devel, Yosys 0.69). Apt's 5.020 and 0.33
failed four tests: Yosys 0.33 cannot read `assets/sync_ff.sv` and locates
loops on line 1, and Verilator 5.020 handles a reset pulse between edges
differently.

## Review of 2026-10-07 (Verilator + Yosys): verification in the loop

The skill targets the right tools, and its Yosys subset is lint-clean in
Verilator (all 149 probes). What separates it from a professional flow is
that "done" never simulates: `check --synth` is lint plus a Yosys read, and
functional correctness is measured only by the eval harness. Ordered by what
lets wrong RTL through today.

### M9 — The skill simulates before it is done

Done as M12 (17–20); 21 dropped, the step did not sprawl.

- [x] **17. `assets/tb_skeleton.sv`.** A self-checking testbench template
  that builds with `verilator --binary --timing`: clock and reset generation,
  a `step` task, an error counter with the first failure's message, one
  `PASS`/`FAIL` line and `$finish`. Take the shape from
  `evals/files/classics/*_tb.sv`, which is what `grade.py` already runs.
- [x] **18. `references/testbench-verilator.md`.** What a testbench for this
  flow is: Verilator 5 with `--binary --timing -Wno-fatal`, the SV a testbench
  may use that RTL may not (queues, unpacked structs, `automatic`, `string`,
  bare SVA), checks against a reference model or golden vectors, a fixed
  seed, the build and run command, and how to read a failing `ASSERT` from
  `assert_macros.svh`.
- [x] **19. SKILL.md: a "Simulate" step and a "Done means" item.** After
  `fix` and `check`, write the testbench from the template, run it, and
  report what it checked. Done means the testbench printed `PASS` and no
  `ASSERT` fired. The testbench is not RTL: keep it out of `svstyle check`
  (`exclude = ["tb/*"]` in `.svstyle.toml`).
- [x] **20. Eval the testbenches, not only the RTL.** For the classics that
  have a planted-bug set, run the skill's own testbench against the planted
  bugs: the score is how many it catches. Record it in `grade.py` as a
  per-eval check, next to the equivalence testbench.
- [x] **21. `svstyle sim`, only if 19 sprawls.** One command that builds and
  runs a testbench with the flags from 18 and reports the exit code, the
  assertion failures and the `PASS` line. Not before 17–19 are in use.

### M10 — Yosys frontends and versions

Done as M15.

- [x] **22. Rerun the probes on CI's tools.** `evals/yosys-probes/run.sh`
  with Yosys 0.69 and Verilator 5.053 (the OSS CAD Suite build CI uses);
  update the stamps in the probes README and `synth-yosys.md`. Add the run to
  CI, so a Yosys bump that changes a row fails the build instead of the next
  eval.
- [x] **23. yosys-slang probe.** The same 149 probes through
  `plugin -i slang; read_slang`. Record which "does not parse" and
  "synthesises wrong" rows disappear. Decision gate: adopt only if the
  project's Yosys ships the plugin (OSS CAD Suite does, Homebrew's does not).
- [x] **24. `synth = "yosys-slang"`** (after 23): `check --synth` reads with
  `read_slang`, and the skill loads a shorter `synth-yosys-slang.md` in place
  of `synth-yosys.md`.

### Recorded, no action

- The skill description summarises the workflow as well as naming triggers;
  trigger evals score 100 %, so it stays.
- `SKILL.md` plus `rules.md` load about 4,200 words per SystemVerilog
  request; acceptable for a domain skill.
- `ASSERT` covers a reset pulse between edges for one-cycle properties only;
  `##2` and longer stay exposed (documented in the macro).
- Verible stays pinned at `v0.0-3946` (see Spec follow-ups).
- Icarus Verilog is not a target. A probe run on 2026-10-07 (iverilog 13.0,
  the 149 Yosys probes) found the SVA macros with `|->`, `unique if`,
  function `output` arguments, block-local `automatic` and struct-typed
  localparams unsupported there; none of it matters for Verilator.

## Ecosystem review of 2026-10-10: release, review workflow, debt

From `docs/superpowers/plans/2026-10-10-ecosystem-review.md`. Done in this
round: M14, M11, M12, M15, M16 (no action) and the engineering debt; M13
except the full VerilogEval.

### Engineering debt

- [x] An unexpected exception in a worker exits 4 with
  `internal error, please report` instead of a traceback (check and fix).
- [x] A filelist that includes itself, directly or in a cycle, is an error.
- [x] Yosys reaches an include dir whose path has a space through a symlink
  (it takes no quoted `-I`); the dir used to be dropped.
- [x] `.svstyle.toml` is read once per directory per run; Verible, Verilator
  and Yosys run at once. Explicit UTF-8 on the last two reads without it.
- [x] Tests for lowercase `-f`, the `select` config key and a hung tool.

### M14 — Skill content

- [x] **Fixed interface.** `SKILL.md` keeps module and port names and the
  reset style a spec, benchmark or integration target fixes; house style
  inside; NAM-002/RST-001 waived with a reason. A trailing waiver doubles as
  the port comment, so such a file checks clean.
- [x] **Reviewing RTL.** `SKILL.md` reports without editing: `check --synth`,
  then the review rules by what the code contains, then the design at its
  edges, then what was not checked; no invented findings.
- [x] **STR-002 and NAM-010 mechanised** (review rules 31 → 29). STR-002: a
  `.sv` that defines no design unit is a header. NAM-010: a declared name
  that is a SystemVerilog keyword (reachable under `` `begin_keywords``;
  without it the parse error now cites NAM-010). Neither fires on the 196
  template, fixture and eval files.
- [x] **Evals 10–12, written, not yet run** (they need M13's runner or the
  skill-creator workflow). 10: a fixed `TopModule`/`clk`/`reset`/`in`/`out`
  edge detector, graded by its testbench (catches 3/3 planted bugs) and a
  port regex. 11: review of `pkt_stats.sv`'s three planted bugs. 12: review
  of a correct one-clock block, the false-positive control. `grade.py`
  grades a review from `review.md` and checks the inputs were not edited.

### M11 — Release readiness

- [x] MIT `LICENSE`, `CHANGELOG.md`, package metadata, version from
  `svstyle/__init__.py`, `pyslang>=11,<12`. `uv build` wheel runs under
  `uvx` outside the checkout. `svstyle` is free on PyPI.
- [x] `release.yml`: a `v*` tag builds and publishes with PyPI trusted
  publishing (configure the publisher on PyPI first), after checking the
  tag against the version.
- [x] Claude Code plugin: `.claude-plugin/plugin.json` (skills from
  `./skill/`) and `marketplace.json`; `claude plugin validate` passes. A
  PostToolUse hook runs `svstyle check --no-external` on an edited `.sv` and
  hands a failing result to the model; silent when svstyle is missing.
- [x] `tooling.md` installs from PyPI; the "two directories above the skill"
  rule is gone. README: install lines, why-not-Verible table, eval numbers,
  CI badge, absolute links, licence. `.pre-commit-hooks.yaml`. A Pages job
  publishes `docs/style-guide.html`.
- [ ] By hand: make the repo public, enable Pages, add the PyPI trusted
  publisher, push the `v0.1.0` tag.

### M13 (partial) — VerilogEval v2, first run

`evals/verilogeval.py` (2026-10-10): 30 of the 155 working spec-to-RTL
problems (every 5th; Prob099 is broken upstream), Opus 5.5, one run each, in
an empty directory with `--setting-sources project`; the with-skill run adds
the repo with `--plugin-dir`. $12 in total.

| config | pass@1 (iverilog) | svstyle clean | Verilator -Wall clean | $/problem | s/problem |
|---|---|---|---|---|---|
| without skill | 23/30 | 0/30 | 28/30 | 0.10 | 11 |
| with skill | 25/30 | 30/30 | 29/30 | 0.30 | 36 |

- iverilog 13 needs the testbenches' `$dumpvars` lines dropped, and rejects
  `state_d = in ? StB : StA;` (legal SV) in both configs on Prob119; under
  Verilator both pass, so 24 vs 26. It cannot read the SVA macros either.
- The skill wins Prob078 and Prob139 and loses Prob149 (one mismatch in
  2040 under Verilator, a spec ambiguity on `dfr` it flagged and guessed
  wrong). Prob053, Prob093 and Prob104 fail in both configs.
- Reading: the benchmark grades guessing an ambiguous spec, which the skill
  does not target; the functional delta (+2) is within noise at n=30. The
  style delta is the skill's point: 30/30 vs 0/30, with the given
  interface kept through the waivers in `SKILL.md`.
- First run lost: outputs inside the repo are inside the plugin directory,
  where Claude Code refuses writes. The runner now refuses `--out` there.

### M12 — Verification in the loop

Supersedes M9 items 17–20; 21 (`svstyle sim`) is not needed, the step did
not sprawl.

- [x] `assets/skeleton_tb.sv`: a model beside the DUT, a `step` task that
  checks then drives at the negedge, the first mismatch, `+seed=N`, one
  `PASS`/`FAIL` line, non-zero exit on FAIL. Tested: passes on `skeleton.sv`,
  fails on a wrong output and on a missing reset.
- [x] `references/testbench-verilator.md`: `tb/<name>_tb.sv`, what a
  testbench may use, a model written from the spec, the build command
  (`--assert`, random initial values for unreset flops), no `-D`/`-G`, how to
  read PASS, FAIL and a fired `ASSERT`.
- [x] `SKILL.md`: a "Simulate" step after the loop, bounded to one fix and
  one rerun, and "Done means" grows "the testbench printed PASS". The
  PostToolUse hook skips `tb/` and `*_tb.sv`.
- [x] Planted bugs checked in: `evals/files/classics/bugs/`, three per
  classic for `seq-detect`, `updown-counter`, `fir`, `fxp-add-sat` and
  `rr-arbiter`, each caught by the grader's own testbench. `grade.py`'s
  `tb_catches` runs the output's testbench on the reference (must pass) and
  on each bug (must fail); a hang counts as caught. The grader now also finds
  RTL in a subdirectory (`rtl/`).

Rerun of the five, with the skill, Opus 5.5, `claude -p` (2026-10-11):

| run | equivalence | own testbench vs planted bugs | $/block | s/block |
|---|---|---|---|---|
| 1 (could not run the binary) | 5/5 | 8/15: two testbenches never built or passed, one missed a bug | 0.67 | ~115 |
| 2 (binary allowed) | 5/5 | 15/15 | 0.65 | 116 |

- Run 1 found a runner bug, not a skill one: the `dontAsk` allowlist let
  the model build the testbench but not run it, and the two that broke
  (a mid-run reset race, a `-D` the grader cannot know) were exactly what a
  run would have caught. `verilogeval.py` now allows `build/*` and
  `obj_dir/*`; the reference forbids testbench-only defines.
- Cost per block is up from about $0.30–0.53 in earlier rounds: the
  testbench is most of the new work.

### M13 — Reproducible evals (runner)

- [x] `evals/run.py`: `claude -p` per eval, config and run in an empty
  directory outside the repo, inputs copied to the path the prompt names,
  graded by `grade.py`, one Markdown table. `evals/README.md` records the
  layout and the tool versions.
- [x] `grade.py`: a 600 s default timeout on every tool call, Yosys file
  names quoted, the `unchanged` check also looks at the input's repo path.
  `cost.py` derives the transcript directory from the checkout.
- [x] VerilogEval, the full 155 (2026-10-11, Opus 5.5, one run each,
  $70 in total; below).

Full VerilogEval v2, 155 problems:

| config | pass@1 (iverilog) | pass@1 (adjudicated) | svstyle clean | Verilator -Wall clean | $/problem | s/problem |
|---|---|---|---|---|---|---|
| without skill | 134/155 | 149/155 | 0/155 | 143/155 | 0.10 | 21 |
| with skill | 131/155 | 147/155 | 155/155 | 147/155 | 0.35 | 71 |

- iverilog 13 is the wrong judge for SystemVerilog: 32 of the 45 failures
  do not build. They are an enum in a ternary (`state_d = in ? A : B`,
  "requires an explicit cast"), an array indexed in a function, and the
  skill's `assert_macros.svh`, which the grader did not pass with `-I` (now
  fixed). Verilator cannot replace it: it is 2-state, and several
  references output `'x` as a don't-care that the testbench matches with
  `===`.
- Adjudicated: a run that does not build under iverilog is graded by
  simulating its Yosys netlist (`proc; write_verilog`) in iverilog.
  Netlists that build pass, except Prob139 with the skill. Both configs
  fail the same six (034, 053, 062, 078, 093, 104). Only the skill fails
  066 and 139. Yosys `equiv` proves 066 equivalent to the reference (the
  iverilog failure is a simulation artefact). 139 passes under Verilator;
  `equiv` cannot decide it because the state encodings differ. So the
  functional numbers are equal.
- Cost: 3.5× per problem. From the transcripts, the extra spend splits
  into roughly 40 % testbench, 40 % reading the skill (`SKILL.md` and
  references, re-read as context on every later turn) and 20 % the
  check/fix loop; 9.3 turns per run against 2.4.
- Reading: as in the 30-problem run, the skill adds no pass@1 on this
  benchmark. It makes every output pass `svstyle`, at 3.5× the cost. The
  testbench, the largest single cost, finds nothing here, because the
  problems are small and come with their own testbench.

First run of evals 10–12 (written in M14), Opus 5.5, one run each,
2026-10-11, $1.83 in total:

| eval | with skill | without skill |
|---|---|---|
| 10 fixed interface | 11/11 | 6/11 (behaviour and ports right; style 0/5) |
| 11 review, three planted bugs | 5/5 | 5/5 |
| 12 review, correct block | 3/3 | 3/3 |

Evals 11 and 12 do not separate the configs: the baseline finds the three
bugs and invents no CDC finding either. They stay as regression checks for
the review workflow; a discriminating review eval needs subtler bugs.

### M15 — Tools: probes in CI, yosys-slang, pins

Supersedes M10 (items 22–24).

- [x] **Probes on CI's tools.** Yosys 0.69+212 and Verilator 5.053 (OSS CAD
  Suite 2026-10-07): all 149 behave as on 0.66. `run.sh` exits non-zero on a
  FAIL and runs in CI on both frontends.
- [x] **yosys-slang probe** (`FRONTEND=slang`, a `// slang:` line where the
  result differs): 46 ERROR and 6 WRONG rows become OK (56 of the 59 new OKs
  proved with `sat`). Lost: constant `repeat` and a non-constant module-level
  initializer (the second was silently wrong before). Still out: `do`/`while`,
  non-constant `repeat`, enum and array methods; `unique`/`priority case`
  with no `default` still drops the default.
- [x] **Adopted, opt-in.** `synth = "yosys-slang"`: `check` reads with
  `read_slang` through a command file (it takes no quoted path), and the
  skill loads `synth-yosys-slang.md` (4 rows) in place of `synth-yosys.md`
  (49). The default stays the built-in frontend: Homebrew's Yosys has no
  plugin. slang has no black boxes, so a module not passed is a read error.
- [x] **Pins.** `pyslang>=11,<12` (from M11). The Verible version stays in
  `external.KNOWN_GOOD_VERIBLE_VERSION`, kept equal to CI's by a test; a
  non-blocking `verible-latest` job runs the `fix` goldens on the newest
  release (v0.0-4296 today), so green there means the pin can move.

### M16 — Formal spike: recorded, no action

Question: can the `ASSERT` macros also run in `sby`, and is it worth it?
Measured 2026-10-11 on the latest with-skill run of the 43 eval designs
(151 assertions), Yosys 0.69+212 and sby from OSS CAD Suite 2026-10-07.

- **Expressible: all of them that mean something.** 89 are X checks
  (`ASSERT_KNOWN`, or `!$isunknown` under `|->`), void in a 2-state model.
  The other 62: 14 boolean, 39 `|->`, 9 `|=>`, no `##N` or sequences.
- **But not through `prop`.** Neither frontend reads `assert property`
  with an implication (`read_verilog -formal` no concurrent form at all,
  `read_slang` booleans only), and a macro cannot rewrite `a |-> b`: it
  takes two new macros with the antecedent and consequent apart (`!a || b`
  same cycle; a one-cycle register for `|=>`), plus an `initial assume` of
  reset and the same reset-since-last-edge guard as simulation.
- **Input checks have to be `ASSUME`.** Three designs assert their input
  protocol (`full_o |-> !wr_en_i`); formal breaks those at step 2.
- **It runs.** With that conversion, 23/23 designs with a non-X assertion
  pass BMC at depth 20, 21 prove unbounded (two need strengthening), 6 s
  in total.
- **It finds nothing the testbench misses.** The rr-arbiter assertions
  (one-hot, grant only to a requester, a grant iff a request) hold on all
  three planted bugs, which are fairness and order bugs; its testbench
  catches 3/3. The skill writes safety invariants, which buggy designs
  also satisfy.

Reopen when assertions encode the spec (ordering, fairness, latency), so a
proof checks something a testbench might not reach. Then the cost is the
two macros, `ASSUME`, an `assets/formal.sby` and a "Done means" line for
projects with `sby`.

### Follow-ups of 2026-10-11

Opus 5.5, `claude -p`, one run each, tools from OSS CAD Suite 2026-10-07;
$11 in total.

**Eval 13, a review the tools cannot help with.** `level_monitor.sv` passes
`svstyle check --synth` and Verilator `-Wall` clean, and carries four bugs
backed by review rules: an unsigned two's-complement compare (LNG-018), a
one-cycle pulse crossing 200 to 25 MHz through two flops (CDC-005), a
combinational signal into a synchroniser (CDC-004) and a pad reset used raw
in both domains (RST-002). Both configs find all four (6/6), the baseline
for $0.26, the skill for $0.48; the baseline also flags three real issues
not planted (bypass does not gate counting, the 12-bit bias add wraps,
`bias_i` has no clock domain). Evals 11 and 12 rerun: 5/5 and 3/3 in both
configs again. Reading: at this model, review is not where the skill adds
value; the three evals stay as regression checks, and no further review
eval is planned.

**`synth = "yosys-slang"` measured.** `run.py --synth NAME` writes the key
to each run's `.svstyle.toml`; the grader's own Yosys check now reads with
the configured frontend. Five classics chosen for the Yosys subset
(fir, cordic, alu-pkg, sort8, systolic-mm), with the skill:

| synth | checks passed | $ total | s total | slang-only constructs in the RTL |
|---|---|---|---|---|
| yosys | 47/51 | 4.81 | 1031 | 0 |
| yosys-slang | 51/51 | 4.29 | 886 | `return` ×7, `inside` ×4, `'{...}` ×4, unpacked arrays, `import` |

- The skill follows the config: under slang it writes the SystemVerilog
  the built-in subset forbids, and all of it checks and synthesises.
- The 4 lost checks are one cordic run that left a scratch `consts.sv`
  (a `real` constant generator) in its output; its `cordic.sv` is clean.
- 11 % cheaper and 14 % faster at n=5, one run each: within noise. The
  case for slang is what it lets the code say, not cost.

**Latest Verible.** The `verible-latest` CI job runs on the next push.

### Synthesis quality and cost (2026-10-11)

**Synthesis is already clean.** `synth -flatten -auto-top` (Yosys 0.69) on
the latest output of each of the 35 classics: with the skill, 0 warnings and
0 latches in all 35, and every RAM the prompt asks for inferred as `$mem`
(fwft-fifo, pkt-drop-fifo, both FIFOs, inferred-ram). Without the skill
(24 outputs): fir and cordic warn "Replacing memory ... with list of
registers", the unpacked-flop-array pattern `synth-yosys.md` forbids. Cell
counts are within a few percent of the baseline. `grade.py` now checks it:
"Yosys synthesis has no warning and no latch".

**Cost: the testbench, and the environment around it.** Transcripts of six
classics (fir, uart-rx, async-fifo, axil-regs, sort8, fp32-add) with the
skill: the RTL was right at the first `check` in every run, and a third of
the cost went to building the testbench, mostly not for its own bugs:

- `-Mdir build/tb` fails with `Can't write file` when `build/` does not
  exist (Verilator does not create parents), in 4 of 6 runs; the model
  then tried `/tmp`, `obj/`, `obj_tb/`, which the allowlist denied. Fixed:
  `mkdir -p build/tb` in `testbench-verilator.md`, and the template test
  now runs that document's command block verbatim.
- 33 denied tool calls: shell variables and `;` chains to read the skill's
  files, and `cp` out of the plugin directory (protected, so a prompt for a
  real user too). `SKILL.md` now says to copy templates by read and write.
  The eval allowlist gained `head`, `tail`, `grep`, `sed`, `rm -rf build*`.

| run | checks | $ total | s total | tb builds | denied |
|---|---|---|---|---|---|
| before | 67/67 | 6.71 | 1508 | 37 | 33 |
| after the mkdir fix | 67/67 | 5.56 | 1244 | 14 | 11 |

| after the `cp` fix | 67/67 | 6.08 | 1376 | 13 | 6 |

The `cp` fix took template-copy denials from 6 to 0. Cost moved within
one-run noise (axil-regs alone $0.85 to $1.39 with the same builds); the
reliable gains are the builds (37 to 13) and the denials (33 to 6). Four
of the six left were `; echo exit=$?` appended to a command; `SKILL.md`
now says the tool reports the exit code.

### Progressive disclosure (2026-10-11)

`SKILL.md` keeps what writing new single-clock RTL needs. Review and legacy
code moved to `references/existing-code.md`, multi-clock guidance to
`references/multi-clock.md`, and the CDC rules to a generated
`references/rules-cdc.md`. The `rules --check` drift test now also checks
rule IDs in the hand-written references. Upfront load: 4,752 → 4,178 words.

Old vs new skill, one run each: 7 classics $6.37 → $6.35 (80/80 → 79/80;
the miss is seq-detect's testbench catching 2/3 planted bugs, a part this
change does not touch); evals 3, 7, 13 $1.89 → $2.25 (27/27 both);
VerilogEval subset of 30 $10.54 → $11.11. The on-demand files are read
exactly where they apply (async-fifo, uart-rx, evals 3, 7, 13) and nowhere
else. No measurable cost change: a 12 % cut of the upfront words is ~3 %
of the cost, below one-run noise. Kept for structure, not cost.

### Simulate only what is worth it (2026-10-11)

Evidence from the full VerilogEval run: the skill's own testbench printed
FAIL in 52 of 155 runs; in 37 only the testbench was then edited (its model
or timing was wrong), and of the 6 RTL edits that could be replayed, 5 were
on RTL that already passed the dataset testbench and one did not fix it. No
real bug found. So `SKILL.md` now skips the testbench for a small block: one
clock, no memory, no handshake or bus protocol, no arithmetic beyond
increment, compare and select, under about 40 lines of logic; it says so,
and simulates when the user asks. `grade.py`'s `tb_catches` passes with
"simulation skipped" when there is no testbench.

| set | before $ | after $ | quality |
|---|---|---|---|
| VerilogEval subset of 30 | 11.11 | 7.79 (−30 %), 57 → 27 s/problem | pass@1 21 → 23; 0/30 wrote a testbench |
| seq-detect, updown-counter, rr-arbiter | 1.21 (two of three) | 1.11 for three | all skipped, 12/12 each |
| fir, fxp-add-sat, uart-rx, axil-regs | 2.92 (three of four) | 3.13 for four | all simulated, planted bugs 3/3 where present |

The cost: rr-arbiter's planted bugs (fairness, order) were caught 3/3 by
its testbench before and are now unchecked; its RTL is still graded by the
equivalence testbench. Before numbers are the progressive-disclosure run,
one run each.


### `fix` speed and a closing directive (2026-10-11)

Profile of `fix` on the 72 classic files: `parse` about 60 % (five parses
per file), the difflib alignment 17 %, Verible 11 %. A pass now reuses the
previous pass's tree when Verible leaves the text alone, the last pass (no
fixes) neither reformats nor reparses, the final `check` reuses the last
tree, and the invariant skips difflib when the tokens are equal. Wall time
9.0 s to 5.9 s on 8 cores; `fix --diff --json` output is byte-identical on
173 eval, probe and fixture files.

Found trying the gradual-adoption config: `fix` ignored `select`/`ignore`
(fixed), LNG-001 flagged a closing `` `default_nettype wire``, and the
`` `resetall`` that `fix` appended was joined onto it by Verible. The
directive is now replaced by `` `resetall``, which also restores it.

# Roadmap

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

- [ ] **17. `assets/tb_skeleton.sv`.** A self-checking testbench template
  that builds with `verilator --binary --timing`: clock and reset generation,
  a `step` task, an error counter with the first failure's message, one
  `PASS`/`FAIL` line and `$finish`. Take the shape from
  `evals/files/classics/*_tb.sv`, which is what `grade.py` already runs.
- [ ] **18. `references/testbench-verilator.md`.** What a testbench for this
  flow is: Verilator 5 with `--binary --timing -Wno-fatal`, the SV a testbench
  may use that RTL may not (queues, unpacked structs, `automatic`, `string`,
  bare SVA), checks against a reference model or golden vectors, a fixed
  seed, the build and run command, and how to read a failing `ASSERT` from
  `assert_macros.svh`.
- [ ] **19. SKILL.md: a "Simulate" step and a "Done means" item.** After
  `fix` and `check`, write the testbench from the template, run it, and
  report what it checked. Done means the testbench printed `PASS` and no
  `ASSERT` fired. The testbench is not RTL: keep it out of `svstyle check`
  (`exclude = ["tb/*"]` in `.svstyle.toml`).
- [ ] **20. Eval the testbenches, not only the RTL.** For the classics that
  have a planted-bug set, run the skill's own testbench against the planted
  bugs: the score is how many it catches. Record it in `grade.py` as a
  per-eval check, next to the equivalence testbench.
- [ ] **21. `svstyle sim`, only if 19 sprawls.** One command that builds and
  runs a testbench with the flags from 18 and reports the exit code, the
  assertion failures and the `PASS` line. Not before 17–19 are in use.

### M10 — Yosys frontends and versions

- [ ] **22. Rerun the probes on CI's tools.** `evals/yosys-probes/run.sh`
  with Yosys 0.69 and Verilator 5.053 (the OSS CAD Suite build CI uses);
  update the stamps in the probes README and `synth-yosys.md`. Add the run to
  CI, so a Yosys bump that changes a row fails the build instead of the next
  eval.
- [ ] **23. yosys-slang probe.** The same 149 probes through
  `plugin -i slang; read_slang`. Record which "does not parse" and
  "synthesises wrong" rows disappear. Decision gate: adopt only if the
  project's Yosys ships the plugin (OSS CAD Suite does, Homebrew's does not).
- [ ] **24. `synth = "yosys-slang"`** (after 23): `check --synth` reads with
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
round: M14, M11 and the engineering debt. Open: M12 (verification in the
loop, which supersedes M9), M13 (reproducible evals and a VerilogEval v2
number), M15 (probes in CI and yosys-slang, which supersedes M10) and M16
(formal spike).

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

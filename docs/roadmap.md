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

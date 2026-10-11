# Existing RTL: review it, or bring it into the style

## Review

When the user asks for a review, report; do not edit unless asked.

1. Run `svstyle check --synth` on every file of the design in one call (or
   without `--synth`, as in "The loop" in SKILL.md). Its findings are the
   mechanical part.
2. Walk the review rules (`svstyle rules --unmapped`, about thirty) by what
   the code contains: CDC-* (in `rules-cdc.md`) and RST-002/003 only with
   more than one clock, FSM-* and DOC-008 only with an enum state, PRT-007
   only with ready/valid, LNG-018 only with signed arithmetic. Then the
   design itself: does it do what its description and the spec say, at the
   edges (reset, full, empty, overflow, back-to-back)?
3. Report in this order: findings, each with rule ID (or "design"),
   `file:line`, severity and one line of why (`rules-rationale.md`, by
   heading, when the reason is not obvious); then what you did not check
   (no testbench run, files you were not given, a second clock you inferred).

A correct file gets a short report that says so. Do not invent findings to
fill one, and do not report style the interface forces (see "When the
interface is given" in SKILL.md).

## Legacy code

To bring legacy RTL into the style, run `svstyle fix`
on it first: besides formatting, it turns `reg`/`wire` into `logic`,
`always @(*)` into `always_comb`, clocked `always` into `always_ff`, and
wraps lone statements in `begin`/`end`, wherever that provably keeps the
meaning. A `.v` file keeps its Verilog: rename it to `.sv` first if it is to
become SystemVerilog. Then work through what `check` still reports;
`tooling.md` lists what `fix` leaves alone and why. To adopt the style on a
large codebase without fixing everything at once, `check --baseline` (in
`tooling.md`) fails only on new findings.

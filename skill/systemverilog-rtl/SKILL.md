---
name: systemverilog-rtl
description: Write, review and fix synthesizable SystemVerilog RTL in a lowRISC-derived house style that the `svstyle` tool checks and fixes. Use this skill whenever the user wants SystemVerilog hardware - `.sv`/`.svh` files, modules, packages, FSMs, FIFOs, arbiters, counters, pipelines, reset logic, clock-domain crossings, synchronisers - or asks to review, lint, format, comment or clean up SV code, even if they never say "style" or "SystemVerilog" (e.g. "design a round-robin arbiter", "add a 2-flop synchroniser", "why does svstyle flag DOC-004"). Also use it for questions about the house rules (IDs like RST-001, PRT-003) or about `svstyle` output.
---

# SystemVerilog RTL

A house style, a checker/fixer (`svstyle`) that enforces the
mechanical ones, and templates that already pass it. The rules exist so that
RTL reads the same no matter who wrote it -- a person or a model -- and so a
reviewer spends time on the design, not on whitespace and naming.

## Before writing any code

Read `references/rules.md` (one line per rule). It is short on
purpose: every rule you break there is a finding you will have to fix later.

Then check the synthesis tool: the `synth` key in the nearest
`.svstyle.toml` (no file or no key means `yosys`). If it is `yosys`, also
read `references/synth-yosys.md`, the SystemVerilog subset Yosys reads;
code outside it is a parse error and an extra round. If it is
`yosys-slang`, read the much shorter `references/synth-yosys-slang.md`
instead. Any other value: skip both.

Start from the closest template in `assets/` rather than a blank file. Each
already passes `svstyle check`, so you inherit a correct header, port order,
reset style and comment layout. `assets/` sits next to this SKILL.md; reach
it by absolute path, not one relative to the project. To copy a template,
read it with the file-read tool and write it into the project: a shell `cp`
out of the skill's directory, a shell variable or a `;` chain each needs a
permission prompt. Run each shell command on its own; the tool already
reports the exit code, so no `; echo $?`.

| Template | Use it for |
|---|---|
| `assets/skeleton.sv` | any module: registered stage, parameter check, reset vs. datapath flops |
| `assets/fsm.sv` + `assets/fsm_pkg.sv` | a state machine: `typedef enum` state, `state_q`/`state_d`, commented case arms, registered outputs |
| `assets/sync_ff.sv` | a synchroniser rank (`NumFlops` 2 or 3) for a one-bit level, or a reset synchroniser with `d_i` tied to 1; copy it next to the RTL and instance it, do not rewrite it |
| `assets/assert_macros.svh` | `` `ASSERT``, `` `ASSERT_KNOWN``, `` `ASSERT_INIT`` (VER-001); both templates include it |
| `assets/skeleton_tb.sv` | the self-checking testbench for "Simulate" below: a model beside the DUT, a `step` task, one PASS/FAIL line |

Rename the module and the file together (STR-001: the basename is the
module name). The FSM template keeps its enum in a package because other
modules usually need the type; an enum used by one module only can be a
`typedef` inside it. Packages are `<name>_pkg` in `<name>_pkg.sv`.

## When the interface is given

A spec, a benchmark, a testbench, vendor IP or the code it plugs into may
fix the module name, the port names, the reset polarity or the reset style
(`clk`, `reset`, `in`, `out`, a synchronous active-high reset). Then keep
them exactly as given, and never rename a port unless the user asks: the
house style is for what you choose, not for a contract you were handed.

Everything inside still follows the style: comments, internal names, `_q`
flops (register `out_q` and `assign out = out_q;`). Waive what the interface
forces, with the reason (DOC-009). A trailing waiver also serves as the
port comment:

```systemverilog
    input  logic       clk,    // svstyle: waive NAM-002 fixed interface; system clock
    input  logic       reset,  // svstyle: waive NAM-002 fixed interface; sync reset, active-high
...
    // svstyle: waive RST-001 fixed interface: synchronous active-high reset
    always_ff @(posedge clk) begin
```

Say in the header's `Description:` that the interface is fixed and by what.

## Write it the way the checker expects

The fixer can insert a missing comment, but it can only write
`// TODO: describe`. That keeps the file passing and tells a human something
is missing -- it is not a comment. So write every comment yourself, as you go:

- **Header** (DOC-001/002): the copyright block from the template, with a
  `Description:` that says what the module does and its non-obvious
  constraints (latency, power-of-two depth, one-hot inputs). Keep
  `<Company>` as written: `svstyle fix` fills it from the nearest
  `.svstyle.toml`. If there is none and the user tells you the company,
  create one at the repository root containing `company = "Their Company"`;
  otherwise the placeholder stays and is reported as a SHOULD.
- **Trailing comment on every port, parameter and declaration** (DOC-003/004):
  what the signal means, when it is valid, what it is relative to. Not its
  type or direction -- the declaration already says that. One comment per
  declaration, at its end; `svstyle fix` moves a lone comment written on the
  line above to the end when it fits. Only a declaration that spans several
  lines, or whose comment would not fit within 100 columns, keeps it above.
- **No temporary with bits you never read** (LNG-017). Round or truncate in
  one expression, cast to the result width: `y = W'((x + Half) >>> Frac);`
  rather than `x_round = x + Half; y = x_round[...];`, whose dropped bits are
  unused. The same for a carry or guard bit you only test: keep it in the
  expression, not in a named wider signal. Nor a register nobody reads (the
  angle of a last pipeline stage), or an `int` loop index used to slice a
  narrow vector: give the index its own sized variable. Port bits the spec
  says to ignore (`addr_i[1:0]`) get their waiver when you write the port:
  `// svstyle: waive LNG-017 <why>` on its own line above the port.
- **No keyword as a name** (NAM-010). SystemVerilog reserves more words than Verilog:
  `small`, `medium`, `large`, `strong`, `weak`, `do`, `final`, `ref`, `bit`,
  `byte`, `int`, `type`, `alias`... A signal called `small` does not parse at all
  (exit 3). Prefer descriptive names anyway: `small_mant`, not `small`.
- **Widths match on every assignment** (LNG-015), constants included: a
  narrow slice stored in an `int` or a `localparam int` needs a cast,
  `localparam int P = 32'(T[i*3 +: 3]);`, or a variable of the slice's width.
- **No assertion the type already guarantees**: `count_q <= CountMax - 1` on
  a `$clog2(CountMax)`-bit counter is constant when `CountMax` is a power of
  two, and Verilator reports it (`EXT-VLTR-CMPCONST`). Nor one that forbids
  an input the spec allows (a zero seed, a back-to-back start): it fires on
  legal use. Write down a hazard the spec permits in the description instead.
- **A comment line above every `always_*` block and every instance**
  (DOC-005/006): what the block computes, or why the design needs the instance.
- **A comment above each FSM case arm** (DOC-008), not on the enum.

Then run the tools.

## Existing code

To bring legacy RTL into the style, run `svstyle fix` on it first: besides
formatting, it turns `reg`/`wire` into `logic`, `always @(*)` into
`always_comb`, clocked `always` into `always_ff`, and wraps lone statements
in `begin`/`end`, wherever that provably keeps the meaning. A `.v` file
keeps its Verilog: rename it to `.sv` first if it is to become SystemVerilog.
Then work through what `check` still reports; `references/tooling.md` lists
what `fix` leaves alone and why. To adopt the style on a large codebase
without fixing everything at once, `check --baseline` (in `tooling.md`)
fails only on new findings.

## Reviewing RTL

When the user asks for a review, report; do not edit unless asked.

1. Run `svstyle check --synth` on every file of the design in one call (or
   without `--synth`, as in "The loop" below). Its findings are the
   mechanical part.
2. Walk the review rules (`svstyle rules --unmapped`, about thirty) by what
   the code contains: CDC-* and RST-002/003 only with more than one clock,
   FSM-* and DOC-008 only with an enum state, PRT-007 only with ready/valid,
   LNG-018 only with signed arithmetic. Then the design itself: does it do
   what its description and the spec say, at the edges (reset, full, empty,
   overflow, back-to-back)?
3. Report in this order: findings, each with rule ID (or "design"),
   `file:line`, severity and one line of why (`references/rules-rationale.md`,
   by heading, when the reason is not obvious); then what you did not check
   (no testbench run, files you were not given, a second clock you inferred).

A correct file gets a short report that says so. Do not invent findings to
fill one, and do not report style the interface forces (see "When the
interface is given").

## The loop

```sh
svstyle fix   rtl/*.sv     # Verible formatting + anything insertable
svstyle check --synth rtl/*.sv  # svstyle + Verible lint + Verilator + Yosys, one report
```

With `synth = "yosys"` or `"yosys-slang"` in `.svstyle.toml`, plain
`svstyle check` runs Yosys too; with another tool there, drop `--synth`.

Pass every file of the design in one call: Verilator needs the submodules
to elaborate, and checking a lone file that instantiates others reports
`EXT-VLTR-MODMISSING`. If the code `` `include``s files from another
directory, add `-I DIR`; without it the file does not parse (exit 3).

Read each finding as `file:line:col: RULE-ID message`. `[fix available]`
means `svstyle fix` handles it; everything else is yours. When a rule's
reason is unclear, or the user questions it, look it up in
`references/rules-rationale.md` by searching for its heading (`### PRT-003`)
rather than loading the whole file. Findings named `EXT-VL-*` / `EXT-VLTR-*`
are tool warnings no house rule claims yet; fix them as the tool says.
`EXT-VLTR-ERROR` means the design did not elaborate (an undeclared name, a
bad connection): fix it first, because the rest of the report is incomplete.

If `svstyle` is not on PATH, or for exit codes, `--json`, `--select` and
waivers, read `references/tooling.md`.

## Simulate

A clean `check` says the RTL is well formed, not that it does what the spec
says. Once it is clean, read `references/testbench-verilator.md`, write
`tb/<name>_tb.sv` from `assets/skeleton_tb.sv` with a model written from the
spec (not from your RTL), and build and run it once with the command there.
Skip this only when the user says so, Verilator is missing, or the user
supplies a testbench (then run theirs); say which.

Keep it bounded: on a FAIL, decide from the spec whether the RTL or the
model is wrong, fix that, rerun once. Still failing: stop and report it.

## What no tool checks for you

About half the rules need judgement. Before calling the RTL done, walk this
list against the code you wrote:

- **Reset** (RST-002..004): reset control (state, counters, valids), leave
  datapath unreset; a reset entering a clock domain goes through a reset
  synchroniser, one per domain: an instance of `assets/sync_ff.sv` with
  `.d_i(1'b1)`. It sits where the reset enters the domain: the top level, or
  a block that itself spans clocks (an async FIFO). A single-clock block takes
  `rst_ni` already synchronised to `clk_i` and adds none; one inside it would
  drop the inputs of the first cycles after reset. Where there is one, the
  synchronised reset releases a few cycles after the input, so an interface
  that accepts transfers must refuse them until then: reset `full`/`ready` flags to the blocking value (full = 1,
  ready = 0), not to the idle one.
- **Clock-domain crossings** (CDC-001..006): two flops for a single bit (an
  instance of `assets/sync_ff.sv`), registered in the source domain first;
  never a synchroniser per bit of a bus -- use a handshake, Gray code or an
  async FIFO; crossings live in a module whose only job is the crossing.
- **FSMs** (FSM-001..004): `typedef enum` state, one FSM per module, no
  combinational outputs across the module boundary.
- **Ports** (PRT-006, PRT-007): the rest of the port list grouped by
  interface; packed structs rather than interfaces as ports; ready/valid
  naming that says which protocol it is.
- **Case statements** (SYN-002, SYN-003): `unique case` + `default`;
  priority as `if`/`else if`. The `default` is not optional: without it
  synthesis may treat the case as `full_case` and drop the assignment
  before it, silently.
- **Parameters** (GEN-003): a parameter with restricted values gets an
  elaboration-time check, as the templates show.
- **Assertions** (VER-001/002): `` `ASSERT_KNOWN`` on every output, plus
  `` `ASSERT`` for the protocol rules the design relies on. If the project
  has no assertion macros of its own, copy `assets/assert_macros.svh` next
  to the RTL; it compiles to nothing under synthesis. Verible never wraps a
  macro argument, and rejoins one you split, so keep each `` `ASSERT`` within
  100 columns: name a long condition with a commented `logic`, or split the
  check into several assertions.
- **Naming** (NAM-003, NAM-009): an active-low flop is `<name>_nq`
  (`cs_nq`, driving `cs_no`); whole-word names; a signal outside the default
  clock domain carries its domain's prefix.
- **Structure** (STR-003, STR-004): declarations next to the logic that
  drives them; no package import cycles.
- **Departures** (DOC-009): if the design genuinely needs to break a rule,
  waive it where it happens with the reason in the same comment:
  `// svstyle: waive RST-001 DSP blocks need a synchronous reset` on the
  line above (or trailing the line). A waiver without a reason is ignored.

## Done means

- `svstyle check --synth` exits 0 on every file of the design (VER-003);
  SHOULD findings are allowed but each one is a deliberate choice. Drop
  `--synth` only if the project synthesises with another tool or Yosys is
  not installed, and say so.
- No `// TODO: describe` is left: `grep -rn "TODO: describe" rtl/` is empty.
- The testbench printed `PASS` and no `` `ASSERT`` fired (see "Simulate").
- The judgement list above has been walked, and anything that departs from
  it carries a DOC-009 comment.

Tell the user what you ran and what it reported, including any SHOULD
findings you left in place and why, and what the testbench checked (the
directed cases, how many random cycles, the seed) and what it did not.

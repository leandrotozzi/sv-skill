---
name: systemverilog-rtl
description: Write, review and fix synthesizable SystemVerilog RTL in a lowRISC-derived house style that the `svstyle` tool checks and fixes. Use this skill whenever the user wants SystemVerilog hardware - `.sv`/`.svh` files, modules, packages, FSMs, FIFOs, arbiters, counters, pipelines, reset logic, clock-domain crossings, synchronisers - or asks to review, lint, format, comment or clean up SV code, even if they never say "style" or "SystemVerilog" (e.g. "design a round-robin arbiter", "add a 2-flop synchroniser", "why does svstyle flag DOC-004"). Also use it for questions about the house rules (IDs like RST-001, PRT-003) or about `svstyle` output.
---

# SystemVerilog RTL

A house style with 76 rules, a checker/fixer (`svstyle`) that enforces the
mechanical ones, and templates that already pass it. The rules exist so that
RTL reads the same no matter who wrote it -- a person or a model -- and so a
reviewer spends time on the design, not on whitespace and naming.

## Before writing any code

Read `references/rules.md` (118 lines, one line per rule). It is short on
purpose: every rule you break there is a finding you will have to fix later.

Start from the closest template in `assets/` rather than a blank file. Each
already passes `svstyle check`, so you inherit a correct header, port order,
reset style and comment layout:

| Template | Use it for |
|---|---|
| `assets/skeleton.sv` | any module: registered stage, parameter check, reset vs. datapath flops |
| `assets/fsm.sv` + `assets/fsm_pkg.sv` | a state machine: `typedef enum` state, `state_q`/`state_d`, commented case arms, registered outputs |

Rename the module and the file together (STR-001: the basename is the
module name). The FSM template keeps its enum in a package because other
modules usually need the type; an enum used by one module only can be a
`typedef` inside it. Packages are `<name>_pkg` in `<name>_pkg.sv`.

## Write it the way the checker expects

The fixer can insert a missing comment, but it can only write
`// TODO: describe`. That keeps the file passing and tells a human something
is missing -- it is not a comment. So write every comment yourself, as you go:

- **Header** (DOC-001/002): the copyright block from the template, with a
  `Description:` that says what the module does and its non-obvious
  constraints (latency, power-of-two depth, one-hot inputs). Put the user's
  company in place of `<Company>` if you know it; otherwise leave the
  placeholder, which `svstyle` reports as a SHOULD until someone replaces it.
- **Trailing comment on every port, parameter and declaration** (DOC-003/004):
  what the signal means, when it is valid, what it is relative to. Not its
  type or direction -- the declaration already says that.
- **A comment line above every `always_*` block and every instance**
  (DOC-005/006): what the block computes, or why the design needs the instance.
- **A comment above each FSM case arm** (DOC-008), not on the enum.

Then run the tools.

## The loop

```sh
svstyle fix   rtl/*.sv     # Verible formatting + anything insertable
svstyle check rtl/*.sv     # svstyle + Verible lint + Verilator, one report
```

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

If `svstyle` is not on PATH, or for exit codes, `--json`, `--select` and
waivers, read `references/tooling.md`.

## What no tool checks for you

About half the rules need judgement. Before calling the RTL done, walk this
list against the code you wrote:

- **Reset** (RST-001..004): async active-low `rst_ni`, reset test first;
  reset control (state, counters, valids), leave datapath unreset; a reset
  entering a clock domain goes through a reset synchroniser.
- **Clock-domain crossings** (CDC-001..006): two flops for a single bit,
  registered in the source domain first; never a synchroniser per bit of a
  bus -- use a handshake, Gray code or an async FIFO; crossings live in a
  module whose only job is the crossing.
- **FSMs** (FSM-001..004): `typedef enum` state, one FSM per module, no
  combinational outputs across the module boundary.
- **Ports and instances** (PRT-002, PRT-004, PRT-006, PRT-007): clocks, then
  resets, then the rest grouped by interface; every port connected in every
  instance, unused outputs as explicit no-connects; ready/valid naming that
  says which protocol it is.
- **Case statements** (SYN-001..003, LNG-009): `unique case` + `default`;
  no `casex`, no `full_case`/`parallel_case`; priority as `if`/`else if`.
- **Parameters** (GEN-003): a parameter with restricted values gets an
  elaboration-time check, as the templates show.
- **Naming** (NAM-003, NAM-009, NAM-010): suffix order `_n` first and
  `_i`/`_o` last (`rst_ni`); whole-word names; no SV keywords.
- **Structure** (STR-003..005, LNG-001): declarations next to the logic that
  drives them, `logic` rather than `wire`, package imports in the module
  header. If the flow includes Yosys, reference package items as
  `pkg::Name` instead: open-source Yosys cannot parse an import in the header.
- **Departures** (DOC-009): if the design genuinely needs to break a rule,
  say why in a comment and add the tool's waiver pragma.

## Done means

- `svstyle check` exits 0 on every file of the design (VER-003); SHOULD
  findings are allowed but each one is a deliberate choice.
- No `// TODO: describe` is left: `grep -rn "TODO: describe" rtl/` is empty.
- The judgement list above has been walked, and anything that departs from
  it carries a DOC-009 comment.

Tell the user what you ran and what it reported, including any SHOULD
findings you left in place and why.

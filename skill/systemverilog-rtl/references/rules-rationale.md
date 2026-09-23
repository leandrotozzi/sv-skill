# SystemVerilog RTL rules — rationale and examples

Generated from `rules.toml` — do not edit.

## DOC — Comments and file header

### DOC-001 (MUST) — Every file opens with the standard header

Every `.sv` and `.svh` file begins with the copyright line, the all-rights-reserved line, and a `Description:` block that says what the file does.

**Why:** The description is the only part of a file that survives being read out of context -- in a diff, a search result, or a model's context window. Copyright and licence state must be mechanical, not remembered, because a file that ships without it is a legal problem discovered late.

**Good:**

```systemverilog
// Copyright (c) 2026 ACME Corp
// All rights reserved
//
// Description:
//   Synchronous FIFO with first-word-fall-through. Depth must be a power of
//   two. Full and empty are registered.
```

**Bad:**

```systemverilog
// fifo.sv
module fifo #(
```

**Enforced by:** svstyle `header` · autofixable

**Sources:** house style, lowRISC §Basic Template (shown as a template, not stated as a rule)

### DOC-002 (SHOULD) — The header carries a real description

The `Description:` block says what the module does and names its non-obvious constraints; it is not the module name restated.

**Why:** A description that repeats the identifier adds a line and no information. The constraints -- power-of-two depth, one-hot input assumption, latency -- are what a reader cannot recover from the port list.

**Good:**

```systemverilog
// Description:
//   Gray-code pointer synchroniser. Source and destination clocks are
//   asynchronous; the pointer must change by at most one per source clock.
```

**Bad:**

```systemverilog
// Description:
//   Gray counter module.
```

**Enforced by:** svstyle `header_description`

**Sources:** house style

### DOC-003 (MUST) — Every port carries a trailing comment

Each port declaration ends with a `//` comment describing the signal.

**Why:** The port list is the module's contract, and it is the one part of a module that other engineers and models read without opening the body. Direction and type are in the declaration; what the signal means, when it is valid and what it is relative to are not.

**Good:**

```systemverilog
input  logic        clk_i,    // System clock
input  logic        rst_ni,   // Asynchronous reset, active-low
input  logic [7:0]  data_i,   // Payload byte, valid while valid_i is high
output logic        ready_o   // Sink can accept a byte this cycle
```

**Bad:**

```systemverilog
input  logic        clk_i,
input  logic        rst_ni,
input  logic [7:0]  data_i,
output logic        ready_o
```

**Enforced by:** svstyle `port_comment` · autofixable

**Sources:** house style

### DOC-004 (MUST) — Every declaration carries a trailing comment

Each parameter, localparam, signal and net declaration statement ends with a `//` comment. Enumeration members are exempt.

**Why:** A declaration is where a signal's purpose can be stated once instead of re-derived at every use. Enum members are exempt because their meaning belongs on the FSM case arm that acts on them, which is where lowRISC puts it -- commenting both places guarantees the two drift apart.

**Good:**

```systemverilog
localparam int unsigned DepthW = $clog2(Depth);  // Bits needed to index the RAM
logic [DepthW-1:0] wptr_q, wptr_d;               // Write pointer, binary
```

**Bad:**

```systemverilog
localparam int unsigned DepthW = $clog2(Depth);
logic [DepthW-1:0] wptr_q, wptr_d;
```

**Enforced by:** svstyle `decl_comment` · autofixable

**Sources:** house style

### DOC-005 (MUST) — Every procedural block is introduced by a comment

A one-line `//` comment sits on the line above every `always_ff`, `always_comb` and `always_latch` block, saying what the block computes.

**Why:** Orientation without structure: the comment scrolls with the code and folds with it, so a reader skimming a collapsed module still sees what each block is for. Framed banner comments would do the same job but break native editor folding and rot when code moves.

**Good:**

```systemverilog
// Advance the write pointer on an accepted write.
always_ff @(posedge clk_i or negedge rst_ni) begin
```

**Bad:**

```systemverilog
always_ff @(posedge clk_i or negedge rst_ni) begin
```

**Enforced by:** svstyle `block_comment` · autofixable

**Sources:** house style

### DOC-006 (MUST) — Every instance is introduced by a comment

A one-line `//` comment sits on the line above every module instantiation, saying what the instance is for in this design.

**Why:** The instance name says which module; the comment says why this design needs it. A reader tracing a signal through a hierarchy needs the second, and it is the thing the code cannot state.

**Good:**

```systemverilog
// Two-flop synchroniser for the request from the slow domain.
prim_flop_2sync #(.Width(1)) u_req_sync (
```

**Bad:**

```systemverilog
prim_flop_2sync #(.Width(1)) u_req_sync (
```

**Enforced by:** svstyle `instance_comment` · autofixable

**Sources:** house style

### DOC-007 (MUST) — Comment placement follows the code it describes

A comment on its own line describes the code that follows; a comment on a line with code describes that line. Use `//`, not `/* */`.

**Why:** Quoting lowRISC: "A comment on its own line describes the code that follows. A comment on a line with code describes that line of code." Consistent placement is what lets a tool insert and a reader trust trailing comments at all.

**Good:**

```systemverilog
// Hold the request until the far side acknowledges.
assign req_d = req_q & ~ack_i;  // Cleared by the synchronised ack
```

**Bad:**

```systemverilog
assign req_d = req_q & ~ack_i;
// Hold the request until the far side acknowledges.
```

**Enforced by:** review only

**Sources:** lowRISC §Comments

### DOC-008 (MUST) — Every FSM state arm is introduced by a comment

Each state alternative inside an FSM case statement is preceded by a comment describing that state's function; those descriptions do not also live on the enum declaration.

**Why:** Quoting lowRISC: "each state alternative should be preceded with a comment that describes the function of that state within the state machine". Keeping the description on the arm and not on the enum member means there is one copy to keep true.

**Good:**

```systemverilog
// IDLE: wait for a request; nothing is in flight.
IDLE: begin
  if (req_i) state_d = BUSY;
end
```

**Bad:**

```systemverilog
typedef enum logic [1:0] {
  IDLE,  // wait for a request
  BUSY   // transfer in flight
} state_e;
```

**Enforced by:** review only

**Sources:** lowRISC §Finite State Machines

### DOC-009 (MUST) — Every deviation from this style is justified in a comment

Code that deliberately departs from a rule in this guide carries a brief comment saying why, plus a lint waiver pragma where the tool supports one.

**Why:** Quoting lowRISC: "It is always okay to deviate from the style guide by necessity, as long as that necessity is clearly justified by a brief comment". An unexplained deviation is indistinguishable from a mistake, so the next reader either breaks it or copies it.

**Good:**

```systemverilog
wire tri_bus;  // Must be wire: connects to an inout port (style exception)
```

**Bad:**

```systemverilog
wire tri_bus;
```

**Enforced by:** review only

**Sources:** lowRISC §Style Guide Exceptions

### DOC-010 (SHOULD) — Long conditional blocks close with a matching label

A `` `endif`` far from its `` `ifdef`` carries a comment naming the condition it closes, and a named `begin` closes as `end : name`.

**Why:** The opening condition has scrolled off screen by the time the reader reaches the close; without the label, matching them is a manual count. Verible checks both mechanically.

**Good:**

```systemverilog
`ifdef SYNTHESIS
  // ...
`endif  // SYNTHESIS
```

**Bad:**

```systemverilog
`ifdef SYNTHESIS
  // ...
`endif
```

**Enforced by:** verible lint `endif-comment` `mismatched-labels`

**Sources:** lowRISC §Comments, Verible

## STR — File structure

### STR-001 (MUST) — One module per file, named after the module

A source file contains exactly one module, package or interface, and the file's basename is that design unit's name.

**Why:** Every build system, waveform viewer and synthesis report addresses design units by name and finds them by filename. When the two disagree the mapping becomes a lookup only the author knows.

**Good:**

```systemverilog
// fifo_sync.sv
module fifo_sync #(
```

**Bad:**

```systemverilog
// fifo.sv
module fifo_sync #(
```

**Enforced by:** verible lint `module-filename` `package-filename` `one-module-per-file`

**Sources:** lowRISC §Files, Verilator DECLFILENAME

### STR-002 (MUST) — SystemVerilog files use `.sv`, headers use `.svh`

SystemVerilog source files are named `.sv`; files intended to be `` `include``d are named `.svh`.

**Why:** The extension is how every tool decides whether to compile a file as a translation unit or treat it as text to be pulled into one. A header compiled standalone fails in ways that read as syntax errors far from the cause.

**Good:**

```systemverilog
prim_assert.svh
```

**Bad:**

```systemverilog
prim_assert.sv  // but only ever `include`d
```

**Enforced by:** review only

**Sources:** lowRISC §Files

### STR-003 (SHOULD) — Declare signals close to their first use

Signals, types, enums and localparams are declared close to where they are first used, grouped with the logic that drives them, rather than hoisted into a block at the top of the module.

**Why:** Quoting lowRISC: "This makes it easier for the reader to find the declaration and see the signal type." Measured practice agrees -- 74.9% of OpenTitan declarations follow the first statement of the module. A hoisted block puts the type a screen away from every use.

**Good:**

```systemverilog
// Write pointer, binary, wraps at Depth.
logic [PtrW-1:0] wptr_q, wptr_d;
always_ff @(posedge clk_i or negedge rst_ni) begin
```

**Bad:**

```systemverilog
logic [PtrW-1:0] wptr_q, wptr_d;
logic [PtrW-1:0] rptr_q, rptr_d;
logic            full, empty;
// ... 200 lines ...
```

**Enforced by:** review only

**Sources:** lowRISC §Declarations, OpenTitan practice (74.9% near-use)

### STR-004 (MUST) — Packages do not depend on each other cyclically

Package dependencies form a directed acyclic graph; two packages never import each other.

**Why:** SystemVerilog has no forward declaration for package contents, so a cycle has no legal compilation order. Tools that appear to accept one are relying on file order, which changes silently when the build system does.

**Good:**

```systemverilog
package top_pkg;
  import common_pkg::*;  // common_pkg imports nothing from top_pkg
```

**Bad:**

```systemverilog
package a_pkg; import b_pkg::*; endpackage
package b_pkg; import a_pkg::*; endpackage
```

**Enforced by:** review only

**Sources:** lowRISC §Packages

### STR-005 (SHOULD) — Wildcard imports are local and justified

`import pkg::*;` is used only for a package belonging to the same IP as the importing module, and the import sits in the module header rather than at file scope.

**Why:** A file-scope wildcard import leaks every name in the package into every design unit in the file and into anything that includes it, so a later addition to the package can capture an identifier that already resolved elsewhere. Scoping it to the module bounds the damage to one unit.

**Good:**

```systemverilog
module hmac_core
  import hmac_pkg::*;
#(
```

**Bad:**

```systemverilog
import hmac_pkg::*;
module hmac_core #(
```

**Enforced by:** review only

**Sources:** lowRISC §Packages

## PRT — Ports and connections

### PRT-001 (MUST) — Ports are declared in ANSI style, one per line

Module ports use the Verilog-2001 combined port-and-direction style, one port per line, with the closing `);` on its own line.

**Why:** The non-ANSI style splits each port's direction, type and order across three places, so adding a port means three consistent edits and the compiler catches only some mistakes. One port per line is also what makes a trailing comment per port possible at all.

**Good:**

```systemverilog
module fifo_sync #(
  parameter int unsigned Depth = 8  // Entries; must be a power of two
) (
  input  logic clk_i,   // System clock
  input  logic rst_ni   // Asynchronous reset, active-low
);
```

**Bad:**

```systemverilog
module fifo_sync (clk, rst_n);
  input clk;
  input rst_n;
```

**Enforced by:** svstyle `ansi_ports`

**Sources:** lowRISC §Module Declaration

### PRT-002 (MUST) — Clocks first, then resets, then the rest

The port list opens with the clock port(s), then all reset inputs, then the remaining ports grouped by interface.

**Why:** A fixed prefix means the reader checks the clocking and reset scheme of an unfamiliar module by looking at one place, and an instantiation's first two lines are comparable across every module in the tree.

**Good:**

```systemverilog
input  logic clk_i,    // System clock
input  logic rst_ni,   // Asynchronous reset, active-low
input  logic req_i,    // Transfer request
```

**Bad:**

```systemverilog
input  logic req_i,    // Transfer request
input  logic clk_i,    // System clock
input  logic rst_ni,   // Asynchronous reset, active-low
```

**Enforced by:** review only

**Sources:** lowRISC §Module Declaration

### PRT-003 (MUST) — Instance ports are connected by name, never by position or `.*`

Every instantiation connects ports by name. Positional connection and `.*` are not used in synthesizable RTL.

**Why:** A positional list breaks silently when a port is inserted, and `.*` makes the connection depend on names matching in two files that no longer have to agree in writing -- a renamed signal connects to nothing and reports nothing. Measured practice agrees: `.*` appears in 28 OpenTitan files and every one of them is under dv/, fpv/, cov/ or sva/, never in synthesizable RTL.

**Good:**

```systemverilog
fifo_sync u_fifo (
  .clk_i  (clk_i),
  .rst_ni (rst_ni),
  .data_i (data_i)
);
```

**Bad:**

```systemverilog
fifo_sync u_fifo (.*);
fifo_sync u_fifo (clk_i, rst_ni, data_i);
```

**Enforced by:** svstyle `named_ports`

**Sources:** lowRISC §Module Instantiation, BSG §prohibitions, OpenTitan practice (0 uses in RTL)

### PRT-004 (MUST) — Every port of an instance is connected explicitly

Every declared port appears in every instantiation, in declaration order; unused outputs are written as explicit no-connects and unused inputs are tied off explicitly.

**Why:** An omitted port is indistinguishable from an oversight, and an unconnected input floats to `z` or a tool-dependent default rather than failing. Writing the tie-off states the intent where the next reader will look for it.

**Good:**

```systemverilog
.status_o (),          // Unused: this instance never reports status
.debug_i  (1'b0),      // Tied off: debug hooks are not built in this config
```

**Bad:**

```systemverilog
// status_o and debug_i simply absent from the instantiation
```

**Enforced by:** review only

**Sources:** lowRISC §Module Instantiation

### PRT-005 (MUST) — Parameters are overridden by name, never by `defparam`

Instance parameters are specified by name in the `#(...)` list. `defparam` is not used.

**Why:** `defparam` applies from a distance, so the effective parameter value of an instance cannot be read from the instantiation; its elaboration order is also weakly specified and it is deprecated in IEEE 1800. Named overrides keep the value where the instance is.

**Good:**

```systemverilog
fifo_sync #(
  .Depth (16)
) u_fifo (
```

**Bad:**

```systemverilog
fifo_sync u_fifo ( ... );
defparam u_fifo.Depth = 16;
```

**Enforced by:** verible lint `forbid-defparam` `module-port`

**Sources:** lowRISC §Module Instantiation, Verilator DEFPARAM

### PRT-006 (SHOULD) — Interfaces are not used as ports of reusable RTL

Synthesizable, reusable modules take individual signals or packed structs as ports, not SystemVerilog interfaces.

**Why:** Interface-typed ports have uneven synthesis support across Vivado, Quartus, Design Compiler, Genus and Yosys, and they hide the module's real fan-in and fan-out from lint and CDC tools. Measured practice is unanimous: zero interface-typed ports in synthesizable RTL across OpenTitan, Ibex and PULP.

**Good:**

```systemverilog
input  tlul_pkg::tl_h2d_t tl_i,   // TileLink host-to-device, packed struct
output tlul_pkg::tl_d2h_t tl_o    // TileLink device-to-host
```

**Bad:**

```systemverilog
tlul_if.device tl   // interface port in a reusable module
```

**Enforced by:** review only

**Sources:** PULP practice, OpenTitan/Ibex/PULP measurement (0 uses)

### PRT-007 (SHOULD) — Handshake suffixes state the protocol contract

A ready/valid interface names its backpressure signal for the protocol it implements: `_ready_and_o` when neither signal may depend combinationally on the other, `_ready_then_o` when valid may depend on ready, `_yumi_o` when the accept may depend on valid. A bare `_ready_o` does not say which.

**Why:** The difference between these protocols is which signal is allowed to depend combinationally on which, and getting it wrong creates a combinational loop only at the point where two modules are finally connected -- often across a hierarchy boundary, long after both passed lint alone. The name is the only place the contract can live, because no linter can check it. Only `ready_and` and `credit` are safe at a top level where both ends are unknown.

**Good:**

```systemverilog
output logic data_ready_and_o,  // r&v: must not depend on data_valid_i
input  logic data_valid_i       // r&v: must not depend on data_ready_and_o
```

**Bad:**

```systemverilog
output logic data_ready_o   // Which protocol? The consumer cannot tell.
```

**Enforced by:** review only

**Sources:** BSG SystemVerilog coding standard §handshakes, Taylor et al., DAC 2018

## NAM — Naming

### NAM-001 (MUST) — Identifiers are lower_snake_case

Modules, packages, interfaces, instances, signals, ports, variables, functions, tasks and named blocks are named in `lower_snake_case`.

**Why:** A single case convention means a reader never has to decide whether a difference in case is meaningful. The exceptions below -- parameters, constants, macros, types -- are deliberate: each marks a category of identifier whose binding time differs from a signal's.

**Good:**

```systemverilog
logic [7:0] write_data_q;
```

**Bad:**

```systemverilog
logic [7:0] writeData_q;
```

**Enforced by:** verible lint `signal-name-style` `interface-name-style` `struct-union-name-style`

**Sources:** lowRISC §Naming Conventions

### NAM-002 (MUST) — Ports carry a direction suffix

Module inputs end in `_i`, outputs in `_o`, and bidirectionals in `_io`.

**Why:** Direction is declared once in the port list but read at every use inside the module and at every connection outside it. The suffix carries it to both places, so a signal driven in the wrong direction is visible where the mistake is written rather than where it is compiled.

**Good:**

```systemverilog
input  logic       req_i,    // Transfer request
output logic [7:0] data_o    // Payload
```

**Bad:**

```systemverilog
input  logic       req,
output logic [7:0] data
```

**Enforced by:** verible lint `port-name-suffix`

**Sources:** lowRISC §Suffixes

### NAM-003 (MUST) — Suffixes stack in a fixed order

Multiple suffixes are concatenated without extra underscores, with `_n` first and `_i`/`_o`/`_io` last: `rst_ni`, `data_qi`, `valid_no`.

**Why:** Without a fixed order the same signal is spelled `rst_in` in one module and `rst_ni` in the next, and the two no longer sort, grep or connect as the same name. Active-low-before-direction also keeps the direction as the true final token, which is what the linter's suffix regex anchors on.

**Good:**

```systemverilog
input logic rst_ni,  // Asynchronous reset, active-low
```

**Bad:**

```systemverilog
input logic rst_in,  // same signal, different spelling
```

**Enforced by:** review only

**Sources:** lowRISC §Suffixes

### NAM-004 (MUST) — Flop pairs are `_q` and `_d`

A registered signal is named `<name>_q` and the value driving its input `<name>_d`; the two are declared together.

**Why:** The pair makes a register visible as a register at every use, so reading a value one cycle late -- the most common RTL mistake -- becomes a spelling difference the reader can see rather than a timing property they have to reconstruct.

**Good:**

```systemverilog
logic [7:0] count_q, count_d;  // Byte counter
always_comb count_d = count_q + 8'd1;
```

**Bad:**

```systemverilog
logic [7:0] count, count_next;
```

**Enforced by:** verible lint `dff-name-style`

**Sources:** lowRISC §Suffixes

### NAM-005 (MUST) — Type names end in `_e` or `_t`

Enumeration types are named `lower_snake_case_e`, other typedefs `lower_snake_case_t`, and every enum and struct used as a type is given a typedef name.

**Why:** A declaration reads `state_e state_q;` -- type and variable are distinguishable without looking either up. Anonymous enums and structs cannot be named in a port list, a function signature or a package, so they force a copy of the definition at each use.

**Good:**

```systemverilog
typedef enum logic [1:0] { IDLE, BUSY, DONE } state_e;  // Transfer states
state_e state_q, state_d;                               // Current/next state
```

**Bad:**

```systemverilog
enum logic [1:0] { IDLE, BUSY, DONE } state_q, state_d;
```

**Enforced by:** verible lint `enum-name-style` `typedef-enums` `typedef-structs-unions`

**Sources:** lowRISC §Naming Conventions

### NAM-006 (SHOULD) — Parameters are UpperCamelCase, true constants ALL_CAPS

Tunable parameters and the localparams derived from them are named in `UpperCamelCase`; values that are immutable facts rather than tuning knobs are named in `ALL_CAPS`.

**Why:** The case says whether overriding the value at instantiation is expected. Both spellings are accepted by the linter's CamelCase check, which matches lowRISC's own split rather than contradicting it. Measured practice: 99.8% UpperCamel across lowRISC code.

**Good:**

```systemverilog
parameter  int unsigned Depth  = 8;             // Entries; override per instance
localparam int unsigned PtrW   = $clog2(Depth); // Derived, not tunable
localparam logic [7:0]  SOF_BYTE = 8'h7E;       // Protocol constant, immutable
```

**Bad:**

```systemverilog
parameter int unsigned depth = 8;
```

**Enforced by:** verible lint `parameter-name-style` `parameter-type-name-style`

**Sources:** lowRISC §Naming Conventions, lowRISC practice (99.8% UpperCamel)

### NAM-007 (SHOULD) — Parameter names state the positive sense

A boolean parameter is named for the condition being true (`EnableLogging`), not negated (`DisableLogging`).

**Why:** A negated name turns every use into a double negative -- `if (!DisableLogging)` -- which is where sign mistakes hide. Defaults also read wrong: `DisableLogging = 0` requires two steps to mean "logging is on".

**Good:**

```systemverilog
parameter bit EnableAssertions = 1;  // Compile the SVA blocks
```

**Bad:**

```systemverilog
parameter bit DisableAssertions = 0;
```

**Enforced by:** verible lint `positive-meaning-parameter-name`

**Sources:** Verible, house style

### NAM-008 (SHOULD) — Macros are ALL_CAPS and prefixed by their group

`` `define`` macros are named in `ALL_CAPS`. A globally visible macro is prefixed with its group name and a double underscore; a file-local macro is prefixed with a single underscore and `` `undef``ed after use.

**Why:** Macros ignore every scope in the language, so the name is the only namespace they have. Undefining a file-local macro keeps it from leaking into whatever file includes this one next, where a collision would silently take the wrong definition.

**Good:**

```systemverilog
`define PRIM_ASSERT__VALID(x) ...
`define _local_helper(x) ...
`undef _local_helper
```

**Bad:**

```systemverilog
`define VALID(x) ...
```

**Enforced by:** verible lint `macro-name-style` `macro-string-concatenation`

**Sources:** lowRISC §Naming Conventions

### NAM-009 (SHOULD) — Names describe purpose in whole words

Signal names say what the signal is for, using whole words; signals that work together share a prefix, and a signal in a non-default clock domain is prefixed with that domain's identifier.

**Why:** The clock-domain prefix is the load-bearing half: it makes a crossing visible at the point of assignment, so `assign vdata = udata;` reads as a bug on the line where it is written rather than at CDC-analysis time. Whole words matter because the reader of an abbreviation is usually not its author.

**Good:**

```systemverilog
logic [7:0] uart_rx_data_q;   // uClk domain
logic [7:0] vsync_rx_data_q;  // vClk domain -- crossing is visible here
```

**Bad:**

```systemverilog
logic [7:0] urxd_q;
logic [7:0] vrxd_q;
```

**Enforced by:** review only

**Sources:** lowRISC §Use descriptive names, Cummings SNUG-2001 §clock domain naming

### NAM-010 (MUST) — Keywords are never used as names

No identifier reuses a Verilog or SystemVerilog keyword, including keywords added after Verilog-2005.

**Why:** SystemVerilog reserved many words that were legal Verilog-2001 identifiers, so a name that compiles today can break when a tool moves to a newer language level -- as a syntax error far from the declaration.

**Good:**

```systemverilog
logic packet_type;
```

**Bad:**

```systemverilog
logic type;  // `type` is a SystemVerilog keyword
```

**Enforced by:** review only

**Sources:** lowRISC §Naming Conventions

## FMT — Formatting and layout

### FMT-001 (MUST) — The formatter owns whitespace

Indentation is two spaces, never tabs; lines carry no trailing whitespace; the file ends with exactly one newline; lines are at most 100 columns.

**Why:** Bundled into one rule because none of them is a judgement call -- the formatter produces all four and a reviewer never has to discuss any of them. Two spaces and 100 columns follow the RISC-V open-source ecosystem this style descends from; 80 is too narrow once names carry direction and register suffixes.

**Good:**

```systemverilog
always_comb begin
  data_d = data_i;
end
```

**Bad:**

```systemverilog
always_comb begin
	data_d = data_i;   
end
```

**Enforced by:** verible lint `no-tabs` `no-trailing-spaces` `posix-eof` `line-length` `forbid-line-continuations`

**Sources:** lowRISC §Basics, Verible defaults

### FMT-002 (MUST) — Port lists, parameters and named connections are tabular

Port declarations, formal parameters, named port connections, named parameter overrides, module-level net declarations, struct members and enum assignments are aligned into columns. Loose assignment statements and case items are not.

**Why:** These constructs are read as tables -- a reader scans one column to answer "what is the width of every port" -- and alignment is what makes the column exist. Loose assignments are excluded deliberately: aligning them makes every future edit rewrite its neighbours' whitespace, which is the cost that keeps Black from aligning anything. lowRISC requires alignment only for instantiation port expressions; the rest is ours, and costs nothing because the formatter does it.

**Good:**

```systemverilog
input  logic        clk_i,    // System clock
input  logic [31:0] addr_i,   // Byte address
output logic        valid_o   // Response valid
```

**Bad:**

```systemverilog
input logic clk_i, // System clock
input logic [31:0] addr_i, // Byte address
output logic valid_o // Response valid
```

**Enforced by:** verible format

**Sources:** lowRISC §Tabular Alignment, house style (the wider set)

### FMT-003 (MUST) — `begin` and `end` are always written

Every `if`, `else`, `for`, `while` and `always` body is wrapped in `begin`/`end`, even a single statement. `begin` sits on the line of the construct that opens it and `end else begin` is written on one line.

**Why:** A single-statement body that grows a second statement is a silent bug, and it is exactly the edit a model or a hurried human makes. This is stricter than lowRISC, which permits omitting `begin`/`end` when the whole statement fits on one line. Note the cost: neither the formatter nor the linter can insert `begin`/`end`, so on existing code every violation is a manual edit.

**Good:**

```systemverilog
if (clear_i) begin
  count_d = '0;
end else begin
  count_d = count_q + 1'b1;
end
```

**Bad:**

```systemverilog
if (clear_i) count_d = '0;
else count_d = count_q + 1'b1;
```

**Enforced by:** verible lint `explicit-begin` `module-begin-block`

**Sources:** house style (stricter than lowRISC §begin/end)

### FMT-004 (MUST) — No stray or duplicated semicolons

There are no empty statements from consecutive semicolons, and no semicolon after the `end` of a block or after a module or generate body.

**Why:** A stray semicolon after `if (cond);` silently makes the body empty and the following block unconditional -- it parses, simulates and synthesises, just not as written.

**Good:**

```systemverilog
if (valid_i) begin
  data_d = data_i;
end
```

**Bad:**

```systemverilog
if (valid_i);
begin
  data_d = data_i;
end
```

**Enforced by:** verible lint `forbid-consecutive-null-statements` `suspicious-semicolon`

**Sources:** Verible

### FMT-005 (SHOULD) — Mixed operators are parenthesised

An expression mixing operators of different precedence carries explicit parentheses around the intended grouping.

**Why:** SystemVerilog's precedence table places the bitwise and comparison operators in an order that surprises most readers coming from C, and the failure is a wrong-but-plausible value rather than an error.

**Good:**

```systemverilog
assign hit = (tag_q == tag_i) && (valid_q | force_i);
```

**Bad:**

```systemverilog
assign hit = tag_q == tag_i && valid_q | force_i;
```

**Enforced by:** verible lint `suggest-parentheses`

**Sources:** Verible

## LNG — Language features

### LNG-001 (MUST) — `logic` everywhere; `wire` only for a real tri-state

Signals are declared `logic`. `wire` appears only where a net is genuinely multiply driven, which in practice means a bidirectional pad, and carries a comment saying so.

**Why:** `logic` is four-state like `reg` and `wire` but carries a single-driver check the compiler enforces, so an accidental second driver is an error at elaboration instead of a resolved value that simulates as `x` and synthesises as a short.

**Good:**

```systemverilog
logic [7:0] data_q;  // Registered payload
```

**Bad:**

```systemverilog
reg [7:0] data_q;
```

**Enforced by:** review only

**Sources:** lowRISC §Use logic for synthesis

### LNG-002 (MUST) — Sequential logic is `always_ff` with nonblocking assignments

Clocked logic is written in `always_ff` and assigns only with `<=`.

**Why:** Cummings SNUG-2000 guideline #1. Blocking assignments in a clocked block execute in the active region of the stratified event queue, so a flop reading another flop assigned earlier in the same block sees the new value instead of the old one -- the simulation shows one pipeline stage where the synthesised gates have two, and which one you get depends on statement order.

**Good:**

```systemverilog
always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    b_q <= '0;
  end else begin
    b_q <= a_q;   // Reads the OLD a_q, as the hardware does
  end
end
```

**Bad:**

```systemverilog
always_ff @(posedge clk_i) begin
  a_q = data_i;
  b_q = a_q;      // Reads the NEW a_q: one flop in sim, two in gates
end
```

**Enforced by:** verible lint `always-ff-non-blocking`

**Sources:** Cummings SNUG-2000 guideline #1, lowRISC §Sequential Logic

### LNG-003 (MUST) — Combinational logic is `always_comb` with blocking assignments

Combinational logic is written in `always_comb` and assigns only with `=`. `always @(*)` and manual sensitivity lists are not used.

**Why:** Cummings SNUG-2000 guideline #3, plus the sensitivity-list half: `always_comb` is checked by the tool for completeness and for having no blocking/nonblocking mix, where `always @(*)` is inferred and an incomplete manual list produces a latch in synthesis that simulation does not show. Nonblocking assignments inside a combinational block defer the update to the NBA region, so a value read later in the same block is stale.

**Good:**

```systemverilog
always_comb begin
  sum = a_i + b_i;
  carry = sum[8];     // Sees the value just assigned
end
```

**Bad:**

```systemverilog
always @(a_i) begin   // b_i missing: latch
  sum <= a_i + b_i;
end
```

**Enforced by:** verible lint `always-comb` `always-comb-blocking`

**Sources:** Cummings SNUG-2000 guidelines #3, #10, lowRISC §Combinational Logic

### LNG-004 (MUST) — Blocking and nonblocking assignments are never mixed in one block

A single `always` block uses either `=` or `<=` throughout, never both.

**Why:** Cummings SNUG-2000 guideline #5. A mixed block splits its own updates across the active and NBA regions, so the behaviour depends on the order the two kinds of statement happen to appear in -- and is not what either kind alone would give.

**Good:**

```systemverilog
always_ff @(posedge clk_i) begin
  a_q <= a_d;
  b_q <= b_d;
end
```

**Bad:**

```systemverilog
always_ff @(posedge clk_i) begin
  temp = a_d;
  b_q <= temp;
end
```

**Enforced by:** verilator `BLKSEQ` `COMBDLY`

**Sources:** Cummings SNUG-2000 guideline #5

### LNG-005 (MUST) — A signal is driven from exactly one block

No variable is assigned from more than one `always` block or continuous assignment.

**Why:** Cummings SNUG-2000 guideline #6. Two blocks assigning one variable race: the simulator may execute them in either order within a time step, and synthesis resolves the conflict as a short or an arbitrary winner. The failure is order-dependent, so it often appears only after an unrelated edit.

**Good:**

```systemverilog
always_comb begin
  data_d = load_i ? data_i : data_q;
end
```

**Bad:**

```systemverilog
always_comb data_d = data_i;
always_comb if (hold_i) data_d = data_q;
```

**Enforced by:** verilator `MULTIDRIVEN`

**Sources:** Cummings SNUG-2000 guideline #6

### LNG-006 (MUST) — Every combinational output has a default assignment

A combinational block assigns a default value to every signal it drives, immediately after the block opens and before any conditional logic.

**Why:** Cummings SNUG-1999 §synthesis mismatch. A signal left unassigned on some path through a combinational block must hold its previous value, which is a latch -- inferred silently, sensitive to a clock it was never meant to have, and usually found in static timing analysis rather than simulation.

**Good:**

```systemverilog
always_comb begin
  valid_o = 1'b0;         // Default
  data_o  = '0;           // Default
  if (hit_i) begin
    valid_o = 1'b1;
    data_o  = payload_i;
  end
end
```

**Bad:**

```systemverilog
always_comb begin
  if (hit_i) begin
    valid_o = 1'b1;       // valid_o latches when hit_i is low
    data_o  = payload_i;
  end
end
```

**Enforced by:** verilator `LATCH`

**Sources:** Cummings SNUG-1999 §synthesis mismatch, lowRISC §Combinational Logic

### LNG-007 (MUST) — Every `case` has a `default`

Every `case`, `casez` and `unique case` statement has a `default` arm, even when it is empty or only raises an error.

**Why:** Without a default, any unlisted value leaves the case's outputs unassigned, which infers a latch in combinational logic and leaves the state unchanged in sequential logic. `unique` does not substitute: it adds a runtime check in simulation but does not supply a value, and the check is absent in synthesis.

**Good:**

```systemverilog
unique case (state_q)
  IDLE: state_d = req_i ? BUSY : IDLE;
  BUSY: state_d = done_i ? IDLE : BUSY;
  default: state_d = IDLE;   // Unreachable; recovers from an upset state
endcase
```

**Bad:**

```systemverilog
unique case (state_q)
  IDLE: state_d = req_i ? BUSY : IDLE;
  BUSY: state_d = done_i ? IDLE : BUSY;
endcase
```

**Enforced by:** verible lint `case-missing-default`

**Sources:** Cummings SNUG-2005, lowRISC §Case Statements, Verilator CASEINCOMPLETE

### LNG-008 (MUST) — Literals state their width

Sized literals state a width that matches their context; a literal is never wider than its declared size, and `'0`/`'1`/`'x` are used for context-width fills.

**Why:** An unsized literal is 32 bits wide, so comparing or assigning it silently zero-extends or truncates the other operand. Truncation of a constant is the case the compiler is least likely to warn about, because the value looks intentional.

**Good:**

```systemverilog
logic [7:0] byte_q;
assign byte_q = 8'hFF;
assign wide_q = '0;        // Context width, whatever it is
```

**Bad:**

```systemverilog
logic [7:0] byte_q;
assign byte_q = 9'h1FF;    // Truncated to 8'hFF, silently
```

**Enforced by:** verible lint `truncated-numeric-literal` `undersized-binary-literal` `numeric-format-string-style`

**Sources:** lowRISC §Number Formatting, Verilator WIDTH

### LNG-009 (MUST) — `casex` is not used; `casez` is used sparingly

`casex` does not appear in synthesizable RTL. `casez` is used only where the truth table genuinely has don't-care bits, with don't-cares written as `?` and never as `z`.

**Why:** Cummings SNUG-1999. `casex` treats `x` as a don't-care in the case *expression* as well as the items, so an input that is still unknown silently matches the first arm -- in his cited case an input unknown after reset release was masked in RTL simulation, gate-level simulation missed it, and the first ASIC came back flawed. `casez` has the same mechanism but only a floating `z` can trigger it, which is far less likely to mask a reset bug.

**Good:**

```systemverilog
casez (opcode_i)
  8'b0000_????: op_d = OP_ALU;
  8'b0001_????: op_d = OP_LOAD;
  default:      op_d = OP_ILLEGAL;
endcase
```

**Bad:**

```systemverilog
casex (opcode_i)
  8'b0000_xxxx: op_d = OP_ALU;   // Matches when opcode_i is itself unknown
endcase
```

**Enforced by:** review only

**Sources:** Cummings SNUG-1999 §casex

### LNG-010 (MUST) — Functions and tasks are `automatic` with typed arguments

Every function and task declares an explicit `automatic` lifetime, an explicit return type, and an explicit direction and type on each argument.

**Why:** A static-lifetime function shares one copy of its locals across every call, so two concurrent calls corrupt each other -- and static is the default in a module. Explicit types stop the implicit single-bit default from silently truncating a wider argument.

**Good:**

```systemverilog
function automatic logic [7:0] parity_byte(input logic [7:0] data);
  return {^data, data[6:0]};
endfunction
```

**Bad:**

```systemverilog
function parity_byte(data);
  parity_byte = {^data, data[6:0]};
endfunction
```

**Enforced by:** verible lint `explicit-function-lifetime` `explicit-task-lifetime` `explicit-function-task-parameter-type`

**Sources:** lowRISC §Functions and Tasks, Verible

### LNG-011 (MUST) — Parameters declare a storage type and the right keyword

`parameter` appears only in a module's formal parameter list; constants inside a module body are `localparam`. Both declare an explicit type.

**Why:** A `parameter` in a module body is overridable through the deprecated `defparam` path and confuses which values are part of the module's interface. An untyped parameter takes its type from its default value, so overriding `8` with `8'sd8` silently changes the arithmetic of every expression using it.

**Good:**

```systemverilog
module fifo #(
  parameter int unsigned Depth = 8       // Interface: tunable
) ();
  localparam int unsigned PtrW = $clog2(Depth);  // Body: derived
```

**Bad:**

```systemverilog
module fifo ();
  parameter Depth = 8;
```

**Enforced by:** verible lint `explicit-parameter-storage-type` `proper-parameter-declaration` `module-parameter`

**Sources:** lowRISC §Parameterized Modules, Verible

### LNG-012 (MUST) — Dimensions are declared big-endian and non-negative

Packed dimensions are declared `[N-1:0]` and unpacked dimensions `[0:N-1]` or `[N]`; no dimension may evaluate to a negative size.

**Why:** Mixing endianness across a design makes bit 0 mean the LSB in one module and the MSB in the next, so a part-select that looks symmetric reverses the field. A negative dimension comes from a parameter expression that underflows -- `$clog2(1)` is 0, so `[$clog2(Depth)-1:0]` is illegal at Depth = 1, which is the edge case the parameterised module is least likely to be tested at.

**Good:**

```systemverilog
logic [31:0] word_q;              // Packed: big-endian
logic [7:0]  buffer_q [0:15];     // Unpacked: little-endian
```

**Bad:**

```systemverilog
logic [0:31] word_q;
```

**Enforced by:** verible lint `packed-dimensions-range-ordering` `unpacked-dimensions-range-ordering` `forbid-negative-array-dim`

**Sources:** lowRISC §Dimensions, Verible

### LNG-013 (MUST) — No simulation-only system tasks in synthesizable code

Synthesizable RTL contains no system tasks or functions that exist only for simulation, and no `#` delays.

**Why:** Synthesis ignores delays and most system tasks rather than rejecting them, so the gates implement something the RTL simulation never showed. A `#` delay in RTL is also the classic way a race is hidden rather than fixed.

**Good:**

```systemverilog
assign data_o = data_q;
```

**Bad:**

```systemverilog
assign #1 data_o = data_q;
```

**Enforced by:** verible lint `invalid-system-task-function`

**Sources:** Cummings SNUG-2000 guideline #8, Verible

### LNG-014 (SHOULD) — `` `default_nettype none`` opens every file

Each `.sv` file begins with `` `default_nettype none`` after the header and ends with `` `resetall``.

**Why:** Without it, a misspelled identifier on the left of a continuous assignment creates a one-bit implicit net rather than an error -- the design compiles, and the signal is silently stuck. lowRISC does not use the directive (zero uses across OpenTitan, Ibex and PULP) but does mandate that "A correct design contains no inferred nets"; this is that rule made mechanical.

**Good:**

```systemverilog
`default_nettype none
module fifo_sync ( ... );
endmodule
`resetall
```

**Bad:**

```systemverilog
module fifo_sync ( ... );
  assign data_ou = data_q;   // typo: creates a 1-bit implicit net
```

**Enforced by:** svstyle `default_nettype` · autofixable

**Sources:** house style, lowRISC §Declare all signals (states the rule, not the directive), Verilator IMPLICIT

## SYN — Synthesis and portability

### SYN-001 (MUST) — `full_case` and `parallel_case` are never used

No case statement carries a `full_case` or `parallel_case` synthesis directive.

**Why:** Cummings SNUG-1999, "the evil twins". They live in comments, so the simulator ignores them while synthesis acts on them -- the design is described differently to the two tools by construction. `full_case` lets synthesis delete logic for values it now believes unreachable (his decoder loses its enable input entirely); `parallel_case` deletes a priority encoder that RTL simulation still models. They are most dangerous when they work, because nothing reports the divergence.

**Good:**

```systemverilog
unique case (sel_i)
  2'b00: y_o = a_i;
  2'b01: y_o = b_i;
  default: y_o = '0;
endcase
```

**Bad:**

```systemverilog
case (sel_i)  // synopsys full_case parallel_case
  2'b00: y_o = a_i;
  2'b01: y_o = b_i;
endcase
```

**Enforced by:** review only

**Sources:** Cummings SNUG-1999 §full_case parallel_case

### SYN-002 (SHOULD) — `unique` and `priority` replace the directives, with care

Use `unique case` with a `default` as the normal form. `priority case` states intentional overlap; plain `case` is used where neither claim holds.

**Why:** Cummings SNUG-2005: these are real keywords, so simulation, synthesis and formal all read them, and they double as runtime assertions. But they are not a blanket substitute -- a `default` nullifies `priority` entirely (only `unique`'s overlap check survives), neither removes a latch caused by unassigned outputs, and both raise runtime errors against the standard default-assign-then-partial-case idiom.

**Good:**

```systemverilog
unique case (state_q)
  IDLE: state_d = BUSY;
  BUSY: state_d = IDLE;
  default: state_d = IDLE;
endcase
```

**Bad:**

```systemverilog
priority case (state_q)
  IDLE: state_d = BUSY;
  default: state_d = IDLE;   // `default` makes `priority` mean nothing here
endcase
```

**Enforced by:** review only

**Sources:** Cummings SNUG-2005 §unique & priority

### SYN-003 (SHOULD) — Priority logic is written as if/else, parallel logic as case

Intentional priority is written as an `if`/`else if` chain; a `case` statement is reserved for logic whose arms are genuinely mutually exclusive.

**Why:** The construct states the designer's intent to every downstream tool and reader. A priority chain written as a case invites someone to add `parallel_case` later to "optimise" it, which is exactly the bug SYN-001 describes.

**Good:**

```systemverilog
if (err_i) begin
  resp_d = RESP_ERR;
end else if (valid_i) begin
  resp_d = RESP_OK;
end
```

**Bad:**

```systemverilog
case (1'b1)
  err_i:   resp_d = RESP_ERR;   // Overlapping arms in a `case`
  valid_i: resp_d = RESP_OK;
endcase
```

**Enforced by:** review only

**Sources:** Cummings SNUG-1999

### SYN-004 (MUST) — Modules are not instantiated recursively

A module does not instantiate itself, directly or through a cycle.

**Why:** Elaboration of a recursive hierarchy terminates only if the tool can prove the parameter sequence reaches the base case, and the tools disagree about which expressions they can prove. What elaborates in one synthesiser hangs in the next.

**Good:**

```systemverilog
// Write the recursion as a generate-for over a flat array of stages.
```

**Bad:**

```systemverilog
module tree #(parameter int N = 8) ();
  tree #(.N(N/2)) u_left ();
```

**Enforced by:** review only

**Sources:** lowRISC §Generate Constructs

## RST — Reset and clocking

### RST-001 (MUST) — Resets are asynchronous and active-low

Flip-flops are reset asynchronously by an active-low reset named `rst_ni`, written as `always_ff @(posedge clk_i or negedge rst_ni)` with the reset test as the first `if` in the block.

**Why:** This is the ecosystem's convention and measurement confirms it is followed, not just written: 902 of 959 reset `always_ff` blocks in OpenTitan and 108 of 130 in Ibex use async active-low, with exactly one positive-edge async reset in all of OpenTitan's hw/ip. Active-low matters physically -- a reset asserted by a pin being pulled low survives loss of the driver. Note that BSG argues the opposite (synchronous, high-true) precisely to avoid the de-assertion hazard RST-002 addresses; this style takes the async path and mandates the synchroniser instead.

**Good:**

```systemverilog
always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    count_q <= '0;
  end else begin
    count_q <= count_d;
  end
end
```

**Bad:**

```systemverilog
always_ff @(posedge clk_i) begin
  if (rst) begin      // synchronous, active-high
    count_q <= '0;
```

**Enforced by:** review only

**Sources:** lowRISC §Resets, Cummings SNUG-2003 §reset techniques, OpenTitan/Ibex measurement (94.1% / 83.1%)

### RST-002 (MUST) — Every asynchronous reset passes through a reset synchroniser

An asynchronous reset entering a clock domain is asserted asynchronously but de-asserted synchronously, through a two-flop reset synchroniser in that domain.

**Why:** Cummings SNUG-2003, verbatim: "EVERY ASIC USING AN ASYNCHRONOUS RESET SHOULD INCLUDE A RESET SYNCHRONIZER CIRCUIT!!" Assertion is safe because it bypasses the clock path. Removal is the bug, two ways: de-asserting inside a flop's reset *recovery* window leaves it metastable, so the chip silently loses its reset state -- an intermittent field failure the controlled simulation never reproduces; and an asynchronous removal lets clock- and reset-tree skew release some flops a cycle before others, starting the design in a state nobody simulated. The synchroniser collapses this into one closed timing budget.

**Good:**

```systemverilog
// Reset synchroniser: async assert, sync de-assert into clk_i.
always_ff @(posedge clk_i or negedge rst_ext_ni) begin
  if (!rst_ext_ni) begin
    {rst_q, rst_meta_q} <= 2'b00;
  end else begin
    {rst_q, rst_meta_q} <= {rst_meta_q, 1'b1};
  end
end
```

**Bad:**

```systemverilog
// External async reset driven straight into every flop in the domain.
always_ff @(posedge clk_i or negedge rst_ext_ni) begin
```

**Enforced by:** review only

**Sources:** Cummings SNUG-2003 §reset synchronizer

### RST-003 (MUST) — Each clock domain has its own reset synchroniser

In a multi-clock design, every clock domain instantiates its own reset synchroniser and its own reset distribution tree.

**Why:** A reset de-asserted synchronously to one clock is asynchronous to every other, so sharing one synchroniser reintroduces exactly the recovery-window failure it was there to prevent -- in the domains nobody looked at.

**Good:**

```systemverilog
rst_sync u_rst_sync_sys  (.clk_i(sys_clk_i),  .rst_ni(rst_ext_ni), .rst_no(sys_rst_ni));
rst_sync u_rst_sync_usb  (.clk_i(usb_clk_i),  .rst_ni(rst_ext_ni), .rst_no(usb_rst_ni));
```

**Bad:**

```systemverilog
// One synchroniser in the sys domain; usb flops use sys_rst_ni.
```

**Enforced by:** review only

**Sources:** Cummings SNUG-2003

### RST-004 (SHOULD) — Only control state is reset

Reset the flops that must hold a known value at startup -- state machines, counters, valid bits, configuration -- and leave datapath registers unreset.

**Why:** Every reset flop costs a reset-tree endpoint, routing and a larger cell, and the reset tree is one of the hardest nets to close timing on. A datapath register whose value is qualified by a valid bit does not need a defined value at startup, because nothing reads it until the valid bit says so.

**Good:**

```systemverilog
always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    valid_q <= 1'b0;      // Control: reset
  end else begin
    valid_q <= valid_d;
  end
end
always_ff @(posedge clk_i) begin
  data_q <= data_d;       // Datapath: qualified by valid_q, not reset
end
```

**Bad:**

```systemverilog
// Every flop in a 512-bit datapath tied to the reset tree.
```

**Enforced by:** review only

**Sources:** Xilinx UG949 §reset strategy, OpenTitan practice (57 unreset always_ff blocks)

### RST-005 (MUST) — Reset and clock nets are not mixed

A signal used as an asynchronous reset is not also used as ordinary data, and a clock is not gated with combinational logic; clock gating uses a dedicated integrated clock-gating cell.

**Why:** A net that reaches both a reset pin and a data pin cannot be timed as either, and the synthesis tool picks one. A clock gated by `if (en)` in RTL produces glitches on the gated clock that the RTL simulation cannot show, because RTL has no notion of a glitch.

**Good:**

```systemverilog
prim_clock_gating u_cg (
  .clk_i    (clk_i),
  .en_i     (enable_q),
  .clk_o    (clk_gated)
);
```

**Bad:**

```systemverilog
assign clk_gated = clk_i & enable_q;   // Glitches on every enable change
```

**Enforced by:** verilator `SYNCASYNCNET`

**Sources:** Cummings SNUG-2001, Verilator SYNCASYNCNET

## FSM — State machines

### FSM-001 (MUST) — State is a typed enum with `_q`/`_d`

FSM state is held in a variable of a `typedef enum` type, named `state_q` with next state `state_d`. State encodings are never `` `define`` macros.

**Why:** Cummings SNUG-2003 §SystemVerilog FSM. A typed enum gives the tool a closed set of legal values, so an assignment of an out-of-range constant is an error and waveform viewers show state names instead of numbers. Macros have no type, no scope and no tool visibility.

**Good:**

```systemverilog
typedef enum logic [1:0] { IDLE, BUSY, DONE } state_e;  // Transfer states
state_e state_q, state_d;                               // Current/next state
```

**Bad:**

```systemverilog
`define IDLE 2'b00
logic [1:0] state;
```

**Enforced by:** review only

**Sources:** Cummings SNUG-2003 §SystemVerilog FSM, lowRISC §Finite State Machines

### FSM-002 (SHOULD) — FSMs use the two- or three-block style

An FSM is written as a sequential `always_ff` holding the state register plus a combinational `always_comb` computing next state and outputs; a third `always_ff` is added when outputs must be registered.

**Why:** Cummings SNUG-2000 §FSM. Separating the register from the next-state logic means the reset, the clocking and the state transition each appear exactly once, and the combinational block can be read as a pure function of current state and inputs. A single-block FSM makes every output a registered output whether or not that was intended.

**Good:**

```systemverilog
// State register.
always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    state_q <= IDLE;
  end else begin
    state_q <= state_d;
  end
end

// Next-state and output logic.
always_comb begin
  state_d = state_q;
  ...
end
```

**Bad:**

```systemverilog
always_ff @(posedge clk_i) begin
  case (state_q)
    IDLE: if (req_i) begin state_q <= BUSY; out_q <= 1'b1; end
```

**Enforced by:** review only

**Sources:** Cummings SNUG-2000 §FSM coding styles

### FSM-003 (SHOULD) — FSM outputs crossing a module boundary are registered

An FSM does not drive combinational (Mealy) outputs across a module boundary; such outputs are registered first, or the output logic moves into the consuming module.

**Why:** Cummings SNUG-2000. A combinational output depends on the FSM's inputs in the same cycle, so it arrives late and its timing path continues into whatever the consumer does with it -- a path that neither module's timing constraints describe on its own.

**Good:**

```systemverilog
always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    grant_o <= 1'b0;
  end else begin
    grant_o <= (state_d == GRANTED);
  end
end
```

**Bad:**

```systemverilog
assign grant_o = (state_q == IDLE) && req_i;   // Mealy, leaves the module
```

**Enforced by:** review only

**Sources:** Cummings SNUG-2000 §FSM outputs

### FSM-004 (SHOULD) — One FSM per module

A module contains at most one state machine.

**Why:** Two FSMs in one module share a namespace and a reset block, so their states, transitions and outputs interleave in the source and neither can be read on its own. Splitting them also makes each one's interface -- and therefore its contract -- explicit.

**Good:**

```systemverilog
// arbiter_fsm.sv and refill_fsm.sv, instantiated side by side.
```

**Bad:**

```systemverilog
// One module holding state_q and mode_q, each a separate FSM.
```

**Enforced by:** review only

**Sources:** Cummings SNUG-2000, lowRISC §Finite State Machines

## CDC — Clock domain crossing

### CDC-001 (MUST) — Single-bit crossings go through a two-flop synchroniser

Every one-bit signal crossing an asynchronous clock boundary passes through two flip-flops clocked by the destination clock, with no logic between them.

**Why:** Cummings SNUG-2001. Across asynchronous domains a setup/hold violation on the first flop is a certainty, not a risk -- the phase relationship changes continuously. The second flop gives the first a full clock period for metastability to decay before anything samples it. Without it, a metastable output fans out and different gates resolve it differently, so the design disagrees with itself.

**Good:**

```systemverilog
always_ff @(posedge dst_clk_i or negedge dst_rst_ni) begin
  if (!dst_rst_ni) begin
    {sync_q, meta_q} <= 2'b00;
  end else begin
    {sync_q, meta_q} <= {meta_q, src_signal_i};
  end
end
```

**Bad:**

```systemverilog
always_ff @(posedge dst_clk_i) begin
  captured_q <= src_signal_i;   // One flop: metastability reaches the logic
end
```

**Enforced by:** review only

**Sources:** Cummings SNUG-2001 §synchronizers

### CDC-002 (MUST) — A multi-bit bus is never crossed bit by bit

A multi-bit value is not crossed by putting a two-flop synchroniser on each bit.

**Why:** Cummings SNUG-2001, and the most expensive mistake in this family because every bit is individually correct. Bit-to-bit skew from routing, rise/fall differences and across-die process variation cannot be matched away; a destination edge landing inside that skew window captures some bits this cycle and the rest next cycle, latching a word that never existed in the source. The same breaks paired controls -- a load and an enable arriving in different cycles means nothing loads.

**Good:**

```systemverilog
// Gray-coded pointer: only one bit changes per increment, so a skewed
// capture yields either the old or the new value, never a third.
prim_fifo_async u_cdc_fifo ( ... );
```

**Bad:**

```systemverilog
for (genvar i = 0; i < 8; i++) begin : gen_sync
  prim_flop_2sync u_sync (.d_i(data_i[i]), .q_o(data_sync[i]));
end
```

**Enforced by:** review only

**Sources:** Cummings SNUG-2001 §multi-bit signals

### CDC-003 (MUST) — Multi-bit crossings use a documented pattern

A multi-bit crossing uses one of: consolidation to a single bit regenerated locally; an unsynchronised data bus held stable behind a synchronised enable; Gray coding for counters; or an asynchronous FIFO.

**Why:** Cummings SNUG-2001/2002, in his order of preference. Each pattern removes the skew problem a different way: consolidation leaves nothing multi-bit to skew; the held-stable formulation guarantees the bus is not changing while it is sampled; Gray coding guarantees at most one bit differs between consecutive values; the FIFO does the pointer crossing in Gray code and keeps the data in memory that is never crossed at all.

**Good:**

```systemverilog
// MCP: data held stable while a synchronised enable qualifies it.
assign data_stable_d = load_i ? data_i : data_stable_q;
prim_flop_2sync u_en_sync (.d_i(load_toggle_q), .q_o(load_toggle_sync));
```

**Bad:**

```systemverilog
// A free-running binary counter synchronised straight across.
```

**Enforced by:** review only

**Sources:** Cummings SNUG-2001, Cummings SNUG-2002 §async FIFO

### CDC-004 (MUST) — Signals are registered before they cross

A signal is registered in its source clock domain immediately before crossing; combinational logic does not drive a crossing directly.

**Why:** Cummings SNUG-2001. Combinational output settles through a sequence of intermediate values, and every one of them is a potential edge for the destination to capture -- the crossing sees phantom pulses that never existed as logical values. Registering also improves MTBF by cutting how often the crossed signal changes.

**Good:**

```systemverilog
always_ff @(posedge src_clk_i) begin
  req_q <= req_valid && !busy;   // Registered, then crossed
end
```

**Bad:**

```systemverilog
assign req_cross = req_valid && !busy;   // Glitches cross as real edges
```

**Enforced by:** review only

**Sources:** Cummings SNUG-2001

### CDC-005 (MUST) — Open-loop pulses are wide enough to be captured

A one-bit signal crossed open-loop through a two-flop synchroniser is held for more than 1.5 destination clock periods -- three destination edges. Narrower events use a closed-loop handshake.

**Why:** Cummings SNUG-2001. A pulse shorter than the destination period can fall entirely between two destination edges and be missed, and one sampled near an edge may be captured by the first flop but not held long enough for the second. Three edges is the width that guarantees capture regardless of phase.

**Good:**

```systemverilog
// Toggle: the level survives any number of destination periods.
assign req_toggle_d = req_i ? ~req_toggle_q : req_toggle_q;
```

**Bad:**

```systemverilog
// A single source-clock-wide pulse crossing into a slower domain.
```

**Enforced by:** review only

**Sources:** Cummings SNUG-2001

### CDC-006 (SHOULD) — Crossings are confined to dedicated modules

Only the top level of a design sees more than one clock; every clock-domain crossing lives inside a module whose purpose is that crossing.

**Why:** Cummings SNUG-2001. Confining crossings makes them findable -- the set of modules to review for CDC is a list rather than a search -- and it lets the rest of the design be verified, timed and lint-checked as single-clock logic.

**Good:**

```systemverilog
// cdc_sync.sv, cdc_fifo.sv instantiated at the top; leaves are single-clock.
```

**Bad:**

```systemverilog
// A leaf module taking both sys_clk_i and usb_clk_i.
```

**Enforced by:** review only

**Sources:** Cummings SNUG-2001 §partitioning

## GEN — Generate and parameterisation

### GEN-001 (MUST) — Every generate block is labelled

Every generate `for` body and every branch of a generate `if` carries a `lower_snake_case` label prefixed `gen_`, written as `begin : gen_name`.

**Why:** The label becomes part of the hierarchical path of everything inside it. Without one the tool invents a name like `genblk3`, so waveforms, timing reports, constraints and bug reports all address the logic by a number that shifts when an unrelated generate is added above it.

**Good:**

```systemverilog
for (genvar i = 0; i < NumPorts; i++) begin : gen_port
  prim_fifo_sync u_fifo ( ... );
end
```

**Bad:**

```systemverilog
for (genvar i = 0; i < NumPorts; i++) begin
  prim_fifo_sync u_fifo ( ... );
end
```

**Enforced by:** verible lint `generate-label` `generate-label-prefix`

**Sources:** lowRISC §Generate Constructs, Verible

### GEN-002 (MUST) — Generate constructs use the modern form

`generate`/`endgenerate` regions are not written, `genvar` is declared inline in the `for` header, and a generate body is not wrapped in an extra bare `begin` block.

**Why:** The `generate` region has been optional since Verilog-2001 and adds a scope level that changes hierarchical paths without changing behaviour. An inline `genvar` scopes the loop variable to its loop, so two loops in one module cannot collide.

**Good:**

```systemverilog
for (genvar i = 0; i < N; i++) begin : gen_stage
  ...
end
```

**Bad:**

```systemverilog
genvar i;
generate
  for (i = 0; i < N; i++) begin : gen_stage
    ...
  end
endgenerate
```

**Enforced by:** verible lint `legacy-generate-region` `legacy-genvar-declaration` `v2001-generate-begin`

**Sources:** lowRISC §Generate Constructs, Verible

### GEN-003 (MUST) — Parameter legality is asserted, not assumed

A parameter with restricted legal values carries an assertion or an elaboration-time check stating the restriction.

**Why:** A parameterised module is instantiated by people who did not read it. A power-of-two depth assumption that is violated produces wrong hardware rather than an error, and the failure appears as a functional bug in the instantiating design, far from the module that assumed it.

**Good:**

```systemverilog
`ASSERT_INIT(DepthIsPowerOfTwo_A, (Depth & (Depth - 1)) == 0)
```

**Bad:**

```systemverilog
parameter int unsigned Depth = 8;  // must be a power of two (comment only)
```

**Enforced by:** review only

**Sources:** lowRISC §Parameterized Modules

## VER — Assertions and verification

### VER-001 (SHOULD) — Assertions are written through the standard macros

SVA in RTL is written with the project's assertion macros (`` `ASSERT``, `` `ASSERT_INIT``, `` `ASSERT_KNOWN``) rather than bare `assert property`.

**Why:** The macros carry the clock and reset arguments, the severity, and the `` `ifdef`` guards that keep assertions out of synthesis. Bare assertions have to repeat all of that at every site, and the one that forgets the reset guard fires spuriously during reset in every simulation.

**Good:**

```systemverilog
`ASSERT(ReqStableUntilAck_A, req_o && !ack_i |=> req_o, clk_i, !rst_ni)
```

**Bad:**

```systemverilog
assert property (@(posedge clk_i) req_o && !ack_i |=> req_o);
```

**Enforced by:** review only

**Sources:** lowRISC §Assertions, PULP assertions.svh

### VER-002 (SHOULD) — Module outputs are checked for X

Module outputs carry an `` `ASSERT_KNOWN`` check, except outputs that may legitimately be unknown before first write, such as the read data of a FIFO or a memory.

**Why:** X propagates silently through most RTL operators and is optimistically resolved by others, so an X originating in one module is often first noticed as wrong data several modules downstream. Checking at the boundary localises it to the module that produced it.

**Good:**

```systemverilog
`ASSERT_KNOWN(ValidKnown_A, valid_o)
```

**Bad:**

```systemverilog
// No X checks; an uninitialised counter shows up as wrong data three
// modules away.
```

**Enforced by:** review only

**Sources:** lowRISC §Assertions

### VER-003 (MUST) — Lint runs clean before code is shared

`svstyle check` reports no MUST violations and `verilator --lint-only -Wall` reports no warnings before RTL is committed or handed over.

**Why:** Every check in this guide is cheap at the point of writing and expensive later: a latch found by static timing analysis, a width truncation found in a chip bring-up lab, a missing case default found by a customer. The gate exists so that none of them travels.

**Good:**

```systemverilog
$ svstyle check fifo_sync.sv && verilator --lint-only -Wall fifo_sync.sv
```

**Bad:**

```systemverilog
// Committed with 14 SHOULD findings and 2 MUSTs outstanding.
```

**Enforced by:** review only

**Sources:** house style

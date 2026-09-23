# SystemVerilog RTL rules

Generated from `rules.toml` — do not edit. Full rationale and examples:
`rules-rationale.md` (load it when a rule is questioned or a finding is unclear).

`MUST` violations fail `svstyle check`. `[fix]` marks what `svstyle fix` writes for you.

## DOC — Comments and file header

- **DOC-001** · MUST · Every `.sv` and `.svh` file begins with the copyright line, the all-rights-reserved line, and a `Description:` block that says what the file does. `[fix]`
- **DOC-002** · SHOULD · The `Description:` block says what the module does and names its non-obvious constraints; it is not the module name restated.
- **DOC-003** · MUST · Each port declaration ends with a `//` comment describing the signal. `[fix]`
- **DOC-004** · MUST · Each parameter, localparam, signal and net declaration statement ends with a `//` comment. Enumeration members are exempt. `[fix]`
- **DOC-005** · MUST · A one-line `//` comment sits on the line above every `always_ff`, `always_comb` and `always_latch` block, saying what the block computes. `[fix]`
- **DOC-006** · MUST · A one-line `//` comment sits on the line above every module instantiation, saying what the instance is for in this design. `[fix]`
- **DOC-007** · MUST · A comment on its own line describes the code that follows; a comment on a line with code describes that line. Use `//`, not `/* */`.
- **DOC-008** · MUST · Each state alternative inside an FSM case statement is preceded by a comment describing that state's function; those descriptions do not also live on the enum declaration.
- **DOC-009** · MUST · Code that deliberately departs from a rule in this guide carries a brief comment saying why, plus a lint waiver pragma where the tool supports one.
- **DOC-010** · SHOULD · A `` `endif`` far from its `` `ifdef`` carries a comment naming the condition it closes, and a named `begin` closes as `end : name`.

## STR — File structure

- **STR-001** · MUST · A source file contains exactly one module, package or interface, and the file's basename is that design unit's name.
- **STR-002** · MUST · SystemVerilog source files are named `.sv`; files intended to be `` `include``d are named `.svh`.
- **STR-003** · SHOULD · Signals, types, enums and localparams are declared close to where they are first used, grouped with the logic that drives them, rather than hoisted into a block at the top of the module.
- **STR-004** · MUST · Package dependencies form a directed acyclic graph; two packages never import each other.
- **STR-005** · SHOULD · `import pkg::*;` is used only for a package belonging to the same IP as the importing module, and the import sits in the module header rather than at file scope.

## PRT — Ports and connections

- **PRT-001** · MUST · Module ports use the Verilog-2001 combined port-and-direction style, one port per line, with the closing `);` on its own line.
- **PRT-002** · MUST · The port list opens with the clock port(s), then all reset inputs, then the remaining ports grouped by interface.
- **PRT-003** · MUST · Every instantiation connects ports by name. Positional connection and `.*` are not used in synthesizable RTL.
- **PRT-004** · MUST · Every declared port appears in every instantiation, in declaration order; unused outputs are written as explicit no-connects and unused inputs are tied off explicitly.
- **PRT-005** · MUST · Instance parameters are specified by name in the `#(...)` list. `defparam` is not used.
- **PRT-006** · SHOULD · Synthesizable, reusable modules take individual signals or packed structs as ports, not SystemVerilog interfaces.
- **PRT-007** · SHOULD · A ready/valid interface names its backpressure signal for the protocol it implements: `_ready_and_o` when neither signal may depend combinationally on the other, `_ready_then_o` when valid may depend on ready, `_yumi_o` when the accept may depend on valid. A bare `_ready_o` does not say which.

## NAM — Naming

- **NAM-001** · MUST · Modules, packages, interfaces, instances, signals, ports, variables, functions, tasks and named blocks are named in `lower_snake_case`.
- **NAM-002** · MUST · Module inputs end in `_i`, outputs in `_o`, and bidirectionals in `_io`.
- **NAM-003** · MUST · Multiple suffixes are concatenated without extra underscores, with `_n` first and `_i`/`_o`/`_io` last: `rst_ni`, `data_qi`, `valid_no`.
- **NAM-004** · MUST · A registered signal is named `<name>_q` and the value driving its input `<name>_d`; the two are declared together.
- **NAM-005** · MUST · Enumeration types are named `lower_snake_case_e`, other typedefs `lower_snake_case_t`, and every enum and struct used as a type is given a typedef name.
- **NAM-006** · SHOULD · Tunable parameters and the localparams derived from them are named in `UpperCamelCase`; values that are immutable facts rather than tuning knobs are named in `ALL_CAPS`.
- **NAM-007** · SHOULD · A boolean parameter is named for the condition being true (`EnableLogging`), not negated (`DisableLogging`).
- **NAM-008** · SHOULD · `` `define`` macros are named in `ALL_CAPS`. A globally visible macro is prefixed with its group name and a double underscore; a file-local macro is prefixed with a single underscore and `` `undef``ed after use.
- **NAM-009** · SHOULD · Signal names say what the signal is for, using whole words; signals that work together share a prefix, and a signal in a non-default clock domain is prefixed with that domain's identifier.
- **NAM-010** · MUST · No identifier reuses a Verilog or SystemVerilog keyword, including keywords added after Verilog-2005.

## FMT — Formatting and layout

- **FMT-001** · MUST · Indentation is two spaces, never tabs; lines carry no trailing whitespace; the file ends with exactly one newline; lines are at most 100 columns.
- **FMT-002** · MUST · Port declarations, formal parameters, named port connections, named parameter overrides, module-level net declarations, struct members and enum assignments are aligned into columns. Loose assignment statements and case items are not.
- **FMT-003** · MUST · Every `if`, `else`, `for`, `while` and `always` body is wrapped in `begin`/`end`, even a single statement. `begin` sits on the line of the construct that opens it and `end else begin` is written on one line.
- **FMT-004** · MUST · There are no empty statements from consecutive semicolons, and no semicolon after the `end` of a block or after a module or generate body.
- **FMT-005** · SHOULD · An expression mixing operators of different precedence carries explicit parentheses around the intended grouping.

## LNG — Language features

- **LNG-001** · MUST · Signals are declared `logic`. `wire` appears only where a net is genuinely multiply driven, which in practice means a bidirectional pad, and carries a comment saying so.
- **LNG-002** · MUST · Clocked logic is written in `always_ff` and assigns only with `<=`.
- **LNG-003** · MUST · Combinational logic is written in `always_comb` and assigns only with `=`. `always @(*)` and manual sensitivity lists are not used.
- **LNG-004** · MUST · A single `always` block uses either `=` or `<=` throughout, never both.
- **LNG-005** · MUST · No variable is assigned from more than one `always` block or continuous assignment.
- **LNG-006** · MUST · A combinational block assigns a default value to every signal it drives, immediately after the block opens and before any conditional logic.
- **LNG-007** · MUST · Every `case`, `casez` and `unique case` statement has a `default` arm, even when it is empty or only raises an error.
- **LNG-008** · MUST · Sized literals state a width that matches their context; a literal is never wider than its declared size, and `'0`/`'1`/`'x` are used for context-width fills.
- **LNG-009** · MUST · `casex` does not appear in synthesizable RTL. `casez` is used only where the truth table genuinely has don't-care bits, with don't-cares written as `?` and never as `z`.
- **LNG-010** · MUST · Every function and task declares an explicit `automatic` lifetime, an explicit return type, and an explicit direction and type on each argument.
- **LNG-011** · MUST · `parameter` appears only in a module's formal parameter list; constants inside a module body are `localparam`. Both declare an explicit type.
- **LNG-012** · MUST · Packed dimensions are declared `[N-1:0]` and unpacked dimensions `[0:N-1]` or `[N]`; no dimension may evaluate to a negative size.
- **LNG-013** · MUST · Synthesizable RTL contains no system tasks or functions that exist only for simulation, and no `#` delays.
- **LNG-014** · SHOULD · Each `.sv` file begins with `` `default_nettype none`` after the header and ends with `` `resetall``. `[fix]`

## SYN — Synthesis and portability

- **SYN-001** · MUST · No case statement carries a `full_case` or `parallel_case` synthesis directive.
- **SYN-002** · SHOULD · Use `unique case` with a `default` as the normal form. `priority case` states intentional overlap; plain `case` is used where neither claim holds.
- **SYN-003** · SHOULD · Intentional priority is written as an `if`/`else if` chain; a `case` statement is reserved for logic whose arms are genuinely mutually exclusive.
- **SYN-004** · MUST · A module does not instantiate itself, directly or through a cycle.

## RST — Reset and clocking

- **RST-001** · MUST · Flip-flops are reset asynchronously by an active-low reset named `rst_ni`, written as `always_ff @(posedge clk_i or negedge rst_ni)` with the reset test as the first `if` in the block.
- **RST-002** · MUST · An asynchronous reset entering a clock domain is asserted asynchronously but de-asserted synchronously, through a two-flop reset synchroniser in that domain.
- **RST-003** · MUST · In a multi-clock design, every clock domain instantiates its own reset synchroniser and its own reset distribution tree.
- **RST-004** · SHOULD · Reset the flops that must hold a known value at startup -- state machines, counters, valid bits, configuration -- and leave datapath registers unreset.
- **RST-005** · MUST · A signal used as an asynchronous reset is not also used as ordinary data, and a clock is not gated with combinational logic; clock gating uses a dedicated integrated clock-gating cell.

## FSM — State machines

- **FSM-001** · MUST · FSM state is held in a variable of a `typedef enum` type, named `state_q` with next state `state_d`. State encodings are never `` `define`` macros.
- **FSM-002** · SHOULD · An FSM is written as a sequential `always_ff` holding the state register plus a combinational `always_comb` computing next state and outputs; a third `always_ff` is added when outputs must be registered.
- **FSM-003** · SHOULD · An FSM does not drive combinational (Mealy) outputs across a module boundary; such outputs are registered first, or the output logic moves into the consuming module.
- **FSM-004** · SHOULD · A module contains at most one state machine.

## CDC — Clock domain crossing

- **CDC-001** · MUST · Every one-bit signal crossing an asynchronous clock boundary passes through two flip-flops clocked by the destination clock, with no logic between them.
- **CDC-002** · MUST · A multi-bit value is not crossed by putting a two-flop synchroniser on each bit.
- **CDC-003** · MUST · A multi-bit crossing uses one of: consolidation to a single bit regenerated locally; an unsynchronised data bus held stable behind a synchronised enable; Gray coding for counters; or an asynchronous FIFO.
- **CDC-004** · MUST · A signal is registered in its source clock domain immediately before crossing; combinational logic does not drive a crossing directly.
- **CDC-005** · MUST · A one-bit signal crossed open-loop through a two-flop synchroniser is held for more than 1.5 destination clock periods -- three destination edges. Narrower events use a closed-loop handshake.
- **CDC-006** · SHOULD · Only the top level of a design sees more than one clock; every clock-domain crossing lives inside a module whose purpose is that crossing.

## GEN — Generate and parameterisation

- **GEN-001** · MUST · Every generate `for` body and every branch of a generate `if` carries a `lower_snake_case` label prefixed `gen_`, written as `begin : gen_name`.
- **GEN-002** · MUST · `generate`/`endgenerate` regions are not written, `genvar` is declared inline in the `for` header, and a generate body is not wrapped in an extra bare `begin` block.
- **GEN-003** · MUST · A parameter with restricted legal values carries an assertion or an elaboration-time check stating the restriction.

## VER — Assertions and verification

- **VER-001** · SHOULD · SVA in RTL is written with the project's assertion macros (`` `ASSERT``, `` `ASSERT_INIT``, `` `ASSERT_KNOWN``) rather than bare `assert property`.
- **VER-002** · SHOULD · Module outputs carry an `` `ASSERT_KNOWN`` check, except outputs that may legitimately be unknown before first write, such as the read data of a FIFO or a memory.
- **VER-003** · MUST · `svstyle check` reports no MUST violations and `verilator --lint-only -Wall` reports no warnings before RTL is committed or handed over.

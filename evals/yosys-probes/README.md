# Yosys 0.66 SystemVerilog support (synthesizable subset)

- Yosys 0.66 (git sha1 7f8fdfd8, the v0.66 tag 86f2ddeb plus an empty merge), built-in frontend `read_verilog -sv`.
- Date: 2026-10-06.
- Probes: 148 minimal files plus one control file, one construct per file, in this
  directory. Rerun them with `sh evals/yosys-probes/run.sh`, or
  `YOSYS=/path/to/yosys sh evals/yosys-probes/run.sh`.
  - Each `NAME.sv` has top module `NAME`. Its first line is `// expect: OK|WARN|ERROR|WRONG`.
  - `run.sh` runs `read_verilog -sv NAME.sv; synth -flatten -top NAME`.
  - If the file has an `ok` output (the construct compared with a plain Verilog-2005 reference), `run.sh` also runs `sat -prove ok 1` on the synthesised netlist. WRONG means the proof fails.
  - `run.sh` prints PASS when Yosys still behaves as recorded, and FAIL when the behaviour changed.
  - It also lints every file with Verilator 5.052 (all 149 lint clean), so each construct is legal SV.
  - `zz_control_wrong.sv` must report WRONG. That proves the sat check catches a bad netlist.
- Evidence key:
  - **P** = confirmed by probe on 0.66.
  - **S** = source only.
  - Short links:
    - `P.y` = https://github.com/YosysHQ/yosys/blob/v0.66/frontends/verilog/verilog_parser.y
    - `L.l` = …/verilog_lexer.l
    - `simplify` = …/frontends/ast/simplify.cc
    - `genrtlil` = …/frontends/ast/genrtlil.cc
    - `doc` = https://github.com/YosysHQ/yosys/blob/v0.66/docs/source/using_yosys/verilog.rst ("Supported features from SystemVerilog", lines 332-395)
- sv-tests: the dashboard at https://chipsalliance.github.io/sv-tests-results (gh-pages `report.csv`, logs under `logs/Yosys/`) ran Yosys 1801abf. That is 7 commits before v0.66, with no frontend change except a nosync fix in genrtlil.
  - The runner is https://github.com/chipsalliance/sv-tests/blob/master/tools/runners/Yosys.py.
  - Many of its failures come from testbench constructs (`final`, `string`, `$display %f`), not RTL. Test names are cited below where they match.
- **Probes win over docs.** Where they disagree, the row says so. In particular, the doc's "type casts are currently not supported" and "array assignment of unpacked arrays is not supported" are stale. A source note that a typedef'd 2-D array in a generate "works" is wrong: it parses but mis-synthesizes.
- **Out of scope:** classes, constraints/randomization, coverage, SVA properties/sequences, DPI, program blocks, dynamic/associative arrays and queues. These are verification-only. Yosys rejects most of them, and sv-tests ch8, 9, 15, 16, 18, 19, 21, 24 and 35 cover them.

## Does not parse / errors

Read failures show as `EXT-YOSYS-read` in svstyle.

| Construct | Minimal example | What Yosys does | Portable rewrite | Evidence |
|---|---|---|---|---|
| `return` | `return x + 3;` | `syntax error, unexpected TOK_ID` (or `TOK_CONSTVAL`). There is no `return` token, also inside packages. | Assign the function name: `f = x + 3;`. For an early return, use if/else. | P `return_in_func`, `return_early_in_func`, `func_in_pkg_with_return`. S `L.l` has no keyword. sv-tests jump_return, function_return. issue #2684 |
| `break` / `continue` | `if (a[i]) begin y = i; break; end` | `Can't resolve task name '\break'` (parsed as a task call) | Add a `found` flag to the condition: `if (a[i] && !found)` | P `break_loop`, `continue_loop`, rewrite `found_flag_loop`. sv-tests jump_break, jump_continue |
| `while` in `always` | `while (i < 8) ...` | `While loops are only allowed in constant functions!` | `for` with a constant bound. `while` is fine in a constant function used for a parameter. | P `while_in_always`, `const_func_while_param` (OK). S `simplify` L2552 |
| `do ... while` | `do begin ... end while (i < 8);` | `syntax error, unexpected TOK_BEGIN` | `for` | P `do_while` |
| `foreach` | `foreach (a[i]) y[i] = ~a[i];` | `syntax error, unexpected TOK_ID, expecting ';'` | `for (int i = 0; i < $bits(a); i++)` | P `foreach_loop`. sv-tests foreach_loop_synth |
| `repeat (n)` with a non-constant n | `repeat (n) y = y + 1;` | `Repeat loops outside must have constant repeat counts!` | `for` up to the maximum, guarded by `if (i < n)`. Constant `repeat (3)` works. | P `repeat_nonconst`, `repeat_loop` (OK) |
| `inside` operator | `a inside {1, 2, [8:9]}` | `syntax error, unexpected TOK_ID` | `(a == 1) \|\| (a == 2) \|\| (a >= 8 && a <= 9)` | P `inside_op`. sv-tests set_member |
| `case (x) inside` | `case (a) inside 1, 2: ...` | `Cast operation must be applied on sized constants, e.g. <ID>'d0, while 1 is not a sized constant.` | Plain `case` with listed items, or `casez` for wildcards | P `case_inside`, `case_inside_plain`. sv-tests case_set |
| `==?` / `!=?` | `a ==? 4'b1?0?` | `syntax error, unexpected '?'` | Mask compare: `(a & 4'b1010) == 4'b1000`, or `casez` | P `wildcard_eq`. sv-tests binary_op_wild_eq |
| Streaming operators | `{<<{a}}` | `syntax error, unexpected OP_SHL` | A `for` loop that reverses the bits | P `streaming_op` |
| Select on a concatenation | `{a, b}[5]` | `syntax error, unexpected '['` | Assign the concatenation to a signal first | P `concat_bit_select` |
| `let` | `let mx(x, z) = ...;` | `syntax error, unexpected '='` | A function | P `let_decl` |
| `-` right before a sized cast | `-W'(a)` | `Static cast with zero or negative size!` (read as `(-W)'(a)`) | `-(W'(a))` | P `neg_sized_cast`, `neg_sized_cast_paren` (OK) |
| `void'(...)` cast | `void'(f(a));` | `syntax error, unexpected TOK_VOID` | Drop the call, or assign to an unused variable | P `void_cast` |
| `$bits` of a type | `$bits(t_t)` | `syntax error, unexpected ')', expecting OP_CAST` | `$bits(var)` of a variable of that type | P `bits_of_type`, `bits_of_var` (OK). sv-tests bits_type_function |
| `parameter type` | `#(parameter type T = logic [7:0])` | `syntax error, unexpected TOK_ID, expecting ')' or ',' or '='` | A width parameter | P `param_type`. S `P.y` L1783 param_type has no `type` |
| `string` type | `parameter string Mode = "fast"` | `syntax error, unexpected TOK_ID ...` | An untyped parameter: `parameter Mode = "fast"` (probe OK) | P `string_param`, `string_param_untyped` |
| `int'()` of a real | `localparam int N = int'(Ratio * 4.0);` | `Parameter \N does not evaluate to constant value!` | `$rtoi(Ratio * 4.0)`. `real` parameters themselves work. | P `real_param`, `real_param_rtoi` (OK) |
| `import pkg::*` (or `import pkg::name`) in a module body | `import pk::*;` | `syntax error, unexpected TOK_IMPORT` | `pk::Name` at each use | P `pkg_import_body`, `pkg_import_named` |
| `import` in a module header | `module m import pk::*; (...)` | `syntax error, unexpected TOK_IMPORT, expecting '#' or '(' or ';'` | `pk::Name` | P `pkg_import_header`. sv-tests core veer-el2 |
| `import` at file scope, using package types or functions | `import pk::*; module m; pair_t s; ...` | Types give `syntax error, unexpected ';', expecting '(' or '['`. A function call aborts with `Assert 'wire != nullptr' failed in frontends/ast/simplify.cc:4313`. | `pk::Name`. File-scope import of localparams and enum constants does work (probe OK), but don't rely on it. | P `pkg_import_unit_type`, `pkg_import_unit`, `pkg_import_unit_param` (OK). issue #5947 |
| `import` inside a package | `package b; import a::*; ...` | Not in the grammar | `a::Name` | S `P.y` L828. issue #5533 |
| Struct assignment pattern, named | `s = '{hi: a, lo: b};` | `syntax error, unexpected ':'` | `s = {a, b};` (field order), or assign the fields | P `struct_pattern_named`, `struct_concat_assign`, `struct_field_assign` (OK) |
| Struct assignment pattern, positional | `s = '{a, b};` | `Assignment pattern is only supported for whole unpacked array assignments.` | `{a, b}` | P `struct_pattern_positional`. S `genrtlil` L1824 |
| `'{default: ...}` | `r_q <= '{default: '0};` | `syntax error, unexpected TOK_DEFAULT` | `'0`, or a `for` loop for an unpacked array | P `struct_pattern_default`, `array_pattern_default`. issue #6120 |
| Constant table as an unpacked localparam | `localparam logic [7:0] T [4] = '{...};` | `syntax error, unexpected '[', expecting ',' or ';' or '='` | Flat vector sliced by index: `localparam logic [31:0] T = {...}; T[i*8 +: 8]`, or a function with a `case` | P `lp_unpacked_array`, `lp_flat_vector_slice`, `lp_case_function` (OK) |
| Unpacked array parameter | `#(parameter logic [7:0] P [2] = ...)` | `syntax error, unexpected '[' ...` | A flat vector parameter | P `lp_unpacked_param_array` |
| Explicit multi-dimensional packed type on a localparam, parameter or function | `localparam logic [3:0][7:0] T = ...;`, `function logic [1:0][7:0] f(logic [1:0][7:0] x)` | `syntax error, unexpected '[', expecting TOK_ID` (with `{...}` or `'{...}` alike) | Flat vector plus `+:` slices. Not a typedef: see the mis-synthesis table. | P `lp_packed2d_concat`, `lp_packed2d_pattern`, `lp_packed2d_const_index`, `param_packed2d`, `func_packed2d_return` |
| Multi-dimensional packed variable declared in a generate or `begin` block | `begin : blk logic [3:0][7:0] v; ...` | `Failed to detect width of signal access '\blk.v'!` (also when it is read only there) | Declare at module level, indexed by stage: `logic [N-1:0][3:0][7:0] v;`. 1-D vectors in blocks are fine. | P `packed2d_in_begin`, `packed2d_in_genblk`, `packed1d_in_*` (OK). S `genrtlil` L1110 |
| Variable-index field of a packed array of structs | `s[i].lo` | `Index in generate block prefix syntax is not constant!` | See the struct-array row in the mis-synthesis table | P `struct_array_field` |
| Unpacked array port | `input logic [7:0] a [2]` | `syntax error, unexpected '[' ...` | Packed array port `input logic [1:0][7:0] a` (probe OK) | P `unpacked_port`, `packed_array_port` |
| Unpacked struct | `typedef struct { ... } t;` | `Only PACKED supported at this time` | `struct packed` | P `unpacked_struct` |
| `automatic` (or static) variable with an initializer in a procedural block | `automatic logic [7:0] t = a;` | `Invalid nesting of always blocks and/or initializations.` | `logic [7:0] t;` at the top of the block, then `t = a;` | P `automatic_init_always`, `static_init_in_always`, `var_decl_init_always` (OK). S `simplify` L1416 |
| Enum methods | `s.next()`, `s.name()`, `s.num()` | `Can't resolve function name '\s.next'.` | Arithmetic plus cast `st_e'(s + 1)`. Constants for `num`. No `.name()`. | P `enum_next`, `enum_name`, `enum_first_last_num` |
| Array reduction methods | `s.sum()` | `Can't resolve function name '\s.sum'.` | A `for` loop | P `array_reduction_method` |
| `endfunction : f` / `endtask : t` labels | `endfunction : f` | `syntax error, unexpected ':'` | Drop the label. `end : blk`, `endmodule : m` and `endpackage : p` work. | P `end_label_function`, `end_label_task`, `end_label_block`, `end_label_package` (OK) |
| `endinterface : label` | `endinterface : bus_if` | `syntax error, unexpected ':'` | Drop the label | P `endinterface_label`. sv-tests ch25 |
| Source-only extras | `->` / `<->` in expressions, `macromodule`, positional interface connections, `unique0`/`priority` on an `else if` branch | Rejected | Plain logic, `module`, named connections | S sv-tests ch11/ch23. `doc`. `P.y` L2959 |

## Parses, but warns or mis-synthesizes

WRONG rows are silent: no error, no warning (except where noted), and a netlist that differs from simulation.

| Construct | Minimal example | What Yosys does | Portable rewrite | Evidence |
|---|---|---|---|---|
| **Typedef with two or more packed dimensions, indexed** | `typedef logic [3:0][7:0] tbl_t; tbl_t v; y = v[i];` | **Silently wrong.** `v[i]` becomes a 1-bit select of the flat vector, `y = {7'b0, v[i]}`. Same for a `localparam tbl_t T` and for the typedef used inside a generate block. Copying into an inline-typed variable (`logic [3:0][7:0] u = T;`) and indexing that is correct. | Write the dimensions inline at module level (`logic [3:0][7:0] v;`), or use a flat vector plus `+:` | P `typedef_2d_var_index`, `lp_packed2d_typedef`, `typedef_2d_in_genblk` (WRONG), `packed2d_module` (OK) |
| **Packed array of packed structs** | `pair_t [1:0] s; assign s = a; e = s[i];` | **Silently wrong.** The outer dimension is dropped: `s` is 8 bits, `$bits(s)` = 8, and `s[i]` is a bit select. `s[1].lo` gives `Warning: Identifier '\s[1].lo' is implicitly declared` and an undriven output. A packed array of enums or of a 1-D logic typedef is correct. | `pair_t e; logic [1:0][$bits(e)-1:0] s; e = s[i];` then use `e.lo` | P `struct_array_var_whole`, `struct_array_field_const` (WRONG), `struct_array_flat_rewrite`, `enum_packed_array`, `typedef_1d_packed_array` (OK). `doc` "arrays of packed structs/unions are currently not supported". issue #2677 |
| `unique` / `priority` case with no `default`, or `unique if` with no `else`, after a default assignment | `y = 0; unique case (a) 0: y = 1; 1: y = 2; endcase` | Mapped to `full_case`, so the preceding `y = 0` is dropped for uncovered values. y is a don't-care there, while simulation keeps 0. This is the classic Cummings full_case mismatch. | Give the case a `default:` item (or an `else`), or use `unique0`, which is correct | P `unique_case_nodefault`, `priority_case_nodefault`, `unique_if_noelse` (WRONG), `unique_case_default_item`, `unique0_case` (OK). `doc` (unique/priority via full_case/parallel_case) |
| Module-level variable with a non-constant initializer | `logic [7:0] t = a;` | Yosys makes a continuous assign. Verilator and Icarus run it once at time 0 (y stays 0/x). | `logic [7:0] t; assign t = a;`, or a net: `wire [7:0] t = a;` (probe OK, LRM-consistent) | P `module_var_init` (Yosys OK; mismatch checked by a Verilator/Icarus sim), `net_decl_assign` |
| Unpacked arrays of flops or of combinational signals, including `arr = '{a, b}` | `logic [7:0] r_q [4];` | `Warning: Replacing memory \r_q with list of registers` (`EXT-YOSYS-warning`). The logic is correct. | Packed array: `logic [3:0][7:0] r_q;`, reset with `'0`. Keep unpacked arrays for real memories (RAM inference, probe OK without a warning). | P `unpacked_flops`, `unpacked_comb`, `multidim_unpacked`, `unpacked_array_pattern` (WARN), `packed_flops`, `ram_infer` (OK) |
| Interface instance with member access | `bus_if b (); assign b.data = a;` | `Warning: Identifier '\b.data' is implicitly declared.`, but the netlist is correct (sat proves it). Positional interface connections are unsupported. | Plain ports, or accept the warning | P `interface_modport`, `interface_param` (WARN, sat OK). `doc` "partially supported" |
| Implicit real-to-int parameter conversion | `localparam int N = Ratio * 4.0;` | `Warning: converting real value 1.000000e+01 to binary 10.` | `$rtoi(...)` | P `real_param_implicit`, `real_param_rtoi` (OK) |

## Works

Each of these probes synthesises with no warning, and its `ok` check holds where it has one.

| Construct | Example | Evidence |
|---|---|---|
| `always_ff`, `always_comb`, `always_latch` | | P `always_ff_comb`, `always_latch_blk`, `mixed_blocking_counter` |
| `localparam` in the parameter port list | `#(parameter int I = 4, localparam int W = I + 12)` | P `localparam_in_port_list` |
| `int unsigned`, `bit` parameters, overrides | | P `param_int_unsigned`, `param_override` |
| Untyped string parameter, `real` parameter with `$rtoi` | | P `string_param_untyped`, `real_param_rtoi` |
| Package items as `pk::Name`: types, enums, structs, functions, localparams, in ports too | | P `pkg_scoped`, `pkg_type_in_port`, `enum_in_pkg_case` |
| `typedef` in a module and at file (`$unit`) scope | | P `typedef_in_module`, `typedef_unit_scope` |
| Packed structs: field access, part-select, nested, signed, as a localparam, 2-D field, flop with `'0` reset | | P `struct_packed`, `struct_field_partsel`, `struct_nested`, `struct_signed_packed`, `struct_param`, `struct_2d_field`, `struct_ff_reset` |
| Packed unions | `union packed { logic [7:0] raw; pair_t p; }` | P `union_packed` |
| Enums: FSM, enum cast `st_e'(x)`, packed array of enums | | P `enum_basic`, `type_cast_enum`, `enum_packed_array` |
| Multi-dimensional packed array at module level (also as a port) | `logic [3:0][7:0] v; v[i]` | P `packed2d_module`, `packed_array_port` |
| 1-D vectors declared in named/unnamed `begin` or generate blocks | | P `packed1d_in_begin`, `packed1d_in_genblk`, `var_decl_init_always` |
| `automatic` variable without an initializer | `automatic logic [7:0] k; k = 5;` | P `const_var` |
| `int`, `byte`, `shortint`, `bit`, `int unsigned` variables | | P `int_types` |
| Casts `W'(x)`, `signed'(x)`, `$signed`, `$unsigned`, `>>>` | | P `sized_cast`, `signed_cast`, `signed_unsigned`, `arith_shift` |
| `'0` / `'1` fills, `{N{a}}`, `**` in constants | | P `fill_literals`, `replication_param`, `power_op` |
| `++`, `+=`, `-=`, `<<=` | | P `incr_ops` |
| `for (int i = 0; ...; i++)`, constant `repeat` | | P `for_int_header`, `repeat_loop` |
| `unique`/`priority` case and if with full coverage, `unique0`, `casez` | | P `unique_case`, `priority_case`, `unique_if`, `priority_if`, `unique0_case`, `casez_basic` |
| Functions: assign to the name, nested calls, `function void` with an output argument, tasks in `always_comb`, a constant function with `while` for a parameter, a function with `case` as a table | | P `func_name_assign`, `func_nested_call`, `func_output_arg`, `func_void_task`, `const_func_while_param`, `lp_case_function` |
| `$clog2`, `$bits(var)`, `$size`, `$high`, `$low`, `$countones`, `$onehot`, `$onehot0` | | P `sysfuncs_size`, `sysfuncs_onehot`, `bits_of_var`. S `simplify` L3875-4150 |
| Generate: `for`/`if`/`case` without the `generate` keyword, with the keyword, hierarchical `gen_s[1].t`, `$error` in a generate `if` | | P `generate_no_keyword`, `generate_keyword`, `generate_case`, `generate_hier_ref`, `gen_error_elab` |
| `end : blk`, `endmodule : m`, `endpackage : p` labels | | P `end_label_block`, `end_label_package` |
| `.*` and `.name` connections, default input port values | | P `port_conn_star`, `port_conn_name`, `default_port_value` |
| Net declaration assignment | `wire [7:0] t = a ^ 8'hff;` | P `net_decl_assign` |
| Immediate `assert` in `always_comb`, and concurrent asserts inside `` `ifndef SYNTHESIS`` (Yosys defines `SYNTHESIS`) | | P `immediate_assert`, `ifndef_synthesis_assert` |
| RAM inference from an unpacked array | | P `ram_infer` |

## Differences from the current synth-yosys.md

**Confirmed as they stand:** `return`, `import pkg::*` in the header or body, `inside`, `foreach`, `break`/`continue`, `while`, an `automatic` var with an initializer, streaming, `parameter type`, `-W'(x)`, a 2-D packed array in a generate or `begin` block, the "Replacing memory" warning, and the whole "Works" list.

**Rows to correct:**
- Constant table row.
  - Keep both forms as errors.
  - But do not suggest a typedef to get around `localparam logic [3:0][7:0]`: a typedef'd 2-D type parses and mis-synthesizes (bit select).
  - The rewrites (flat vector plus `+:`, or a function with `case`) are confirmed.
- Struct assignment pattern row.
  - The positional form fails with a different message ("only supported for whole unpacked array assignments").
  - Add `'{default: ...}` (syntax error).
  - Note that `'{a, b}` on an unpacked array parses but warns.
- `import` row.
  - File-scope `import` is also broken for types (syntax error) and functions (assertion crash).
  - The rewrite stays `pkg::Name`.
- `while` row: also `do ... while` and non-constant `repeat`.
- 2-D packed array in a block row: "declare it at module level" stays right. Add "do not use a typedef there (mis-synthesizes)".
- "Parses, but warns": add the interface member warning and the `real` conversion warning.

**Rows to add (errors):**
- `case inside`
- `==?`
- `{a,b}[i]`
- `let`
- `void'()`
- `$bits(type)`
- `parameter string`
- `int'(real)`
- unpacked array parameter
- explicit 2-D packed type on a parameter or function
- unpacked array ports
- unpacked structs
- enum methods
- array methods
- `endfunction :` / `endtask :` / `endinterface :` labels

**Rows to add (silent mis-synthesis, highest priority):**
- A typedef with 2+ packed dimensions, indexed.
- Packed arrays of packed structs.
- `unique`/`priority` case without `default` (or `unique if` without `else`) after a default assignment.
- A module-level variable with a non-constant initializer.

**Rows to add (works):** `typedef` in a module, packed unions, `unique0`/`priority`, `++`/`+=`, `for (int i ...)`, `always_latch`, `.*`/`.name`, default port values, `'0`/`'1`, `$size`/`$bits(var)`/`$countones`, generate without the keyword, and `end : blk` labels.

**Rows to drop:** none. Narrow "`$signed`, sized casts" in Works to say that `int'()` of a real fails.

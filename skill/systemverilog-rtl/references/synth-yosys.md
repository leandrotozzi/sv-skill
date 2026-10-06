# Writing for Yosys

Read this when the project synthesises with Yosys: `synth = "yosys"` in the
nearest `.svstyle.toml`, or no `synth` key at all (Yosys is the default).
With `synth = "yosys"`, `svstyle check` runs Yosys on every call.

Yosys reads a subset of SystemVerilog. Everything below is legal
SystemVerilog that Verilator and commercial tools accept. Write the
right-hand form from the start: an error costs a round of check-edit-check,
and the first table costs a wrong chip. Verified on Yosys 0.66 by one probe
per row (`evals/yosys-probes/` in the svstyle repository).

## Synthesises wrong, with no error

`svstyle check` passes and simulation is right, but the netlist differs.
Never write these.

| Instead of | Write |
|---|---|
| a `typedef` with two or more packed dimensions, indexed: `typedef logic [3:0][7:0] tbl_t; tbl_t v; v[i]` (`v[i]` becomes one bit; also as a `localparam` or in a generate block) | the dimensions inline on a module-level signal, `logic [3:0][7:0] v;`, or a flat vector sliced with `+:` |
| a packed array of packed structs, `pair_t [1:0] s;` (the outer dimension is dropped; `s[1].lo` is undriven) | `pair_t e; logic [1:0][$bits(e)-1:0] s;`, then `e = s[i];` and read `e`'s fields |
| `unique`/`priority case` with no `default`, or `unique if` with no `else`, after a default assignment (read as `full_case`: the default is dropped) | a `default:` arm (or `else`), as SYN-002 asks anyway; or `unique0` |
| a module-level variable with a non-constant initializer, `logic [7:0] t = a;` (Yosys makes it continuous, simulators run it once) | `logic [7:0] t; assign t = a;` |

## Does not parse

`EXT-YOSYS-read`: synthesis was not checked.

| Instead of | Write |
|---|---|
| `return x;` in a function | assign the function name: `f = x;` |
| `break` / `continue` | a `found` flag in the loop condition or the body |
| `while`, `do ... while`, `repeat (n)` with a non-constant `n`, `foreach` | `for` with a constant bound, `if (i < n)` inside |
| `a inside {1, 2}`, `case (a) inside`, `a ==? 4'b1?0?` | `(a == 1) \|\| (a == 2)`, a plain `case`, `casez`, or a mask compare `(a & M) == V` |
| streaming `{<<{a}}` | a `for` loop that reverses the bits |
| a select on a concatenation, `{a, b}[5]` | assign the concatenation to a signal first |
| `let`, `void'(f(x))` | a function; drop the call |
| a unary minus right before a sized cast, `-W'(x)` | `-(W'(x))` |
| `$bits(type_t)` | `$bits(sig)` of a signal of that type |
| `parameter type T`, `parameter string S`, `int'(real_expr)` | a width parameter; an untyped `parameter S = "x"`; `$rtoi(...)` |
| `import pkg::*;` or `import pkg::name;` anywhere: module header, body, file scope, inside a package | `pkg::Name` at each use; types, enums, structs and functions all work that way |
| a constant table as an array, `localparam logic [7:0] T [4]`, or with an explicit 2-D packed type, `localparam logic [3:0][7:0] T` (same for a `parameter` or a function's type) | a flat vector sliced by index, `localparam logic [31:0] T = {...}; ... T[i*8 +: 8]`, or a function with a `case`; not a typedef (see above) |
| a multi-dimensional packed array (`logic [3:0][7:0] x;`) declared inside a generate or `begin` block, even one read only there ("Failed to detect width of signal access") | declare it at module level, indexed by stage if each iteration needs its own: `logic [N-1:0][3:0][7:0] x;`; 1-D vectors inside blocks are fine |
| an unpacked array port or parameter, `input logic [7:0] a [2]` | a packed array, `input logic [1:0][7:0] a` |
| an unpacked struct, `typedef struct { ... }` | `struct packed` |
| a struct assignment pattern, `s = '{f: a, g: b}` or `'{a, b}`, or `'{default: '0}` | a concatenation in field order, `s = {a, b};`, or field by field; `'0` |
| `automatic logic t = a;` (any initializer) inside an `always` block | `logic t;` at the top of the block, then `t = a;` |
| enum methods (`s.next()`, `s.name()`), array methods (`a.sum()`) | `st_e'(s + 1)`; a `for` loop |
| `endfunction : f`, `endtask : t`, `endinterface : i` | drop the label (`end : blk`, `endmodule : m` and `endpackage : p` are fine) |

## Parses, but warns

`EXT-YOSYS-warning`. The netlist is right, but the warning stays in the report.

- **Unpacked arrays of flops or of combinational signals** (`logic [7:0] r_q [4]`)
  make Yosys report `Replacing memory ... with list of registers`. For
  pipelines, tap delay lines and partial sums, use a packed array:
  `logic [3:0][7:0] r_q;`, reset with `r_q <= '0`. Keep unpacked arrays for
  real memories, where Yosys should infer a RAM.
- **Interface member access** (`b.data`) warns "implicitly declared". Use
  plain ports, as PRT-006 asks.
- **A real expression assigned to an `int` parameter** warns about the
  conversion: write `$rtoi(...)`.

## Works, no need to avoid

- `always_ff`, `always_comb`, `always_latch`; `unique case`, `unique0`,
  `priority`, `casez` (with a `default`).
- A `localparam` in the parameter port list, used for port widths:
  `#(parameter int IntBits = 4, parameter int FracBits = 12, localparam int Width = IntBits + FracBits)`.
- Packed structs (nested, signed, as a `localparam`, reset with `'0`),
  packed unions, enums and enum casts `st_e'(x)`, packed arrays of enums.
- Package items as `pkg::Name`, in ports too; `typedef` inside a module.
- Multi-dimensional packed arrays declared inline at module level, ports
  included: `logic [3:0][7:0] v; ... v[i]`.
- Functions that assign their name, nested calls, `output` arguments, tasks
  in `always_comb`; a constant function with `while` for a parameter.
- `for (int i = 0; ...; i++)`, constant `repeat`, `++`, `+=`, `<<=`.
- `generate` `for`, `if` and `case`, with or without the keyword;
  `$error` in a generate `if` (GEN-003); `gen_s[1].t` references.
- `$clog2`, `$bits(sig)`, `$size`, `$countones`, `$onehot`, `$onehot0`;
  sized casts `W'(x)`, `signed'(x)`, `$signed`, `$unsigned`; `'0`/`'1`.
- `.*` and `.name` connections, default input port values, `wire t = a;`.
- Declarations of 1-D vectors at the top of a named or unnamed `begin`
  block or in a generate block.
- Assertions inside `` `ifndef SYNTHESIS``, as `assets/assert_macros.svh` does.

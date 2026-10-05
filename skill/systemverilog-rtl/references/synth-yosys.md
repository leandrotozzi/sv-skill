# Writing for Yosys

Read this when the project synthesises with Yosys: `synth = "yosys"` in the
nearest `.svstyle.toml`, or no `synth` key at all (Yosys is the default).
With `synth = "yosys"`, `svstyle check` runs Yosys on every call.

Yosys reads a subset of SystemVerilog. Everything below is legal
SystemVerilog that Verilator and commercial tools accept, but Yosys stops
with a syntax error (`EXT-YOSYS-read`: synthesis was not checked) or warns.
Write the right-hand form from the start; each miss costs a round of
check-edit-check. Verified on Yosys 0.66.

## Does not parse

| Instead of | Write |
|---|---|
| `return x;` in a function | assign the function name: `f = x;` |
| a constant table as an array: `localparam logic [7:0] T [4] = '{...}` or `localparam logic [3:0][7:0] T = ...` | a flat vector sliced by index, `localparam logic [31:0] T = {...}; ... T[i*8 +: 8]`, or a function with a `case` |
| `import pkg::*;` in the module header or body | `pkg::Name` at each use; package types, enums, structs and functions all work that way |
| `a inside {1, 2}` | `(a == 1) \|\| (a == 2)`, or a `case` |
| `foreach (a[i])` | `for (int i = 0; i < $bits(a); i++)` |
| `break` / `continue` | a `found` flag in the loop condition or the body |
| `while` outside a constant function | `for` with a constant bound |
| `automatic logic t = a;` inside an `always` block | `logic t;` at the top of the block, then `t = a;` |
| streaming `{<<{a}}` | a `for` loop that reverses the bits |
| `parameter type T = ...` | a width parameter |

## Parses, but warns

- **Unpacked arrays of flops or of combinational signals** (`logic [7:0] r_q [4]`)
  make Yosys report `Replacing memory ... with list of registers`
  (`EXT-YOSYS-warning`). For pipelines, tap delay lines and partial sums,
  use a packed array: `logic [3:0][7:0] r_q;`, reset with `r_q <= '0`.
  Keep unpacked arrays for real memories, where Yosys should infer a RAM.

## Works, no need to avoid

- A `localparam` in the parameter port list, used for port widths:
  `#(parameter int IntBits = 4, parameter int FracBits = 12, localparam int Width = IntBits + FracBits)`.
- Packed structs, enums and functions from a package, as `pkg::Name`.
- `unique case`, `casez`, `generate` `for` and `if`, `$error` in a generate
  `if` (GEN-003), `$clog2`, sized casts `W'(x)`, `$signed`.
- Declarations at the top of a named or unnamed `begin` block.
- Assertions inside `` `ifndef SYNTHESIS``, as `assets/assert_macros.svh` does.

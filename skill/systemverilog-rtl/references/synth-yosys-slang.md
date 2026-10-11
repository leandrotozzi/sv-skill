# Writing for Yosys with yosys-slang

Read this instead of `synth-yosys.md` when the nearest `.svstyle.toml` has
`synth = "yosys-slang"`: the project's Yosys has the slang plugin (the OSS
CAD Suite ships it; Homebrew's Yosys does not), and `svstyle check` reads
with `read_slang` on every call.

slang reads nearly all synthesizable SystemVerilog. Of the 149 one-construct
probes behind `synth-yosys.md`, 46 that Yosys's own frontend rejects and 6
it synthesises wrong are correct here (56 of them proved equal to a plain
Verilog reference with `sat`). Write normal SystemVerilog: `return`,
`break`, `foreach`, `inside`, `import pkg::*`, assignment patterns,
`parameter type`, unpacked arrays and structs, typedef'd multi-dimensional
arrays and arrays of structs all work. What is left, verified on Yosys
0.69+212 with the plugin from OSS CAD Suite 2026-10-07:

## Synthesises wrong, with no error

| Instead of | Write |
|---|---|
| `unique`/`priority case` with no `default`, after a default assignment (read as `full_case`: the default is dropped) | a `default:` arm, as SYN-002 asks anyway; or `unique0` |

## Does not parse

`EXT-YOSYS-read`: synthesis was not checked.

| Instead of | Write |
|---|---|
| `do ... while`, and `repeat (n)` even with a constant `n` | `for` with a constant bound (`while` itself works) |
| enum methods (`s.next()`, `s.name()`), array methods (`a.sum()`) | `st_e'(s + 1)`; a `for` loop |
| a module-level variable with a non-constant initializer, `logic [7:0] t = a;` | `logic [7:0] t; assign t = a;` |
| an instance of a module not passed to the same `check` (slang has no black boxes) | pass every file of the design in one call |

## Parses, but warns

- `logic [7:0] t = 8'd1;` inside a procedural block warns that a static
  variable initialised there needs an explicit `static`: write
  `automatic logic [7:0] t = 8'd1;` (works), or `logic [7:0] t;` then
  `t = 8'd1;`.

# svstyle: usage, output and who owns each rule

## Getting the tool

If `svstyle` is not on PATH, install it from PyPI, or run it without
installing:

```sh
uv tool install svstyle      # or: pipx install svstyle
uvx svstyle check rtl/       # one-off run, nothing installed
```

Working on svstyle itself: `uv tool install --editable <checkout>` puts the
checkout's version on PATH.

External tools are used when present: `verible-verilog-format` and
`verible-verilog-lint` (pinned to `v0.0-3946-g851d3ff4`; another version
warns that alignment may drift) and `verilator`. `check` skips a missing tool
with a warning; `fix` refuses without Verible, because its output would not
be idempotent.

## Configuration: `.svstyle.toml`

`svstyle` reads the nearest `.svstyle.toml` found walking up from each file,
so one file at the repository root covers the whole tree:

```toml
company = "ACME Corp"      # the copyright holder in every file header
select  = ["DOC", "LNG"]   # optional: only these rule IDs/prefixes
ignore  = ["DOC-005"]      # optional: drop these
include = ["rtl/inc"]      # optional: `include dirs, relative to this file
exclude = ["vendor/*"]     # optional: skip these when walking a directory or filelist
synth   = "yosys"          # optional: the synthesis tool; "yosys" or "yosys-slang" runs Yosys on every check
```

With it, `fix` writes new headers with that company and replaces the
`<Company>` placeholder in existing ones. `synth = "yosys"` makes plain
`check` behave like `check --synth`; `synth = "yosys-slang"` does the same
but reads with the yosys-slang plugin (`read_slang`, which the OSS CAD Suite
ships), so the skill loads `synth-yosys-slang.md` in place of
`synth-yosys.md`; any other value names a tool svstyle does not run, and
tells the skill to load neither. `--select`/`--ignore` on the
command line replace the file's selection. Without it the placeholder stays and
DOC-001 reports it as a SHOULD. An unknown key or a wrong type is an error
(exit 2), so a typo never silently disables the setting.

## Commands

```sh
svstyle check [FILES|DIRS] [-f LIST] [-F LIST] [-I DIR]... [--json] [--no-external]
              [--synth] [--select IDS] [--ignore IDS] [--baseline FILE [--write-baseline]]
svstyle fix   [FILES|DIRS] [-f LIST] [-F LIST] [-I DIR]... [--json] [--diff]
svstyle rules [--id ID] [--unmapped]
```

- `--select` / `--ignore` take comma-separated IDs or prefixes, ruff-style:
  `--select DOC,PRT-003 --ignore DOC-005`.
- `-I DIR` adds an `` `include`` search directory (repeatable; a missing one is
  an error); a file's own directory is always searched. Verilator gets the
  same directories.
- `exclude` globs match the path relative to the `.svstyle.toml`, fnmatch-style
  (`*` crosses directories, so `vendor/*` is the whole tree). They drop files
  found by walking a directory or reading a filelist; a file named on the
  command line is always checked, as in ruff.
- `--no-external` runs only svstyle's own checks (fast; no Verible/Verilator).
- `--synth` also runs Yosys (`read_verilog -sv; hierarchy; proc; check`):
  combinational loops (SYN-005), conflicting drivers. Yosys reads less
  SystemVerilog than the other tools; a file it cannot read is reported as
  `EXT-YOSYS-read` (MUST): synthesis was not checked, so `check` fails until
  the code is in the subset Yosys reads (`synth-yosys.md`). With
  `synth = "yosys-slang"` the read is `plugin -i slang; read_slang`, which
  reads far more, but has no black boxes: a module instantiated and not
  passed is an `EXT-YOSYS-read` too. A Yosys without the plugin fails the
  same way.
- A directory stands for every `*.sv` below it; name `.v` files explicitly.
- `--baseline FILE` reports only findings not recorded in FILE, so existing
  code can adopt the style without fixing everything first: run once with
  `--write-baseline` (exits 0), commit FILE, and CI fails only on new
  findings. A finding is keyed by file, rule and the text of its line, so
  edits elsewhere do not resurface it; changing the line does.
- `-f LIST` / `-F LIST` read a Verilator/VCS filelist: source paths,
  `+incdir+DIR`, nested `-f`/`-F`, `$VAR`s. `-f` paths are relative to the
  working directory, `-F` paths to the list. Other options are skipped.
- `fix --diff` prints the change instead of writing it, and exits 1 when
  any file would change, so it can gate CI.
- `rules --id PRT-003` prints one rule in full; `--unmapped` lists the rules
  that need human judgement.

`fix` never rebuilds the file. It runs Verible, inserts what is missing
(header, `` `default_nettype none`` / `` `resetall``, `// TODO: describe`
comments, `` `endif  // NAME`` labels), and modernises legacy code where the
syntax tree proves the meaning is unchanged:

| Legacy | Becomes | Left alone when |
|---|---|---|
| `reg` | `logic` | never |
| `wire` | `logic` | an `inout` port, or an initialiser (`wire x = a;` is an assign) |
| `always @(*)` / `always @*` | `always_comb` | the body has a delay or event control |
| `always @(posedge ...)` | `always_ff` | the body has a blocking `=` or a delay |
| a lone statement under `if`/`else`/loop/`always` | `begin ... end` around it | it is an `else if` |
| `generate` / `endgenerate` | removed | never |
| `function` / `task` | `... automatic ...` | inside a class |

Nothing inside a macro or reached by an `` `ifdef`` split is rewritten. A
`wire` stays a `wire` when it is resolved -- two `assign`s, one driving `z`, or
connected to an `inout` of a module in any file passed with it -- and a
clocked `always` stays when an `initial` also writes its variables. A `.v`
file stays Verilog-2001: it gets no `logic`, `always_comb` or `always_ff`
(the findings say to rename it to `.sv` first, which is the migration step).

A file that already opens with a licence header (a comment block naming a
copyright, licence or SPDX identifier) keeps it; `fix` adds only a
`Description:` block at its end instead of a second header on top. It
then runs Verible again and verifies that every token change is one of the
above; if not, nothing is written (exit 4). `always @(a or b)` is reported
(LNG-003), not rewritten: `always_comb` would add the signals the list forgot,
which changes what simulation does.

## Output

Text: one line per finding, then a summary.

```
rtl/fifo.sv:14:1: DOC-003 `rst_ni` has no trailing // comment [fix available]
2 findings (MUST 1, SHOULD 1)
```

`--json`:

```json
{
  "ok": false, "exit_code": 1, "kind": "violations",
  "diagnostics": [{"path": "rtl/fifo.sv", "line": 14, "col": 1, "rule": "DOC-003",
                   "severity": "MUST", "message": "...", "fixable": true}],
  "summary": {"MUST": 1, "SHOULD": 0, "MAY": 0}
}
```

`fix --json` adds `files_changed`, and its diagnostics are what remains for
the author after the fix.

## Exit codes

| Code | `kind` | Meaning | What to do |
|---|---|---|---|
| 0 | clean | no MUST findings (SHOULD allowed) | done |
| 1 | violations | at least one MUST finding | fix them, rerun |
| 2 | error | unreadable file, or a required tool missing | read stderr |
| 3 | refused | the file does not parse | fix the syntax error named in `error`; a missing `` `include`` needs `-I DIR` |
| 4 | bug | svstyle broke its own invariant; nothing written | report it with the input file |

## Who enforces what

| Owner | Rules | Notes |
|---|---|---|
| `svstyle` | DOC-001..006, PRT-001..003, PRT-005 (positional parameters), NAM-003, NAM-010, STR-002, STR-005, LNG-001, LNG-014, SYN-001, RST-001, FMT-001 (comment-only lines) | header, comments, ANSI ports, port order, named connections and parameters, suffix order, import scope, `logic`, `default_nettype`, no synthesis directives, async active-low reset, `.sv` vs `.svh`, keywords as names |
| Verible format | FMT-002 | reported as "file needs formatting"; `svstyle fix` resolves it |
| Verible lint | naming, `always_comb`/`always_ff` usage, `begin`/`end`, file names, literals, ... | tool rule name maps to the house ID |
| Verilator `-Wall` | LNG-004..006, LNG-009, LNG-015..017, PRT-004, RST-005 | latches, multi-driven, mixed assignments, `casex`, widths, undriven/unused signals, missing pins; also backs up STR-001, PRT-005, LNG-003, LNG-007, LNG-013, LNG-014, SYN-002 |
| review | 29 rules | `svstyle rules --unmapped`; walk them yourself |

Tool findings with no house rule pass through as `EXT-VL-<rule>` (Verible)
or `EXT-VLTR-<CODE>` (Verilator) at SHOULD. The common ones:

- `EXT-VLTR-MODMISSING`: a submodule's file was not on the command line.
  Pass all the design's files together; when checking one file on purpose,
  `--ignore EXT-VLTR-MODMISSING` silences it. For the same reason, with
  `--synth`, Yosys's "used but has no driver" (LNG-016) drops to SHOULD when
  a module the files instantiate is not among them.
- `EXT-VLTR-UNUSEDPARAM` is not reported for package constants: their users
  live in other files, so "unused" says nothing when a package is checked.
- `EXT-VLTR-ERROR` (MUST): the design did not elaborate -- an undeclared
  name, a port that does not exist. Fix it first; the rest of the report is
  incomplete until it is gone.

An output left open as `.q_o()` is PRT-004's explicit no-connect and is not
reported; a port missing from the instance is (PRT-004).

FMT-002 without `[fix available]` means Verible cannot format the file at
all (its layout does not converge); lay that region out by hand.

NAM-004 checks that every flop is named `_q` (indexed memory writes such as
`mem_q[addr] <= wdata_i` excepted). An output port registered in place
(`valid_o <= ...`) keeps its `_o`, and a `_q` that is a flop in one generate
branch may be tied off with `assign` in the other. It does not require a
`_d` on the right: `data_q <= data_i`, `rdata_q <= mem_q[addr_i]`, pipeline stages and
synchroniser chains are fine as written. Name a `_d` only where
combinational logic really computes the next value; never add one just to
satisfy a tool.

## Waivers (DOC-009)

`svstyle` waives any finding -- its own, Verible's or Verilator's -- with one
comment that names the rule and says why. On its own line it covers the next
line; trailing a line it covers that line. Without a reason it is ignored.

```systemverilog
// svstyle: waive RST-001 DSP blocks need a synchronous reset
always_ff @(posedge clk_i) begin
    ...
wire pad_io;  // svstyle: waive LNG-001 bidirectional pad
```

The tools' own pragmas also work, and are what a reader outside this flow
recognises:

```systemverilog
module phy_if #(
    // Name fixed by the PHY vendor's integration guide.
    // verilog_lint: waive parameter-name-style
    parameter int unsigned PHY_WIDTH = 10  // PHY data width
) (
    ...
);
    // verilator lint_off UNUSEDSIGNAL
    logic [7:0] spare_q;  // Reserved for the next revision
    // verilator lint_on UNUSEDSIGNAL
```

# svstyle: usage, output and who owns each rule

## Getting the tool

`svstyle` lives in the repository this skill comes from: two directories
above the skill's real (non-symlinked) path. If `svstyle` is not on PATH:

```sh
uv tool install --editable <repo>     # puts `svstyle` on PATH, tracks the repo
uvx --from <repo> svstyle --help      # or run it once without installing
```

External tools are used when present: `verible-verilog-format` and
`verible-verilog-lint` (pinned to `v0.0-3946-g851d3ff4`; another version
warns that alignment may drift) and `verilator`. `check` skips a missing tool
with a warning; `fix` refuses without Verible, because its output would not
be idempotent.

## Commands

```sh
svstyle check FILES [--json] [--no-external] [--select IDS] [--ignore IDS]
svstyle fix   FILES [--json] [--diff]
svstyle rules [--id ID] [--unmapped]
```

- `--select` / `--ignore` take comma-separated IDs or prefixes, ruff-style:
  `--select DOC,PRT-003 --ignore DOC-005`.
- `--no-external` runs only svstyle's own checks (fast; no Verible/Verilator).
- `fix --diff` prints the change instead of writing it.
- `rules --id PRT-003` prints one rule in full; `--unmapped` lists the rules
  that need human judgement.

`fix` never rebuilds the file. It runs Verible, inserts what is missing
(header, `` `default_nettype none`` / `` `resetall``, `// TODO: describe`
comments), runs Verible again, and then verifies that no token other than
those insertions changed. If that check fails nothing is written.

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
| 3 | refused | the file does not parse | fix the syntax error named in `error` first |
| 4 | bug | svstyle broke its own invariant; nothing written | report it with the input file |

## Who enforces what

| Owner | Rules | Notes |
|---|---|---|
| `svstyle` | DOC-001..006, PRT-001, PRT-003, LNG-014 | header, comments, ANSI ports, named connections, `default_nettype` |
| Verible format | FMT-002 | reported as "file needs formatting"; `svstyle fix` resolves it |
| Verible lint | naming, `always_comb`/`always_ff` usage, `begin`/`end`, file names, literals, ... | tool rule name maps to the house ID |
| Verilator `-Wall` | LNG-004..006, RST-005 | latches, multi-driven signals, mixed assignments |
| review | 38 rules | `svstyle rules --unmapped`; walk them yourself |

Tool findings with no house rule pass through as `EXT-VL-<rule>` (Verible)
or `EXT-VLTR-<CODE>` (Verilator) at SHOULD. The common ones:

- `EXT-VLTR-MODMISSING`: a submodule's file was not on the command line.
  Pass all the design's files together.
- `EXT-VLTR-DECLFILENAME`: file and design-unit names differ (STR-001).
- `EXT-VLTR-PINCONNECTEMPTY`: an output connected as `.q_o()`. Fine when
  deliberate (PRT-004); otherwise connect it.

## Waivers (DOC-009)

A deliberate departure carries a comment saying why, and the tool's pragma:

```systemverilog
// Bus width is fixed by the external PHY, not by this module.
// verilog_lint: waive parameter-name-style
localparam int unsigned PHY_WIDTH = 10;  // PHY data width

/* verilator lint_off UNUSED */
logic [7:0] spare_q;  // Reserved for the next revision
/* verilator lint_on UNUSED */
```

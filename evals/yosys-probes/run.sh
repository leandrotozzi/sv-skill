#!/bin/sh
# Rerun every Yosys SystemVerilog probe in this directory.
# Each probe NAME.sv has top module NAME and a first line `// expect: X`, X one of
#   OK    parses, synthesises with no warning, and (if it has an `ok` output)
#         `sat -prove ok 1` holds on the synthesised netlist
#   WARN  synthesises but Yosys prints a warning
#   ERROR read_verilog or synth stops with an error
#   WRONG synthesises silently but `ok` (construct vs plain-Verilog reference) can be 0
# Prints: PASS|FAIL  name  expected  actual  [verilator]  first message
# PASS = Yosys still behaves as recorded; FAIL = behaviour changed (update the notes).
# The verilator column: lint = Verilator 5 accepts the file (the construct is legal SV).
cd "$(dirname "$0")" || exit 1
YOSYS=${YOSYS:-yosys}
"$YOSYS" -V
npass=0; nfail=0
for f in *.sv; do
  top=${f%.sv}
  exp=$(sed -n '1s/^\/\/ expect: *\([A-Z]*\).*/\1/p' "$f")
  out=$("$YOSYS" -q -p "read_verilog -sv $f; synth -flatten -top $top" 2>&1)
  if printf '%s\n' "$out" | grep -q 'ERROR'; then
    act=ERROR; msg=$(printf '%s\n' "$out" | grep -m1 'ERROR' | cut -c1-150)
  elif printf '%s\n' "$out" | grep -qi 'warning'; then
    act=WARN; msg=$(printf '%s\n' "$out" | grep -m1 -i 'warning' | cut -c1-150)
  else
    act=OK; msg=""
  fi
  if [ "$act" != ERROR ]; then
    if grep -q 'output.*\bok\b' "$f"; then
      sat=$("$YOSYS" -q -p "read_verilog -sv $f; synth -flatten -top $top; sat -prove ok 1 -verify -set-init-zero" 2>&1)
      if printf '%s\n' "$sat" | grep -q 'ERROR'; then act=WRONG; msg="sat: ok can be 0; $msg"; fi
    fi
  fi
  if verilator --lint-only -Wno-fatal -Wno-lint -Wno-style -Wno-MULTITOP --top-module "$top" "$f" >/dev/null 2>&1; then
    vl=lint; else vl=nolint; fi
  if [ "$act" = "$exp" ]; then r=PASS; npass=$((npass+1)); else r=FAIL; nfail=$((nfail+1)); fi
  printf '%-4s  %-28s %-5s %-5s %-6s %s\n' "$r" "$top" "$exp" "$act" "$vl" "$msg"
done
echo "$npass PASS, $nfail FAIL"

"""Grade one skill-creator iteration: every assertion is checked by a tool, not by eye.

    uv run python evals/grade.py skill/systemverilog-rtl-workspace/iteration-N

Moves each `<config>/outputs` to `<config>/run-1/outputs` (the layout the
skill-creator aggregator expects) and writes `run-1/grading.json`.
"""

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


def run(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)


def grade(out: Path) -> list[dict]:
    # Packages first: Yosys and Verilator need them before their users.
    # Testbenches some runs leave behind are not RTL; grade the design only.
    rtl = [p.name for p in out.glob("*.sv") if not re.search(r"(^tb_|_tb\.sv$)", p.name)]
    files = sorted(rtl, key=lambda n: (not n.endswith("_pkg.sv"), n))
    exp = []

    def check(text: str, passed: bool, evidence: str) -> None:
        exp.append({"text": text, "passed": bool(passed), "evidence": evidence[:600]})

    check("Produces at least one .sv file", files, f"files: {files}")
    if not files:
        return exp

    res = run(["svstyle", "check", "--json", *files], out)
    try:
        doc = json.loads(res.stdout)
    except json.JSONDecodeError:
        doc = {"exit_code": res.returncode, "diagnostics": [], "summary": {}, "error": res.stderr}
    diags = doc.get("diagnostics", [])
    must = [d for d in diags if d["severity"] == "MUST"]

    def rules(*ids: str) -> list[str]:
        return [f"{d['path']}:{d['line']} {d['rule']}" for d in must if d["rule"].startswith(ids)]

    check(
        "svstyle check exits 0 (no MUST violation, file parses)",
        doc.get("exit_code") == 0,
        f"exit {doc.get('exit_code')}, summary {doc.get('summary')}, MUST: "
        + "; ".join(f"{d['rule']}@{d['path']}:{d['line']}" for d in must[:12])
        + (f" error: {doc['error']}" if doc.get("error") else ""),
    )
    hdr = rules("DOC-001")
    check("Every file has the standard copyright header (DOC-001)", not hdr, "; ".join(hdr) or "ok")
    cmt = rules("DOC-003", "DOC-004", "DOC-005", "DOC-006")
    check("Every port, declaration, block and instance is commented (DOC-003..006)", not cmt,
          f"{len(cmt)} missing: " + "; ".join(cmt[:10]) if cmt else "ok")  # fmt: skip
    names = rules("NAM-")
    check("Naming rules hold: _i/_o suffixes, _q/_d, CamelCase params (NAM-*)", not names,
          "; ".join(names[:10]) or "ok")  # fmt: skip
    fmt = rules("FMT-")
    check("Formatted to house layout: 4-space indent, alignment (FMT-*)", not fmt,
          "; ".join(fmt) or "ok")  # fmt: skip

    todo = [f"{f}:{i}" for f in files for i, ln in enumerate((out / f).read_text().splitlines(), 1)
            if "TODO: describe" in ln]  # fmt: skip
    check("No `// TODO: describe` placeholder left", not todo, ", ".join(todo) or "none")

    vl = run(["verilator", "--lint-only", "-Wall", "-Wno-MULTITOP", *files], out)
    warns = [ln for ln in vl.stderr.splitlines() if re.match(r"%(Warning|Error)", ln)]
    check("verilator --lint-only -Wall is clean", not warns, "\n".join(warns[:8]) or "clean")

    ys = run(["yosys", "-q", "-p", f"read_verilog -sv {' '.join(files)}; synth -auto-top"], out)
    check("Yosys reads and synthesizes the design", ys.returncode == 0,
          (ys.stderr or ys.stdout).strip()[-400:] or "ok")  # fmt: skip
    return exp


def main(iteration: Path) -> None:
    for cfg in sorted(iteration.glob("eval-*/*")):
        if not cfg.is_dir():
            continue
        if (cfg / "outputs").is_dir():
            (cfg / "run-1").mkdir(exist_ok=True)
            shutil.move(cfg / "outputs", cfg / "run-1" / "outputs")
        for run_dir in sorted(cfg.glob("run-*")):
            exp = grade(run_dir / "outputs")
            passed = sum(e["passed"] for e in exp)
            (run_dir / "grading.json").write_text(json.dumps({
                "expectations": exp,
                "summary": {"passed": passed, "failed": len(exp) - passed, "total": len(exp),
                            "pass_rate": round(passed / len(exp), 2)},
            }, indent=2))  # fmt: skip
            print(f"{run_dir.relative_to(iteration)}: {passed}/{len(exp)}")


if __name__ == "__main__":
    main(Path(sys.argv[1]))

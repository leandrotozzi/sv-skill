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

EVALS = Path(__file__).parent
CHECKS = {
    e["id"]: e.get("checks", [])
    for f in ("evals.json", "classics.json")
    for e in json.loads((EVALS / f).read_text())["evals"]
}


def run(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)


def grade(out: Path, checks: list[dict] = ()) -> list[dict]:
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

    res = run(["svstyle", "check", "--json", "--synth", *files], out)
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

    # PINCONNECTEMPTY: `.q_o()` is PRT-004's explicit no-connect, as in svstyle.
    vl = run(
        ["verilator", "--lint-only", "-Wall", "-Wno-MULTITOP", "-Wno-PINCONNECTEMPTY", *files], out
    )
    warns = [ln for ln in vl.stderr.splitlines() if re.match(r"%(Warning|Error)", ln)]
    check("verilator --lint-only -Wall is clean", not warns, "\n".join(warns[:8]) or "clean")

    ys = run(["yosys", "-q", "-p", f"read_verilog -sv {' '.join(files)}; synth -auto-top"], out)
    check("Yosys reads and synthesizes the design", ys.returncode == 0,
          (ys.stderr or ys.stdout).strip()[-400:] or "ok")  # fmt: skip

    # Per-eval checks from evals.json: what this prompt specifically asked for.
    rtl_text = "\n".join((out / f).read_text() for f in files)
    for c in checks:
        if "present" in c:
            m = re.search(c["present"], rtl_text)
            check(c["text"], m, f"found {m.group(0)!r}" if m else f"no match for {c['present']}")
        elif "yosys_memory" in c:
            read = f"read_verilog -sv {' '.join(files)}"
            script = f"{read}; hierarchy -auto-top; proc; memory -nomap; stat"
            st = run(["yosys", "-p", script], out)  # not -q: that silences `stat`
            # A memory cell in the `stat` table. mem2reg on a small side array (a
            # skid or prefetch buffer) is fine; a storage array in flops leaves none.
            cells = re.findall(r"^\s+\d*\s*\$mem(?:_v2)?\b.*$", st.stdout, re.MULTILINE)
            check(c["text"], cells, "; ".join(cells) or "no $mem cell (array turned into flops)")
        elif "equiv_tb" in c:
            check(c["text"], *equiv(out, files, c["equiv_tb"]))
    return exp


def equiv(out: Path, files: list[str], spec: dict) -> tuple[bool, str]:
    """Simulate the output with a self-checking testbench, against the original
    (renamed <module>_ref) when the spec names one."""
    work = out.parent / "equiv"
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir()
    sources = [*(str(out / f) for f in files)]
    if "ref" in spec:
        ref = (EVALS / spec["ref"]).read_text()
        (work / "ref.v").write_text(
            re.sub(rf"\bmodule\s+{spec['module']}\b", f"module {spec['module']}_ref", ref)
        )
        sources.insert(0, str(work / "ref.v"))
    tb = EVALS / spec["tb"]
    sources.append(str(tb))
    flags = [
        "--binary",
        "--timing",
        "-Wno-lint",
        "-Wno-style",
        "-Mdir",
        str(work / "obj"),
        f"-I{out}",
    ]
    build = run(["verilator", *flags, "--top-module", tb.stem, *sources], work)
    if build.returncode:
        return False, "testbench does not build: " + build.stderr.strip()[-400:]
    sim = run([str(work / "obj" / f"V{tb.stem}")], work)
    return "EQUIV PASS" in sim.stdout, sim.stdout.strip()[-300:]


def main(iteration: Path) -> None:
    for cfg in sorted(iteration.glob("eval-*/*")):
        if not cfg.is_dir():
            continue
        if (cfg / "outputs").is_dir():
            (cfg / "run-1").mkdir(exist_ok=True)
            shutil.move(cfg / "outputs", cfg / "run-1" / "outputs")
        meta = cfg.parent / "eval_metadata.json"
        checks = CHECKS.get(json.loads(meta.read_text())["eval_id"], []) if meta.exists() else []
        for run_dir in sorted(cfg.glob("run-*")):
            exp = grade(run_dir / "outputs", checks)
            passed = sum(e["passed"] for e in exp)
            (run_dir / "grading.json").write_text(json.dumps({
                "expectations": exp,
                "summary": {"passed": passed, "failed": len(exp) - passed, "total": len(exp),
                            "pass_rate": round(passed / len(exp), 2)},
            }, indent=2))  # fmt: skip
            print(f"{run_dir.relative_to(iteration)}: {passed}/{len(exp)}")


if __name__ == "__main__":
    main(Path(sys.argv[1]).resolve())  # the equivalence build runs in another directory

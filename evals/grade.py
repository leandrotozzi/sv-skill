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

from svstyle.checks import load_config, waivers

EVALS = Path(__file__).parent
CHECKS = {
    e["id"]: e.get("checks", [])
    for f in ("evals.json", "classics.json")
    for e in json.loads((EVALS / f).read_text())["evals"]
}


def run(cmd: list[str], cwd: Path, timeout: float = 600) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)


REPORT_CHECKS = ("report", "report_absent", "unchanged")
NEGATED_RE = re.compile(r"(?i)\b(not|no|n/a)\b|n't\b")


def grade_review(out: Path, checks: list[dict]) -> list[dict]:
    """A review eval: the prompt asks for `review.md` and no edits."""
    exp = []
    report = out / "review.md"
    text = report.read_text() if report.exists() else ""
    exp.append({"text": "Writes review.md", "passed": bool(text), "evidence": str(report)})
    for c in checks:
        if "report" in c:
            m = re.search(c["report"], text)
            ok, ev = m, f"found {m.group(0)!r}" if m else f"no match for {c['report']}"
        elif "report_absent" in c:
            # A finding asserts; "CDC-001 does not apply" is the report being thorough.
            hits = [ln for ln in text.splitlines()
                    if re.search(c["report_absent"], ln) and not NEGATED_RE.search(ln)]  # fmt: skip
            ok, ev = not hits, f"found {hits[0]!r}" if hits else "absent"
        else:  # unchanged: an edited copy among the outputs is an edit nobody asked for
            # At its name (skill-creator runs) or at its repo path (run.py copies it there).
            edited = [
                f for f in c["unchanged"] for p in (out / Path(f).name, out / f)
                if p.exists() and p.read_text() != (EVALS.parent / f).read_text()
            ]  # fmt: skip
            ok, ev = not edited, f"edited: {edited}" if edited else "untouched"
        exp.append({"text": c["text"], "passed": bool(ok), "evidence": ev[:600]})
    return exp


def design(out: Path) -> tuple[list[str], list[str], str]:
    """The output's RTL files, its include flags and the Yosys command that reads them."""
    # Packages first: Yosys and Verilator need them before their users.
    # Testbenches some runs leave behind are not RTL; grade the design only.
    # Anywhere below the outputs (some runs use rtl/), but not a build directory.
    rtl = [
        p.relative_to(out).as_posix() for p in out.rglob("*.sv")
        if not re.search(r"(^tb_|_tb\.sv$)", p.name)
        and not {"build", "obj_dir"} & set(p.relative_to(out).parts)
    ]  # fmt: skip
    files = sorted(rtl, key=lambda n: (not n.endswith("_pkg.sv"), Path(n).name))
    incs = [f"-I{out / d}" for d in sorted({str(Path(f).parent) for f in files})]
    quoted = " ".join(f'"{f}"' for f in files)  # a path with a space
    read = f"read_verilog -sv {' '.join(incs)} {quoted}"
    if load_config(out / "x.sv").get("synth") == "yosys-slang":  # the project's frontend
        read = f"plugin -i slang; read_slang {' '.join(incs)} {' '.join(files)}"
    return files, incs, read


def metrics(out: Path) -> dict:
    """Logic depth and size of the flattened design, numbers rather than a check: there
    is no right depth, only one to compare (docs/research/timing-metric.md). `ltp`
    counts cells on the longest flop-to-flop path, unit delay; `stat -tech cmos`
    estimates transistors. Empty when the design does not synthesise."""
    files, _, read = design(out)
    if not files:
        return {}
    # Not -q: that silences `ltp` and `stat`. Flattened, or `ltp` sees one module.
    ys = run(["yosys", "-p", f"{read}; synth -flatten -auto-top; ltp -noff; stat -tech cmos"], out)
    depth = re.findall(r"Longest topological path in \S+ \(length=(\d+)\)", ys.stdout)
    tr = re.search(r"Estimated number of transistors:\s+(\d+)", ys.stdout)
    if ys.returncode or not depth or not tr:
        return {}
    return {"depth": int(depth[-1]), "transistors": int(tr.group(1))}


def grade(out: Path, checks: list[dict] = ()) -> list[dict]:
    if any(k in c for c in checks for k in REPORT_CHECKS):
        return grade_review(out, checks)
    files, incs, read = design(out)
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
        ["verilator", "--lint-only", "-Wall", "-Wno-MULTITOP", "-Wno-PINCONNECTEMPTY",
         *incs, *files], out,
    )  # fmt: skip
    # A line the author waived for svstyle (DOC-009) is waived here too.
    waived = {f"{f}:{n}:" for f in files for n in waivers((out / f).read_text())}
    warns = [
        ln for ln in vl.stderr.splitlines()
        if re.match(r"%(Warning|Error)", ln) and not ln.startswith("%Error: Exiting due to")
        and not any(w in ln for w in waived)
    ]  # fmt: skip
    check("verilator --lint-only -Wall is clean", not warns, "\n".join(warns[:8]) or "clean")

    ys = run(["yosys", "-q", "-p", f"{read}; synth -auto-top"], out)
    check("Yosys reads and synthesizes the design", ys.returncode == 0,
          (ys.stderr or ys.stdout).strip()[-400:] or "ok")  # fmt: skip
    if ys.returncode == 0:
        # Clean synthesis: no warning (e.g. an unpacked array of flops) and no latch.
        warns = sorted({ln[:160] for ln in (ys.stdout + ys.stderr).splitlines()
                        if ln.startswith("Warning:")})  # fmt: skip
        latch = run(
            ["yosys", "-q", "-p", f"{read}; synth -auto-top; select -assert-none t:$_DLATCH*"], out
        )
        bad = warns + ([] if latch.returncode == 0 else ["a latch was inferred"])
        check("Yosys synthesis has no warning and no latch", not bad, "\n".join(bad[:6]) or "clean")

    # Per-eval checks from evals.json: what this prompt specifically asked for.
    rtl_text = "\n".join((out / f).read_text() for f in files)
    for c in checks:
        if "present" in c:
            m = re.search(c["present"], rtl_text)
            check(c["text"], m, f"found {m.group(0)!r}" if m else f"no match for {c['present']}")
        elif "yosys_memory" in c:
            script = f"{read}; hierarchy -auto-top; proc; memory -nomap; stat"
            st = run(["yosys", "-p", script], out)  # not -q: that silences `stat`
            # A memory cell in the `stat` table. mem2reg on a small side array (a
            # skid or prefetch buffer) is fine; a storage array in flops leaves none.
            cells = re.findall(r"^\s+\d*\s*\$mem(?:_v2)?\b.*$", st.stdout, re.MULTILINE)
            check(c["text"], cells, "; ".join(cells) or "no $mem cell (array turned into flops)")
        elif "equiv_tb" in c:
            check(c["text"], *equiv(out, files, c["equiv_tb"]))
        elif "tb_catches" in c:
            check(c["text"], *tb_catches(out, files, c["tb_catches"]))
    return exp


def tb_catches(out: Path, files: list[str], module: str) -> tuple[bool, str]:
    """Run the output's own testbench against the reference, which it must pass,
    and against each planted bug in files/classics/bugs/, which it must fail."""
    tbs = sorted(p for p in out.rglob("*.sv") if re.search(r"(^tb_|_tb\.sv$)", p.name))
    if not tbs:  # SKILL.md lets a small block skip simulation
        return True, "no testbench: simulation skipped"
    tb = tbs[0]
    work = out.parent / "tb_catches"
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir()
    # The output's packages and submodules stay; only the top module is swapped.
    rest = [str(out / f) for f in files if Path(f).name != f"{module}.sv"]
    incs = [f"-I{out / d}" for d in sorted({str(Path(f).parent) for f in files})]
    bugs = sorted((EVALS / "files/classics/bugs").glob(f"{module}_*.sv"))

    def passes(dut: Path, tag: str) -> bool:
        flags = ["--binary", "--timing", "--assert", "-Wno-fatal", "-Wno-lint", "-Wno-style",
                 "--x-assign", "unique", "--x-initial", "unique", *incs,
                 f"-I{tb.parent}"]  # fmt: skip
        obj = work / tag
        build = run(["verilator", *flags, "-Mdir", str(obj), "--top-module", tb.stem,
                     *rest, str(dut), str(tb)], work, timeout=300)  # fmt: skip
        if build.returncode:
            raise RuntimeError(build.stderr.strip()[-300:])
        try:
            sim = run([str(obj / f"V{tb.stem}"), "+verilator+rand+reset+2"], work, timeout=60)
        except subprocess.TimeoutExpired:
            return False  # a hang is a failure: a bug can stall a handshake forever
        return sim.returncode == 0 and re.search(r"\bPASS\b", sim.stdout) is not None

    try:
        if not passes(EVALS / f"files/classics/{module}.sv", "ref"):
            return False, f"{tb.name} fails on the correct reference"
        missed = [b.name for b in bugs if passes(b, b.stem)]
    except RuntimeError as e:
        return False, f"{tb.name} does not build: {e}"
    caught = len(bugs) - len(missed)
    note = f", missed {missed}" if missed else ""
    return not missed, f"{tb.name} catches {caught}/{len(bugs)}{note}"


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
        "-Wno-fatal",  # lint is its own check; a warning such as UNOPTFLAT is no wrong behaviour
        "-Mdir",
        str(work / "obj"),
        *(f"-I{out / d}" for d in sorted({str(Path(f).parent) for f in files})),
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
                "metrics": metrics(run_dir / "outputs"),
                "summary": {"passed": passed, "failed": len(exp) - passed, "total": len(exp),
                            "pass_rate": round(passed / len(exp), 2)},
            }, indent=2))  # fmt: skip
            print(f"{run_dir.relative_to(iteration)}: {passed}/{len(exp)}")


if __name__ == "__main__":
    main(Path(sys.argv[1]).resolve())  # the equivalence build runs in another directory

"""VerilogEval v2 spec-to-RTL, with and without the skill, through `claude -p`.

    git clone https://github.com/NVlabs/verilog-eval DIR
    git -C DIR checkout c498220d0a52248f8e3fdffe279075215bde2da6
    uv run python evals/verilogeval.py grade-refs --dataset DIR      # harness self-check
    uv run python evals/verilogeval.py run --dataset DIR --subset 30 --model claude-opus-5-5

Each run starts in an empty directory with `--setting-sources project`, so no
user skill, hook or CLAUDE.md leaks in; the with-skill run adds this repo with
`--plugin-dir`. Both get the dataset prompt verbatim plus where to write the
file. Graded per run: the dataset's testbench under iverilog (the benchmark's
pass@1), `svstyle check` clean, and `verilator --lint-only -Wall` clean.

iverilog 13 rejects the testbenches' `$dumpvars` (a forward reference v12
allowed); those lines only write a waveform, so they are dropped. Prob099 is
broken upstream (its testbench wants ports its reference lacks) and skipped.
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
BROKEN = {"Prob099_m2014_q6c"}
IVERILOG = ["iverilog", "-Wall", "-Winfloop", "-Wno-timescale", "-g2012", "-s", "tb"]
ASK = "\n\nWrite the module in SystemVerilog to TopModule.sv in the current directory."
TOOLS = [
    "Read", "Write", "Edit", "Glob", "Grep", "Skill",
    "Bash(svstyle *)", "Bash(verilator *)", "Bash(yosys *)", "Bash(iverilog *)",
    "Bash(vvp *)", "Bash(ls *)", "Bash(cat *)", "Bash(cp *)", "Bash(mkdir *)",
    "Bash(head *)", "Bash(tail *)", "Bash(grep *)", "Bash(sed *)", "Bash(rm -rf build*)",
    "Bash(build/*)", "Bash(./build/*)", "Bash(obj_dir/*)", "Bash(./obj_dir/*)",  # a built testbench
]  # fmt: skip
TIMEOUT = 900  # seconds per claude run


def problems(dataset: Path) -> list[str]:
    d = dataset / "dataset_spec-to-rtl"
    names = sorted(p.name.removesuffix("_test.sv") for p in d.glob("*_test.sv"))
    return [n for n in names if n not in BROKEN]


def simulate(dataset: Path, prob: str, dut: Path, work: Path) -> tuple[bool, str]:
    """The dataset's own testbench against `dut`: pass means `Mismatches: 0`."""
    d = dataset / "dataset_spec-to-rtl"
    tb = work / "tb.sv"
    tb.write_text("".join(ln for ln in (d / f"{prob}_test.sv").open() if "$dump" not in ln))
    sim = work / "sim"
    srcs = [str(dut), str(tb), str(d / f"{prob}_ref.sv")]
    # -I: the DUT may include a header beside it (the skill's assert_macros.svh).
    build = subprocess.run([*IVERILOG, f"-I{dut.parent}", "-o", str(sim), *srcs], capture_output=True, text=True,
                           cwd=work)  # fmt: skip
    if build.returncode:
        return False, "does not build: " + build.stderr.strip()[-300:]
    try:
        run = subprocess.run(["vvp", "-n", str(sim)], capture_output=True, text=True,
                             cwd=work, timeout=60)  # fmt: skip
    except subprocess.TimeoutExpired:
        return False, "simulation timed out"
    m = re.search(r"Mismatches: (\d+) in (\d+) samples", run.stdout)
    return bool(m and m[1] == "0"), m[0] if m else run.stdout.strip()[-200:]


def grade_refs(dataset: Path, work: Path) -> int:
    ok = 0
    for prob in problems(dataset):
        w = work / prob
        w.mkdir(parents=True, exist_ok=True)
        ref = (dataset / "dataset_spec-to-rtl" / f"{prob}_ref.sv").read_text()
        (w / "TopModule.sv").write_text(re.sub(r"\bRefModule\b", "TopModule", ref))
        passed, why = simulate(dataset, prob, w / "TopModule.sv", w)
        ok += passed
        if not passed:
            print(f"{prob}: {why}")
    print(f"{ok}/{len(problems(dataset))} references pass their own testbench")
    return 0 if ok == len(problems(dataset)) else 1


def generate(prompt: str, work: Path, skill: bool, model: str, budget: float) -> dict:
    cmd = ["claude", "-p", prompt, "--model", model, "--output-format", "json",
           "--setting-sources", "project",
           "--permission-mode", "dontAsk", "--allowedTools", *TOOLS,
           "--max-budget-usd", str(budget)]  # fmt: skip
    if skill:
        cmd += ["--plugin-dir", str(REPO), "--add-dir", str(REPO / "skill")]
    t0 = time.time()
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, cwd=work, timeout=TIMEOUT,
                             stdin=subprocess.DEVNULL)  # fmt: skip
        doc = json.loads(res.stdout or "{}")
    except subprocess.TimeoutExpired:
        doc = {"error": "timeout"}
    except json.JSONDecodeError:
        doc = {"error": res.stderr[-300:]}
    (work / "claude.json").write_text(json.dumps(doc, indent=1))
    # The session's transcript, kept beside the result while the skill is being tuned.
    if sid := doc.get("session_id"):
        for t in (Path.home() / ".claude" / "projects").glob(f"*/{sid}.jsonl"):
            shutil.copy(t, work / "transcript.jsonl")
    return {"cost": doc.get("total_cost_usd", 0.0), "turns": doc.get("num_turns", 0),
            "seconds": round(time.time() - t0)}  # fmt: skip


def grade(dataset: Path, prob: str, out: Path) -> dict:
    dut = out / "TopModule.sv"
    if not dut.exists():  # written under another name: take the file that defines it
        defines = (p for p in out.glob("*.sv") if re.search(r"module\s+TopModule\b", p.read_text()))
        dut = next(defines, dut)
    if not dut.exists():
        return {
            "pass": False,
            "why": "no TopModule",
            "svstyle": False,
            "must": 0,
            "verilator": False,
            "verilator_first": "",
        }
    sim = out / "grade"
    sim.mkdir(exist_ok=True)
    passed, why = simulate(dataset, prob, dut, sim)
    sv = subprocess.run(["svstyle", "check", "--json", dut.name], capture_output=True, text=True,
                        cwd=out)  # fmt: skip
    try:
        style = json.loads(sv.stdout)
    except json.JSONDecodeError:
        style = {"exit_code": sv.returncode, "summary": {}}
    vl = subprocess.run(["verilator", "--lint-only", "-Wall", dut.name], capture_output=True,
                        text=True, cwd=out)  # fmt: skip
    warns = [ln for ln in vl.stderr.splitlines() if re.match(r"%(Warning|Error)", ln)]
    return {"pass": passed, "why": why, "svstyle": style.get("exit_code") == 0,
            "must": style.get("summary", {}).get("MUST", 0), "verilator": not warns,
            "verilator_first": warns[0] if warns else ""}  # fmt: skip


def one(dataset: Path, prob: str, cfg: str, out: Path, model: str, budget: float) -> dict:
    work = out / cfg / prob
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    prompt = (dataset / "dataset_spec-to-rtl" / f"{prob}_prompt.txt").read_text().strip() + ASK
    gen = generate(prompt, work, cfg == "with_skill", model, budget)
    row = {"problem": prob, "config": cfg, **gen, **grade(dataset, prob, work)}
    print(f"{cfg:13s} {prob:32s} pass={row['pass']!s:5s} svstyle={row['svstyle']!s:5s} "
          f"${row['cost']:.2f} {row['seconds']}s", flush=True)  # fmt: skip
    return row


def table(rows: list[dict], model: str) -> str:
    out = [f"VerilogEval v2 spec-to-RTL, {len({r['problem'] for r in rows})} problems, "
           f"{model}, {time.strftime('%Y-%m-%d')}\n",
           "| config | pass@1 | svstyle clean | Verilator -Wall clean | $/problem | s/problem |",
           "|---|---|---|---|---|---|"]  # fmt: skip
    for cfg in ("without_skill", "with_skill"):
        rs = [r for r in rows if r["config"] == cfg]
        if not rs:
            continue
        n = len(rs)
        pas, sty, vlt = (f"{sum(r[k] for r in rs)}/{n}" for k in ("pass", "svstyle", "verilator"))
        cost, secs = sum(r["cost"] for r in rs) / n, sum(r["seconds"] for r in rs) / n
        out.append(f"| {cfg} | {pas} | {sty} | {vlt} | {cost:.2f} | {secs:.0f} |")
    return "\n".join(out) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("cmd", choices=["run", "grade-refs"])
    ap.add_argument("--dataset", type=Path, required=True, help="a verilog-eval checkout")
    # Outside the repo: inside it, the runs would pick up its project settings and
    # CLAUDE.md, and Claude Code refuses writes into the plugin directory.
    ap.add_argument("--out", type=Path, default=Path(tempfile.gettempdir()) / "verilogeval")
    ap.add_argument("--subset", type=int, help="every k-th problem, this many")
    ap.add_argument("--ids", help="comma-separated problem name prefixes, e.g. Prob001,Prob050")
    ap.add_argument("--configs", default="without_skill,with_skill")
    ap.add_argument("--model", default="claude-opus-5-5")
    ap.add_argument("--budget", type=float, default=3.0, help="USD cap per run")
    ap.add_argument("--jobs", type=int, default=4)
    args = ap.parse_args()
    dataset = args.dataset.resolve()
    if args.out.resolve().is_relative_to(REPO):
        ap.error("--out must be outside the repository")
    args.out.mkdir(parents=True, exist_ok=True)
    if args.cmd == "grade-refs":
        return grade_refs(dataset, args.out / "refs")

    probs = problems(dataset)
    if args.ids:
        probs = [p for p in probs if p.startswith(tuple(args.ids.split(",")))]
    if args.subset:  # the set is ordered roughly by difficulty: sample across it
        step = max(1, len(probs) // args.subset)
        probs = probs[step // 2 :: step][: args.subset]
    jobs = [(p, c) for p in probs for c in args.configs.split(",")]
    with ThreadPoolExecutor(args.jobs) as pool:
        rows = list(pool.map(lambda j: one(dataset, *j, args.out, args.model, args.budget), jobs))
    (args.out / "results.json").write_text(json.dumps(rows, indent=1))
    md = table(rows, args.model)
    (args.out / "results.md").write_text(md)
    print("\n" + md)
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""Run evals through `claude -p`, with and without the skill, grade them, print one table.

    uv run python evals/run.py classics --ids 101,105 --runs 3
    uv run python evals/run.py evals --ids 10,11,12 --configs with_skill

Each run starts in an empty directory outside the repo, as in verilogeval.py:
`--setting-sources project`, the skill added with `--plugin-dir` for
with_skill only. Input files are copied in at the path the prompt names.
Layout: OUT/eval-<name>/<config>/run-N/{outputs,grading.json,timing.json};
OUT/results.md is the table.
"""

import argparse
import json
import shutil
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import grade
import verilogeval

REPO = verilogeval.REPO


def one(e: dict, cfg: str, n: int, out: Path, model: str, budget: float) -> dict:
    name = e.get("name", str(e["id"]))
    d = out / f"eval-{name}"
    run = d / cfg / f"run-{n}"
    shutil.rmtree(run, ignore_errors=True)
    work = run / "outputs"
    work.mkdir(parents=True)
    (d / "eval_metadata.json").write_text(
        json.dumps({"eval_id": e["id"], "eval_name": name, "prompt": e["prompt"]}, indent=1)
    )
    for f in e.get("files", []):  # the prompt names them relative to the repo root
        (work / f).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(REPO / f, work / f)
    timing = verilogeval.generate(e["prompt"], work, cfg == "with_skill", model, budget)
    (run / "timing.json").write_text(json.dumps(timing))
    exp = grade.grade(work, e.get("checks", []))
    passed = sum(x["passed"] for x in exp)
    (run / "grading.json").write_text(json.dumps({
        "expectations": exp,
        "summary": {"passed": passed, "failed": len(exp) - passed, "total": len(exp)},
    }, indent=2))  # fmt: skip
    print(f"{name}/{cfg}/run-{n}: {passed}/{len(exp)}, ${timing['cost']:.2f}", flush=True)
    return {"eval": name, "config": cfg, "run": n, "passed": passed, "total": len(exp), **timing}


def table(rows: list[dict], model: str) -> str:
    out = [f"{model}, {time.strftime('%Y-%m-%d')}\n",
           "| eval | config | checks passed | $/run | s/run |",
           "|---|---|---|---|---|"]  # fmt: skip
    for key in sorted({(r["eval"], r["config"]) for r in rows}):
        rs = [r for r in rows if (r["eval"], r["config"]) == key]
        p, t = sum(r["passed"] for r in rs), sum(r["total"] for r in rs)
        cost, secs = sum(r["cost"] for r in rs) / len(rs), sum(r["seconds"] for r in rs) / len(rs)
        out.append(f"| {key[0]} | {key[1]} | {p}/{t} | {cost:.2f} | {secs:.0f} |")
    return "\n".join(out) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("suite", choices=["evals", "classics"])
    ap.add_argument("--ids", help="comma-separated eval ids; default all")
    ap.add_argument("--configs", default="without_skill,with_skill")
    ap.add_argument("--runs", type=int, default=1)
    # Outside the repo: Claude Code refuses writes into the plugin directory.
    ap.add_argument("--out", type=Path, default=Path(tempfile.gettempdir()) / "sv-evals")
    ap.add_argument("--model", default="claude-opus-5-5")
    ap.add_argument("--budget", type=float, default=4.0, help="USD cap per run")
    ap.add_argument("--jobs", type=int, default=4)
    args = ap.parse_args()
    if args.out.resolve().is_relative_to(REPO):
        ap.error("--out must be outside the repository")
    evals = json.loads((REPO / "evals" / f"{args.suite}.json").read_text())["evals"]
    if args.ids:
        evals = [e for e in evals if str(e["id"]) in args.ids.split(",")]
    jobs = [(e, c, n) for e in evals for c in args.configs.split(",")
            for n in range(1, args.runs + 1)]  # fmt: skip
    out = args.out.resolve()
    with ThreadPoolExecutor(args.jobs) as pool:
        rows = list(pool.map(lambda j: one(*j, out, args.model, args.budget), jobs))
    (out / "results.json").write_text(json.dumps(rows, indent=1))
    md = table(rows, args.model)
    (out / "results.md").write_text(md)
    print("\n" + md)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

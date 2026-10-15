"""Run evals through `claude -p`, with and without the skill, grade them, print one table.

    uv run python evals/run.py classics --ids 101,105 --runs 3
    uv run python evals/run.py evals --ids 10,11,12 --configs with_skill
    uv run python evals/run.py classics --ids 104 --configs with_skill --synth yosys-slang

Each run starts in an empty directory outside the repo, as in verilogeval.py:
`--setting-sources project`, the skill added with `--plugin-dir` for
with_skill only. Input files are copied in at the path the prompt names.
Layout: OUT/eval-<name>/<config>/run-N/{outputs,grading.json,timing.json};
OUT/results.md is the table.
"""

import argparse
import json
import math
import shutil
import statistics
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import grade
import verilogeval

REPO = verilogeval.REPO


def one(
    e: dict, cfg: str, n: int, out: Path, model: str, budget: float, synth: str | None = None
) -> dict:
    name = e.get("name", str(e["id"]))
    d = out / f"eval-{name}"
    run = d / cfg / f"run-{n}"
    shutil.rmtree(run, ignore_errors=True)
    work = run / "outputs"
    work.mkdir(parents=True)
    (d / "eval_metadata.json").write_text(
        json.dumps({"eval_id": e["id"], "eval_name": name, "prompt": e["prompt"]}, indent=1)
    )
    if synth:  # what a project says in its config; the skill and the grader both read it
        (work / ".svstyle.toml").write_text(f'synth = "{synth}"\n')
    for f in e.get("files", []):  # the prompt names them relative to the repo root
        (work / f).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(REPO / f, work / f)
    timing = verilogeval.generate(e["prompt"], work, cfg == "with_skill", model, budget)
    (run / "timing.json").write_text(json.dumps(timing))
    exp = grade.grade(work, e.get("checks", []))
    passed = sum(x["passed"] for x in exp)
    size = grade.metrics(work)
    if "error" in size:
        print(f"warning: {name}/{cfg}/run-{n}: no depth: {size['error']}", flush=True)
    # Depth is compared only on correct RTL: a broken block is not shallow.
    tb = {c["text"] for c in e.get("checks", []) if "equiv_tb" in c}
    correct = all(x["passed"] for x in exp if x["text"] in tb)
    (run / "grading.json").write_text(json.dumps({
        "expectations": exp,
        "metrics": size,
        "summary": {"passed": passed, "failed": len(exp) - passed, "total": len(exp)},
    }, indent=2))  # fmt: skip
    print(f"{name}/{cfg}/run-{n}: {passed}/{len(exp)}, ${timing['cost']:.2f}", flush=True)
    return {"eval": name, "config": cfg, "run": n, "passed": passed, "total": len(exp),
            "correct": correct, "has_rtl": bool(size), "depth_error": size.get("error"),
            **{k: size[k] for k in METRICS if k in size}, **timing}  # fmt: skip


METRICS = ("depth", "transistors")


def median(rows: list[dict], key: str) -> float | None:
    """Over the runs whose RTL is correct; None when there is none."""
    vals = [r[key] for r in rows if r.get("correct") and key in r]
    return statistics.median(vals) if vals else None


def table(rows: list[dict], model: str) -> str:
    out = [f"{model}, {time.strftime('%Y-%m-%d')}\n",
           "| eval | config | checks passed | depth | transistors | $/run | s/run |",
           "|---|---|---|---|---|---|---|"]  # fmt: skip
    for key in sorted({(r["eval"], r["config"]) for r in rows}):
        rs = [r for r in rows if (r["eval"], r["config"]) == key]
        p, t = sum(r["passed"] for r in rs), sum(r["total"] for r in rs)
        cost, secs = sum(r["cost"] for r in rs) / len(rs), sum(r["seconds"] for r in rs) / len(rs)
        size = " | ".join(f"{m:g}" if (m := median(rs, k)) is not None else "–" for k in METRICS)
        out.append(f"| {key[0]} | {key[1]} | {p}/{t} | {size} | {cost:.2f} | {secs:.0f} |")
    return "\n".join(out) + "\n" + ratios(rows)


def ratios(rows: list[dict]) -> str:
    """with_skill over without_skill, per eval and as a geomean. Above 1.10 overall or
    1.25 for one eval is past the ~7% noise of an equivalent rewrite."""
    out, logs = [], {k: [] for k in METRICS}
    for ev in sorted({r["eval"] for r in rows}):
        cells = []
        for k in METRICS:
            w, wo = (median([r for r in rows if r["eval"] == ev and r["config"] == c], k)
                     for c in ("with_skill", "without_skill"))  # fmt: skip
            if not w or not wo:
                cells.append("–")
                continue
            logs[k].append(math.log(w / wo))
            cells.append(f"{w / wo:.2f}" + (" **regression**" if w / wo > 1.25 else ""))
        out.append(f"| {ev} | " + " | ".join(cells) + " |")
    gaps = holes(rows)
    if not any(logs.values()):
        return gaps
    geo = [math.exp(statistics.fmean(v)) if v else None for v in logs.values()]
    cells = [f"{g:.2f}" + (" **regression**" if g > 1.10 else "") if g else "–" for g in geo]
    head = ["\nWith skill / without, median of correct runs:\n",
            "| eval | depth | transistors |", "|---|---|---|"]  # fmt: skip
    return "\n".join([*head, *out, "| geomean | " + " | ".join(cells) + " |"]) + "\n" + gaps


def holes(rows: list[dict]) -> str:
    """Every RTL run the ratios leave out, and why: a hole is never silent."""
    out = []
    for r in sorted(rows, key=lambda r: (r["eval"], r["config"], r["run"])):
        if not r.get("has_rtl"):
            continue
        why = r.get("depth_error") or ("" if r.get("correct") else "fails its testbench")
        if why:
            out.append(f"- {r['eval']}/{r['config']}/run-{r['run']}: {why}")
    return "\nLeft out of depth and transistors:\n\n" + "\n".join(out) + "\n" if out else ""


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
    ap.add_argument("--synth", help='write `synth = "SYNTH"` to each run\'s .svstyle.toml')
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
        rows = list(pool.map(lambda j: one(*j, out, args.model, args.budget, args.synth), jobs))
    (out / "results.json").write_text(json.dumps(rows, indent=1))
    md = table(rows, args.model)
    (out / "results.md").write_text(md)
    print("\n" + md)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

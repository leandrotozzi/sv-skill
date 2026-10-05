# /// script
# requires-python = ">=3.11"
# dependencies = ["pygments>=2.17"]
# ///
"""Side-by-side code of one eval iteration, with and without the skill.

    uv run evals/compare.py skill/systemverilog-rtl-workspace/iteration-N

Writes <iteration>/compare/: index.html (scores, cost and time of every eval)
and one self-contained page per eval (Pygments highlighting inlined, no
network) with its prompt, grades, cost and the RTL of both runs.
"""

# ruff: noqa: E501  (the page template is HTML/CSS, kept one rule per line)

import html
import json
import sys
from pathlib import Path

from pygments import highlight
from pygments.formatters import HtmlFormatter
from pygments.lexers import SystemVerilogLexer

CONFIGS = ("with_skill", "without_skill")
LABEL = {"with_skill": "Con skill", "without_skill": "Sin skill"}


def rtl_files(out: Path) -> list[Path]:
    # Packages first, then the rest; headers last, as a reader meets them.
    files = [p for p in out.iterdir() if p.suffix in (".sv", ".svh", ".v")]
    return sorted(files, key=lambda p: (p.suffix == ".svh", not p.stem.endswith("_pkg"), p.name))


def run_block(cfg_dir: Path, fmt: HtmlFormatter) -> tuple[str, str, dict]:
    run = cfg_dir / "run-1"
    grading = json.loads((run / "grading.json").read_text())
    s = grading["summary"]
    score = f"{s['passed']}/{s['total']}"
    cost_file = run / "cost.json"
    cost = json.loads(cost_file.read_text()) if cost_file.exists() else {}
    fails = "".join(
        f"<li><b>{html.escape(e['text'])}</b><pre class='ev'>{html.escape(e['evidence'])}</pre></li>"
        for e in grading["expectations"]
        if not e["passed"]
    )
    parts = [
        f"<ul class='fails'>{fails}</ul>"
        if fails
        else "<p class='allok'>Todos los chequeos pasan</p>"
    ]
    for f in rtl_files(run / "outputs"):
        code = highlight(f.read_text(), SystemVerilogLexer(), fmt)
        lines = f.read_text().count("\n")
        parts.append(
            f"<details open><summary>{html.escape(f.name)} <span class='muted'>· {lines} líneas</span>"
            f"</summary>{code}</details>"
        )
    return score, "".join(parts), cost


def money(cost: dict) -> str:
    return f"≈${cost['usd']:.2f}" if cost else "–"


def minutes(cost: dict) -> str:
    return f"{cost['wall_s'] / 60:.1f} min" if cost else "–"


def main(iteration: Path) -> None:
    fmt = HtmlFormatter(linenos="table", cssclass="hl")
    evals = sorted(p for p in iteration.glob("eval-*") if p.is_dir())
    metas = {ev: json.loads((ev / "eval_metadata.json").read_text()) for ev in evals}
    evals.sort(key=lambda ev: metas[ev]["eval_id"])
    rows, pages, totals = [], {}, {cfg: {"usd": 0.0, "wall_s": 0.0} for cfg in CONFIGS}
    for ev in evals:
        meta = metas[ev]
        name = meta["eval_name"]
        cols, scores, costs = [], {}, {}
        for cfg in CONFIGS:
            scores[cfg], body, costs[cfg] = run_block(ev / cfg, fmt)
            for k in totals[cfg]:
                totals[cfg][k] += costs[cfg].get(k, 0)
            c = costs[cfg]
            stats = (f"<p class='stats'>{money(c)} · {minutes(c)} · {c['turns']} turnos · "
                     f"{c['tokens']['output']:,} tokens de salida</p>") if c else ""  # fmt: skip
            cols.append(
                f"<div class='col'><h3>{LABEL[cfg]} <span class='score {cfg}'>{scores[cfg]}</span></h3>"
                f"{stats}{body}</div>"
            )
        cells = "".join(
            f"<td>{scores[cfg]}</td><td>{money(costs[cfg])}</td><td>{minutes(costs[cfg])}</td>"
            for cfg in CONFIGS
        )
        rows.append(f"<tr><td><a href='{name}.html'>{meta['eval_id']}. {html.escape(name)}</a></td>{cells}</tr>")
        pages[name] = (
            f"<section><h2>{meta['eval_id']}. {html.escape(name)}</h2>"
            f"<p class='prompt'>{html.escape(meta['prompt'])}</p><div class='cols'>{''.join(cols)}</div></section>"
        )
    nav = "<a href='index.html'><b>Resumen</b></a>" + "".join(
        f"<a href='{name}.html'>{html.escape(name)}</a>" for name in pages
    )
    head = "".join(f"<th colspan='3'>{LABEL[cfg]}</th>" for cfg in CONFIGS)
    sub = "<th>chequeos</th><th>costo</th><th>tiempo</th>" * len(CONFIGS)
    foot = "".join(
        f"<td></td><td>${totals[cfg]['usd']:.2f}</td><td>{totals[cfg]['wall_s'] / 60:.1f} min</td>"
        for cfg in CONFIGS
    )
    index = (
        f"<section><h2>Resumen · {html.escape(iteration.name)}</h2>"
        f"<table class='sum'><thead><tr><th></th>{head}</tr><tr><th>ejemplo</th>{sub}</tr></thead>"
        f"<tbody>{''.join(rows)}</tbody><tfoot><tr><td>total</td>{foot}</tr></tfoot></table>"
        "<p class='prompt'>Costo a precio de Claude Opus 5.5. Entrada y caché son exactos, de las "
        "transcripciones; la salida (razonamiento incluido) se estima por el crecimiento del contexto, "
        "porque Claude Code registra el uso al empezar cada mensaje. Tiempo: primer a último evento "
        "de cada corrida.</p></section>"
    )
    out = iteration / "compare"
    out.mkdir(exist_ok=True)
    for name, body in {"index": index, **pages}.items():
        (out / f"{name}.html").write_text(page(iteration.name, name, nav, body), encoding="utf-8")
    print(f"wrote {out}/index.html and {len(pages)} pages")


def page(iteration: str, title: str, nav: str, body: str) -> str:
    light = HtmlFormatter(style="default").get_style_defs(".hl")
    dark = HtmlFormatter(style="github-dark").get_style_defs(".hl")
    return f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(title)} · con y sin skill</title>
<style>
:root {{ --bg:#fbfbfc; --fg:#1c2230; --dim:#6e7684; --line:#e5e7eb; --card:#fff;
  --ok:#0e7c58; --bad:#c0392b; --accent:#0a6e96; --codebg:#f6f8fa; }}
@media (prefers-color-scheme: dark) {{ :root {{ --bg:#0d1117; --fg:#e6edf3; --dim:#8b949e;
  --line:#30363d; --card:#161b22; --ok:#3fb950; --bad:#f85149; --accent:#58a6ff; --codebg:#0d1117; }} }}
* {{ box-sizing:border-box; }}
body {{ margin:0; background:var(--bg); color:var(--fg);
  font:15px/1.5 -apple-system,"Segoe UI",Helvetica,sans-serif; }}
nav {{ position:fixed; top:0; left:0; bottom:0; width:260px; overflow:auto; padding:16px;
  border-right:1px solid var(--line); background:var(--card); }}
nav h1 {{ font-size:1rem; margin:0 0 12px; }}
nav a {{ display:flex; justify-content:space-between; gap:8px; padding:6px 8px; border-radius:6px;
  color:var(--fg); text-decoration:none; font-size:.85rem; }}
nav a:hover {{ background:var(--codebg); }}
main {{ margin-left:260px; padding:24px; }}
section {{ margin-bottom:48px; }}
h2 {{ margin:0 0 4px; }}
.prompt {{ color:var(--dim); max-width:110ch; }}
.cols {{ display:grid; grid-template-columns:1fr 1fr; gap:16px; }}
.col {{ min-width:0; background:var(--card); border:1px solid var(--line); border-radius:8px; padding:12px; }}
h3 {{ margin:0 0 8px; display:flex; justify-content:space-between; align-items:center; }}
.score {{ font-size:.85rem; padding:2px 8px; border-radius:99px; color:#fff; }}
.score.with_skill {{ background:var(--ok); }} .score.without_skill {{ background:var(--bad); }}
.muted {{ color:var(--dim); font-weight:normal; }}
.stats {{ margin:0 0 8px; color:var(--dim); font-size:.85rem; }}
.sum {{ border-collapse:collapse; background:var(--card); }}
.sum th, .sum td {{ border:1px solid var(--line); padding:6px 10px; text-align:right; }}
.sum td:first-child, .sum th:first-child {{ text-align:left; }}
.sum a {{ color:var(--accent); }}
.sum tfoot {{ font-weight:600; }}
.allok {{ color:var(--ok); margin:0 0 8px; }}
.fails {{ margin:0 0 8px; padding-left:18px; font-size:.85rem; }}
.fails li {{ margin-bottom:6px; }}
.ev {{ white-space:pre-wrap; margin:2px 0 0; color:var(--dim); font-size:.78rem; max-height:8em; overflow:auto; }}
details {{ margin-top:8px; }}
summary {{ cursor:pointer; font-family:ui-monospace,Menlo,monospace; font-size:.85rem; }}
.hl, .hltable {{ background:var(--codebg) !important; }}
.hltable {{ width:100%; border-collapse:collapse; display:block; overflow-x:auto; border-radius:6px; margin-top:6px; }}
.hltable td {{ padding:0 8px; vertical-align:top; }}
.hltable .linenos {{ color:var(--dim); user-select:none; text-align:right; border-right:1px solid var(--line); }}
.hl pre, .linenos pre {{ margin:0; font:12.5px/1.45 ui-monospace,Menlo,monospace; }}
{light}
@media (prefers-color-scheme: dark) {{ {dark} }}
@media (max-width: 1100px) {{ .cols {{ grid-template-columns:1fr; }} }}
@media (max-width: 760px) {{ nav {{ position:static; width:auto; border-right:0;
  border-bottom:1px solid var(--line); }} main {{ margin-left:0; padding:16px; }} }}
</style></head><body>
<nav><h1>Evals · {html.escape(iteration)}</h1>{nav}</nav>
<main>{body}</main>
</body></html>
"""


if __name__ == "__main__":
    main(Path(sys.argv[1]))

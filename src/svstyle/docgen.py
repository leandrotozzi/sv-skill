"""Render the rules DB to the HTML review page and the skill's Markdown references.

All three outputs are generated; none is ever hand-edited. `svstyle rules --check`
regenerates and diffs them, so an edit here that changes output fails CI until
the files are regenerated with `svstyle rules --gen`.
"""

import html
import re
from datetime import date

from .rules import CATEGORIES, Rule, by_category

SEV_COLOR = {"MUST": "red", "SHOULD": "orange", "MAY": "blue"}

TOOL_LABEL = {
    "verible-format": "verible format",
    "verible-lint": "verible lint",
    "verilator": "verilator",
    "svstyle": "svstyle",
    "review": "review only",
}

# ---------------------------------------------------------------------------
# Markdown
# ---------------------------------------------------------------------------


def render_markdown_compact(rules: list[Rule]) -> str:
    """The skill's always-loaded reference: one line per rule."""
    out = [
        "# SystemVerilog RTL rules",
        "",
        "Generated from `rules.toml` — do not edit. Full rationale and examples:",
        "`rules-rationale.md` (load it when a rule is questioned or a finding is unclear).",
        "",
        "`MUST` violations fail `svstyle check`. `[fix]` marks what `svstyle fix` writes for you.",
        "",
    ]
    for cat, group in by_category(rules).items():
        out += [f"## {cat} — {CATEGORIES[cat]}", ""]
        for r in group:
            fix = " `[fix]`" if r.autofix else ""
            out.append(f"- **{r.id}** · {r.severity} · {r.statement}{fix}")
        out.append("")
    return "\n".join(out).rstrip() + "\n"


def render_markdown_full(rules: list[Rule]) -> str:
    """Loaded on demand: every rule with its rationale, examples and sources."""
    out = [
        "# SystemVerilog RTL rules — rationale and examples",
        "",
        "Generated from `rules.toml` — do not edit. To read one rule, search for its",
        "heading, e.g. `### DOC-003`, instead of loading the whole file.",
        "",
        "## Contents",
        "",
    ]
    grouped = by_category(rules)
    out += [f"- {c} — {CATEGORIES[c]}: {g[0].id} … {g[-1].id}" for c, g in grouped.items()]
    out.append("")
    for cat, group in grouped.items():
        out += [f"## {cat} — {CATEGORIES[cat]}", ""]
        for r in group:
            out += [f"### {r.id} ({r.severity}) — {r.title}", "", r.statement, ""]
            out += [f"**Why:** {r.rationale}", ""]
            if r.good:
                out += ["**Good:**", "", "```systemverilog", r.good, "```", ""]
            if r.bad:
                out += ["**Bad:**", "", "```systemverilog", r.bad, "```", ""]
            names = " ".join(f"`{n}`" for n in r.tool_rules)
            enforced = TOOL_LABEL[r.tool] + (f" {names}" if names else "")
            if r.autofix:
                enforced += " · autofixable"
            out += [f"**Enforced by:** {enforced}", "", f"**Sources:** {', '.join(r.sources)}", ""]
    return "\n".join(out).rstrip() + "\n"


# ---------------------------------------------------------------------------
# HTML
# ---------------------------------------------------------------------------

CSS = """
:root{
 --bg:#FBFBFC;--fg:#1C2230;--dim:#6E7684;--line:#E5E7EB;--card:#fff;
 --accent:#0A6E96;--red:#C0392B;--green:#0E7C58;--blue:#0A6E96;--orange:#B45309;
 --codebg:#1C22300D;--goodbg:#0E7C580D;--badbg:#C0392B0D;
 --display:"Avenir Next","Segoe UI",Helvetica Neue,sans-serif;
 --mono:ui-monospace,SFMono-Regular,"SF Mono",Menlo,monospace}
@media (prefers-color-scheme:dark){:root{
 --bg:#0D1117;--fg:#E4E8EE;--dim:#8B949E;--line:#21262D;--card:#151B23;
 --accent:#4FB6DE;--red:#E5786F;--green:#3FBE8C;--blue:#4FB6DE;--orange:#E09A5C;
 --codebg:#ffffff12;--goodbg:#3FBE8C14;--badbg:#E5786F14}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.6 var(--display)}
.wrap{max-width:1180px;margin:0 auto;padding:0 1.5rem 6rem}
.mast{padding:3rem 0 1.4rem}
h1{margin:0;font-size:1.85rem;letter-spacing:-.01em}
.mast p{margin:.5rem 0 0;color:var(--dim);max-width:70ch}
.stats{display:flex;gap:.6rem;flex-wrap:wrap;margin:1.5rem 0}
.stats div{background:var(--card);border:1px solid var(--line);border-radius:9px;
 padding:.6rem .95rem;min-width:6.2rem}
.stats b{display:block;font-size:1.45rem;font-weight:600;line-height:1.2}
.stats span{font-size:.7rem;letter-spacing:.06em;text-transform:uppercase;color:var(--dim)}
.bar{position:sticky;top:0;z-index:3;background:var(--bg);padding:.8rem 0;
 border-bottom:1px solid var(--line);margin-bottom:1.6rem}
.bar .row{display:flex;gap:.35rem;flex-wrap:wrap;align-items:center;margin-bottom:.45rem}
.bar .row:last-child{margin-bottom:0}
.bar label{font-size:.68rem;letter-spacing:.06em;text-transform:uppercase;
 color:var(--dim);width:4.6rem;flex:none}
button{font:inherit;font-size:.78rem;padding:.26rem .66rem;border:1px solid var(--line);
 border-radius:6px;background:var(--card);color:var(--dim);cursor:pointer}
button:hover{color:var(--fg);border-color:var(--dim)}
button.on{background:var(--accent);color:#fff;border-color:var(--accent)}
#q{flex:1;min-width:14rem;font:inherit;font-size:.85rem;padding:.3rem .65rem;
 border:1px solid var(--line);border-radius:6px;background:var(--card);color:var(--fg)}
#q:focus{outline:none;border-color:var(--accent)}
h2{font-size:.76rem;letter-spacing:.1em;text-transform:uppercase;color:var(--dim);
 margin:2.4rem 0 .8rem;padding-bottom:.4rem;border-bottom:1px solid var(--line)}
.rule{background:var(--card);border:1px solid var(--line);border-radius:10px;
 padding:1rem 1.15rem;margin-bottom:.7rem}
.rhead{display:flex;gap:.6rem;align-items:baseline;flex-wrap:wrap}
.rid{font-family:var(--mono);font-size:.82rem;font-weight:600;color:var(--accent);
 cursor:pointer;border:none;background:none;padding:0}
.rid:hover{text-decoration:underline}
.pill{font-size:.64rem;font-weight:700;letter-spacing:.07em;padding:.12rem .45rem;
 border-radius:4px;border:1px solid currentColor}
.sev-MUST{color:var(--red)}.sev-SHOULD{color:var(--orange)}.sev-MAY{color:var(--blue)}
.tool{font-size:.68rem;color:var(--dim);margin-left:auto;font-family:var(--mono)}
.fix{color:var(--green);font-weight:600}
.rt{font-weight:600}
.stm{margin:.5rem 0 0}
.why{margin:.55rem 0 0;color:var(--dim);font-size:.93em}
.ex{display:grid;grid-template-columns:1fr 1fr;gap:.6rem;margin-top:.8rem}
/* Realistic SystemVerilog with trailing comments runs past a half-width
   column; stack those so the line is read, not scrolled. */
.ex.stack{grid-template-columns:1fr}
.ex>div{border:1px solid var(--line);border-radius:7px;overflow:hidden}
.ex .t{font-size:.64rem;letter-spacing:.07em;text-transform:uppercase;padding:.3rem .6rem;
 border-bottom:1px solid var(--line)}
.good .t{color:var(--green);background:var(--goodbg)}
.bad .t{color:var(--red);background:var(--badbg)}
pre{margin:0;padding:.55rem .6rem;font-family:var(--mono);font-size:.78rem;line-height:1.5;
 overflow-x:auto;white-space:pre}
.src{margin:.7rem 0 0;font-size:.72rem;color:var(--dim)}
.hidden{display:none}
#none{color:var(--dim);padding:2rem 0}
@media(max-width:680px){.ex{grid-template-columns:1fr}.bar label{width:100%}}
"""

JS = """
const rules=[...document.querySelectorAll('.rule')];
const state={cat:'',sev:'',tool:'',q:''};
function apply(){
  let n=0;
  for(const el of rules){
    const ok=(!state.cat||el.dataset.cat===state.cat)
      &&(!state.sev||el.dataset.sev===state.sev)
      &&(!state.tool||el.dataset.tool===state.tool)
      &&(!state.q||el.dataset.text.includes(state.q));
    el.classList.toggle('hidden',!ok); n+=ok?1:0;
  }
  for(const h of document.querySelectorAll('h2')){
    const any=[...document.querySelectorAll('.rule[data-cat="'+h.dataset.cat+'"]')]
      .some(e=>!e.classList.contains('hidden'));
    h.classList.toggle('hidden',!any);
  }
  document.getElementById('none').classList.toggle('hidden',n>0);
  document.getElementById('shown').textContent=n;
}
for(const b of document.querySelectorAll('button[data-k]')){
  b.onclick=()=>{
    const k=b.dataset.k,v=b.dataset.v;
    state[k]=state[k]===v?'':v;
    for(const o of document.querySelectorAll('button[data-k="'+k+'"]'))
      o.classList.toggle('on',o.dataset.v===state[k]&&state[k]!=='');
    apply();
  };
}
// Normalise the query exactly as the index was built, so that punctuation
// the reader types ("module's", "`always_ff`") still matches.
const norm=s=>s.toLowerCase().replace(/[^a-z0-9 _-]+/g,' ');
document.getElementById('q').oninput=e=>{state.q=norm(e.target.value);apply();};
for(const b of document.querySelectorAll('.rid'))
  b.onclick=()=>navigator.clipboard?.writeText(b.textContent);
apply();
"""


def _esc(text: str) -> str:
    return html.escape(text, quote=True)


def _card(r: Rule) -> str:
    tool = TOOL_LABEL[r.tool] + (f" · {' '.join(r.tool_rules)}" if r.tool_rules else "")
    if r.autofix:
        tool += ' · <span class="fix">fix</span>'
    # Strip punctuation rather than escaping it: the raw text would put HTML
    # entities in the attribute, so searching "module's" could never match.
    searchable = re.sub(
        r"[^a-z0-9 _-]+", " ", " ".join([r.id, r.title, r.statement, r.rationale]).lower()
    )

    ex = ""
    if r.good or r.bad:
        widest = max((len(ln) for ln in (r.good + "\n" + r.bad).splitlines()), default=0)
        stack = " stack" if widest > 56 else ""
        cells = []
        if r.good:
            cells.append(
                f'<div class="good"><div class="t">good</div><pre>{_esc(r.good)}</pre></div>'
            )
        if r.bad:
            cells.append(f'<div class="bad"><div class="t">bad</div><pre>{_esc(r.bad)}</pre></div>')
        ex = f'<div class="ex{stack}">{"".join(cells)}</div>'

    return (
        f'<div class="rule" data-cat="{r.category}" data-sev="{r.severity}"'
        f' data-tool="{r.tool}" data-text="{searchable}">'
        f'<div class="rhead"><button class="rid">{r.id}</button>'
        f'<span class="pill sev-{r.severity}">{r.severity}</span>'
        f'<span class="rt">{_esc(r.title)}</span>'
        f'<span class="tool">{tool}</span></div>'
        f'<p class="stm">{_esc(r.statement)}</p>'
        f'<p class="why">{_esc(r.rationale)}</p>'
        f"{ex}"
        f'<p class="src">Sources: {_esc(", ".join(r.sources))}</p>'
        f"</div>"
    )


def render_html(rules: list[Rule], company: str = "") -> str:
    grouped = by_category(rules)
    counts = {s: sum(1 for r in rules if r.severity == s) for s in ("MUST", "SHOULD", "MAY")}
    autofix = sum(1 for r in rules if r.autofix)
    tools_used = [t for t in TOOL_LABEL if any(r.tool == t for r in rules)]

    stats = "".join(
        f"<div><b>{v}</b><span>{k}</span></div>"
        for k, v in [
            ("rules", len(rules)),
            ("must", counts["MUST"]),
            ("should", counts["SHOULD"]),
            ("may", counts["MAY"]),
            ("autofixed", autofix),
        ]
    )
    cat_btns = "".join(f'<button data-k="cat" data-v="{c}">{c}</button>' for c in grouped)
    sev_btns = "".join(
        f'<button data-k="sev" data-v="{s}">{s}</button>'
        for s in ("MUST", "SHOULD", "MAY")
        if counts[s]
    )
    tool_btns = "".join(
        f'<button data-k="tool" data-v="{t}">{TOOL_LABEL[t]}</button>' for t in tools_used
    )

    body = []
    for cat, group in grouped.items():
        body.append(f'<h2 data-cat="{cat}">{cat} — {CATEGORIES[cat]}</h2>')
        body += [_card(r) for r in group]

    subtitle = (
        "Every rule in the house SystemVerilog style, with its rationale, examples and "
        "who enforces it. Generated from <code>rules.toml</code>; the tool, the skill and "
        "this page all read that one file."
    )
    owner = f"{_esc(company)} · " if company else ""

    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>SystemVerilog RTL style guide</title>
<style>{CSS}</style></head><body><div class="wrap">
<div class="mast">
<h1>SystemVerilog RTL style guide</h1>
<p>{subtitle}</p>
<p style="font-size:.78rem">{owner}generated {date.today().isoformat()} ·
<span id="shown">{len(rules)}</span> of {len(rules)} shown · click a rule ID to copy it</p>
</div>
<div class="stats">{stats}</div>
<div class="bar">
<div class="row"><input id="q" placeholder="Search rules, rationale, IDs&hellip;"></div>
<div class="row"><label>Category</label>{cat_btns}</div>
<div class="row"><label>Severity</label>{sev_btns}</div>
<div class="row"><label>Enforced</label>{tool_btns}</div>
</div>
{"".join(body)}
<p id="none" class="hidden">No rule matches those filters.</p>
</div><script>{JS}</script></body></html>
"""

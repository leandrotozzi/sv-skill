"""Render the rules DB to the HTML review page and the skill's Markdown references.

All three outputs are generated; none is ever hand-edited. `svstyle rules --check`
regenerates and diffs them, so an edit here that changes output fails CI until
the files are regenerated with `svstyle rules --gen`.
"""

import html
import re

from .external import KNOWN_GOOD_VERIBLE_VERSIONS
from .rules import CATEGORIES, Rule, by_category

SEV_COLOR = {"MUST": "red", "SHOULD": "orange", "MAY": "blue"}

TOOL_LABEL = {
    "verible-format": "verible format",
    "verible-lint": "verible lint",
    "verilator": "verilator",
    "yosys": "yosys",
    "svstyle": "svstyle",
    "review": "review only",
}

# ---------------------------------------------------------------------------
# Markdown
# ---------------------------------------------------------------------------


# Categories that only matter in some designs, rendered to their own file so the
# always-loaded rules.md stays short; SKILL.md says when to read each.
ON_DEMAND = {"CDC": "rules-cdc.md"}


def render_markdown_compact(rules: list[Rule], part: str = "") -> str:
    """One line per rule: all of them; or `part="core"`, every category but
    ON_DEMAND's (the skill's always-loaded rules.md); or `part=<category>`."""
    title = f"{part} rules" if part not in ("", "core") else "SystemVerilog RTL rules"
    out = [
        f"# {title}",
        "",
        "Generated from `rules.toml` — do not edit. Full rationale and examples:",
        "`rules-rationale.md` (load it when a rule is questioned or a finding is unclear).",
        "",
        "`MUST` violations fail `svstyle check`. `[fix]` marks what `svstyle fix` writes for you.",
        "",
    ]
    if part == "core":
        out += [f"{c} rules are in `{f}`, read only when they apply." for c, f in ON_DEMAND.items()]
        out.append("")
    for cat, group in by_category(rules).items():
        if (part == "core" and cat in ON_DEMAND) or (part not in ("", "core") and cat != part):
            continue
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
            for tool, codes in r.also:
                enforced += f"; also {TOOL_LABEL[tool]} " + " ".join(f"`{n}`" for n in codes)
            if r.autofix:
                enforced += " · autofixable"
            out += [f"**Enforced by:** {enforced}", "", f"**Sources:** {', '.join(r.sources)}", ""]
    return "\n".join(out).rstrip() + "\n"


# ---------------------------------------------------------------------------
# HTML: the documentation site published to GitHub Pages
# ---------------------------------------------------------------------------

REPO_URL = "https://github.com/leandrotozzi/sv-skill"
FONTS = (
    "https://fonts.googleapis.com/css2?family=Fraunces:ital,opsz,wght@0,9..144,400..600;"
    "1,9..144,400&family=IBM+Plex+Mono:wght@400;500;600"
    "&family=IBM+Plex+Sans:wght@400;500;600&display=swap"
)

CSS = """
:root{
 --paper:#F3EFE6;--paper2:#EAE4D7;--card:#FBF9F4;--ink:#15171B;--ink2:#464B53;--dim:#7B7F86;
 --line:#DAD3C4;--grid:#E4DDCE;--copper:#B4531A;--mask:#0E5A43;--maskbg:#0E5A4314;
 --must:#B3261E;--should:#A35F05;--may:#2D5E8C;--good:#0E6B4C;--bad:#B3261E;
 --code:#16181D;--codefg:#E7E2D6;--codedim:#8A8F96;--codeline:#262A31;
 --ck:#E68A4E;--cc:#7E8790;--cn:#8FD3B4;--cm:#C9A0F0;--cs:#E8C46A;
 --display:"Fraunces",Georgia,serif;--body:"IBM Plex Sans",-apple-system,"Segoe UI",sans-serif;
 --mono:"IBM Plex Mono",ui-monospace,"SF Mono",Menlo,monospace;color-scheme:light}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){
 --paper:#0B0F0D;--paper2:#101612;--card:#111814;--ink:#ECE7DC;--ink2:#B7B2A6;--dim:#868B84;
 --line:#24302A;--grid:#151D18;--copper:#E68A4E;--mask:#5CC79A;--maskbg:#5CC79A14;
 --must:#F0776C;--should:#E5A54B;--may:#82B3E2;--good:#5CC79A;--bad:#F0776C;
 --code:#070A08;--codeline:#1A221D;color-scheme:dark}}
:root[data-theme="dark"]{
 --paper:#0B0F0D;--paper2:#101612;--card:#111814;--ink:#ECE7DC;--ink2:#B7B2A6;--dim:#868B84;
 --line:#24302A;--grid:#151D18;--copper:#E68A4E;--mask:#5CC79A;--maskbg:#5CC79A14;
 --must:#F0776C;--should:#E5A54B;--may:#82B3E2;--good:#5CC79A;--bad:#F0776C;
 --code:#070A08;--codeline:#1A221D;color-scheme:dark}
*{box-sizing:border-box}
html{scroll-behavior:smooth;scroll-padding-top:5rem}
body{margin:0;color:var(--ink);font:16px/1.65 var(--body);background-color:var(--paper);
 background-image:linear-gradient(var(--grid) 1px,transparent 1px),
  linear-gradient(90deg,var(--grid) 1px,transparent 1px);
 background-size:28px 28px;background-attachment:fixed}
a{color:inherit}
code{font-family:var(--mono);font-size:.86em;background:var(--paper2);border:1px solid var(--line);
 border-radius:4px;padding:.05em .3em}
.wrap{max-width:1200px;margin:0 auto;padding:0 2rem}
/* ---- top bar ---- */
.top{position:sticky;top:0;z-index:20;background:color-mix(in srgb,var(--paper) 88%,transparent);
 backdrop-filter:blur(10px);border-bottom:1px solid var(--line)}
.top .wrap{display:flex;align-items:center;gap:1.5rem;height:3.6rem}
.brand{display:flex;align-items:center;gap:.55rem;font-family:var(--mono);font-weight:600;
 font-size:.92rem;text-decoration:none;white-space:nowrap}
.brand svg{width:26px;height:26px}
.nav{display:flex;gap:.2rem;overflow-x:auto;scrollbar-width:none;flex:1;min-width:0}
.nav a{font-size:.83rem;text-decoration:none;color:var(--ink2);padding:.3rem .65rem;
 border-radius:99px;white-space:nowrap}
.nav a:hover{color:var(--ink);background:var(--paper2)}
.nav a.on{color:var(--paper);background:var(--ink)}
.icon-btn{border:1px solid var(--line);background:var(--card);color:var(--ink2);border-radius:8px;
 height:2.1rem;min-width:2.1rem;display:grid;place-items:center;cursor:pointer;text-decoration:none;
 font:500 .8rem var(--body);padding:0 .6rem}
.icon-btn:hover{color:var(--ink);border-color:var(--ink2)}
/* ---- hero ---- */
.hero{display:grid;grid-template-columns:1.05fr minmax(0,1fr);gap:3.5rem;align-items:center;
 padding:5rem 0 4rem}
.eyebrow{font-family:var(--mono);font-size:.76rem;letter-spacing:.12em;text-transform:uppercase;
 color:var(--copper);display:flex;gap:.6rem;align-items:center}
.eyebrow:before{content:"";width:1.8rem;height:1px;background:currentColor}
h1{font-family:var(--display);font-weight:500;font-size:clamp(2.6rem,5.2vw,4.3rem);line-height:1.02;
 letter-spacing:-.025em;margin:1rem 0 1.3rem;font-variation-settings:"opsz" 144}
h1 em{font-style:italic;color:var(--mask);font-weight:400}
.lede{font-size:1.12rem;color:var(--ink2);max-width:36rem;margin:0}
.cta{display:flex;gap:.7rem;flex-wrap:wrap;margin:2rem 0 0}
.btn{display:inline-flex;align-items:center;gap:.5rem;padding:.7rem 1.1rem;border-radius:10px;
 font-weight:600;font-size:.92rem;text-decoration:none;border:1px solid var(--ink)}
.btn.solid{background:var(--ink);color:var(--paper)}
.btn.solid:hover{background:var(--mask);border-color:var(--mask)}
.btn.ghost:hover{background:var(--card)}
.stats{display:grid;grid-template-columns:repeat(4,1fr);margin:2.6rem 0 0;
 border-top:1px solid var(--line)}
.stats div{padding:1rem 0 0}
.stats b{display:block;font-family:var(--display);font-size:2.1rem;font-weight:500;line-height:1}
.stats span{font-size:.75rem;color:var(--dim);letter-spacing:.04em}
.scope{background:var(--code);border-radius:16px;padding:1.1rem 1.1rem .9rem;color:var(--codefg);
 box-shadow:0 30px 60px -30px #0007,0 0 0 1px #ffffff10 inset;position:relative}
.scope-head{display:flex;justify-content:space-between;font-family:var(--mono);font-size:.7rem;
 color:var(--codedim);margin-bottom:.7rem;letter-spacing:.04em}
.scope-head i{font-style:normal;color:var(--ck)}
.scope svg{width:100%;height:auto;display:block}
.scope figcaption{font-size:.74rem;color:var(--codedim);margin-top:.6rem;line-height:1.5}
.wave .lbl{font:500 11px var(--mono);fill:#C9C4B8}
.wave .grid{stroke:#ffffff14;stroke-dasharray:2 4}
.wave .tr{fill:none;stroke:var(--cn);stroke-width:1.6;stroke-linejoin:round;
 stroke-dasharray:1;stroke-dashoffset:1;animation:draw 1.6s cubic-bezier(.6,0,.2,1) forwards;
 animation-delay:calc(var(--i)*.18s + .2s)}
.wave .clk{stroke:#E7E2D6}
.wave .bus{fill:#5CC79A1F;stroke:var(--cn);stroke-width:1.3;opacity:0;
 animation:fade .5s ease forwards;animation-delay:calc(var(--i)*.18s + .9s)}
.wave .bus.x{fill:url(#hatch);stroke:#ffffff33}
.wave .val{font:600 10.5px var(--mono);fill:#E7E2D6;text-anchor:middle;opacity:0;
 animation:fade .5s ease forwards;animation-delay:calc(var(--i)*.18s + 1.1s)}
.wave .mark{stroke:var(--ck);stroke-width:1.3;stroke-dasharray:3 3}
.wave .note{font:500 10px var(--mono);fill:var(--ck)}
.wave .sweep{stroke:var(--ck);stroke-width:1;opacity:.55;animation:sweep 7s linear 2.4s infinite}
@keyframes draw{to{stroke-dashoffset:0}}
@keyframes fade{to{opacity:1}}
@keyframes sweep{from{transform:translateX(0)}to{transform:translateX(var(--span))}}
@keyframes rise{from{opacity:0;transform:translateY(14px)}to{opacity:1;transform:none}}
.hero>*{animation:rise .8s cubic-bezier(.2,.7,.2,1) both}
.hero>*:nth-child(2){animation-delay:.15s}
/* ---- sections ---- */
section{padding:5.5rem 0 1rem}
.sec-head{display:grid;grid-template-columns:7rem minmax(0,1fr);gap:1rem;margin-bottom:2.4rem}
.sec-no{font-family:var(--mono);color:var(--copper);font-size:.85rem;padding-top:.9rem;
 border-top:2px solid var(--copper)}
h2{font-family:var(--display);font-weight:500;font-size:clamp(2rem,3.4vw,2.8rem);line-height:1.08;
 letter-spacing:-.02em;margin:0 0 .8rem;font-variation-settings:"opsz" 144}
.sec-head p{margin:0;color:var(--ink2);max-width:44rem;font-size:1.04rem}
h3{font-family:var(--display);font-weight:500;font-size:1.45rem;letter-spacing:-.01em;
 margin:3rem 0 1rem}
h4{font-size:.98rem;margin:0 0 .4rem}
.muted{color:var(--dim)}
.small{font-size:.86rem}
.grid2{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:1.2rem}
.grid3{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:1.2rem}
.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:1.4rem 1.5rem}
.card p{margin:.3rem 0 0;color:var(--ink2);font-size:.94rem}
/* ---- code ---- */
.code{background:var(--code);border-radius:11px;overflow:hidden;margin:.9rem 0 0;
 box-shadow:0 0 0 1px #ffffff0c inset}
.code-head{display:flex;justify-content:space-between;align-items:center;
 padding:.45rem .5rem .45rem .9rem;
 border-bottom:1px solid var(--codeline);font:500 .7rem var(--mono);color:var(--codedim);
 letter-spacing:.03em}
.copy{font:500 .68rem var(--mono);color:var(--codedim);background:none;
 border:1px solid var(--codeline);
 border-radius:6px;padding:.2rem .5rem;cursor:pointer}
.copy:hover{color:var(--codefg);border-color:var(--codedim)}
.copy.ok{color:var(--cn);border-color:var(--cn)}
pre{margin:0;padding:.85rem .95rem;font:13px/1.6 var(--mono);color:var(--codefg);overflow-x:auto;
 white-space:pre;tab-size:4}
pre .k{color:var(--ck)}pre .cm{color:var(--cc);font-style:italic}pre .num{color:var(--cn)}
pre .mac,pre .sys{color:var(--cm)}pre .str{color:var(--cs)}
/* ---- quick start ---- */
.steps{counter-reset:s;display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:1.2rem}
.step{position:relative;padding-top:3.2rem}
.step:before{counter-increment:s;content:"0" counter(s);position:absolute;top:1.1rem;left:1.5rem;
 font:600 .8rem var(--mono);color:var(--copper)}
.prompts{display:flex;flex-direction:column;gap:.5rem;margin:.9rem 0 0;padding:0;list-style:none}
.prompts li{background:var(--paper);border:1px solid var(--line);border-radius:10px;
 padding:.55rem .8rem;
 font-size:.9rem;position:relative;padding-left:2rem}
.prompts li:before{content:"›";position:absolute;left:.85rem;color:var(--copper);font-weight:700}
/* ---- skill flow ---- */
.flow{list-style:none;margin:0;padding:0;position:relative}
.flow:before{content:"";position:absolute;left:1.35rem;top:1rem;bottom:1rem;width:2px;
 background:repeating-linear-gradient(var(--line) 0 6px,transparent 6px 12px)}
.flow>li{display:grid;grid-template-columns:2.7rem minmax(0,1fr) 1.15fr;gap:1.4rem;
 align-items:start;
 padding:1.1rem 0;position:relative}
.flow .dot{width:2.7rem;height:2.7rem;border-radius:50%;background:var(--card);
 border:2px solid var(--ink);
 display:grid;place-items:center;font:600 .8rem var(--mono);position:relative;z-index:1}
.flow>li.tool .dot{background:var(--ink);color:var(--paper)}
.flow h4{font-family:var(--display);font-weight:500;font-size:1.25rem;margin:.35rem 0 .3rem}
.flow p{margin:0;color:var(--ink2);font-size:.94rem}
.flow .code{margin:0}
.flow .side{font-size:.88rem;color:var(--ink2);padding-top:.4rem}
.flow .side ul{margin:0;padding-left:1.1rem}
.tag{display:inline-block;font:600 .64rem var(--mono);letter-spacing:.08em;text-transform:uppercase;
 padding:.12rem .45rem;border-radius:4px;background:var(--maskbg);color:var(--mask);
 vertical-align:middle}
.checks{list-style:none;padding:0;margin:.6rem 0 0}
.checks li{padding:.45rem 0 .45rem 1.9rem;position:relative;border-bottom:1px dashed var(--line);
 font-size:.93rem}
.checks li:last-child{border:none}
.checks li:before{content:"";position:absolute;left:0;top:.62rem;width:1.05rem;height:1.05rem;
 border-radius:4px;border:1.5px solid var(--mask);background:
 linear-gradient(45deg,transparent 45%,var(--mask) 45% 55%,transparent 55%) no-repeat}
table{width:100%;border-collapse:collapse;font-size:.92rem}
th{text-align:left;font:600 .7rem var(--mono);letter-spacing:.08em;text-transform:uppercase;
 color:var(--dim);
 padding:.6rem .8rem;border-bottom:1.5px solid var(--ink)}
td{padding:.65rem .8rem;border-bottom:1px solid var(--line);vertical-align:top}
tr:last-child td{border-bottom:none}
.tbl{background:var(--card);border:1px solid var(--line);border-radius:14px;overflow-x:auto;
 padding:.3rem .4rem}
.callout{border-left:3px solid var(--copper);background:var(--card);border-radius:0 14px 14px 0;
 padding:1.3rem 1.5rem;margin:2rem 0 0;border-top:1px solid var(--line);
 border-right:1px solid var(--line);
 border-bottom:1px solid var(--line)}
.callout h4{font-family:var(--display);font-weight:500;font-size:1.2rem}
/* ---- house style ---- */
.pillar{position:relative;overflow:hidden}
.pillar .big{font:500 3.2rem/1 var(--display);color:var(--paper2);position:absolute;right:1rem;
 top:.6rem;
 letter-spacing:-.03em;-webkit-text-stroke:1px var(--line)}
.pillar h4{font-family:var(--display);font-size:1.18rem;font-weight:500;position:relative;
 margin-top:.2rem}
.pillar .ids{margin-top:.8rem}
.sev-legend{display:grid;grid-template-columns:repeat(auto-fit,minmax(14rem,1fr));gap:1.2rem;
 margin-top:1.2rem}
.sev-legend .card{border-top:3px solid currentColor}
.sev-legend b{font:600 .85rem var(--mono);letter-spacing:.08em}
.anat{display:grid;grid-template-columns:minmax(0,1.35fr) minmax(0,1fr);gap:1.4rem;
 align-items:start}
.anat .code{margin:0;position:sticky;top:4.6rem}
.anat pre{font-size:12.3px;padding:.7rem 0;max-height:calc(100vh - 8rem);overflow:auto}
.anat .ln{display:block;padding:0 .9rem 0 3.1rem;position:relative;transition:background .2s}
.anat .ln:before{content:attr(data-n);position:absolute;left:0;width:2.2rem;text-align:right;
 color:#4E545C}
.anat .ln.hl{background:#E68A4E26}
.pin{display:inline-grid;place-items:center;width:1.25rem;height:1.25rem;border-radius:50%;
 background:var(--ck);color:#16181D;font:700 .62rem var(--mono);margin-left:.6rem;
 vertical-align:1px}
.notes{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:.55rem}
.notes li{background:var(--card);border:1px solid var(--line);border-radius:11px;
 padding:.7rem .9rem;
 display:grid;grid-template-columns:1.4rem minmax(0,1fr);gap:.7rem;font-size:.9rem;cursor:default;
 transition:border-color .2s}
.notes li:hover,.notes li.hl{border-color:var(--copper)}
.notes .pin{margin:.15rem 0 0;background:var(--copper);color:var(--paper)}
.notes p{margin:0;color:var(--ink2)}
.chip{display:inline-block;font:600 .7rem var(--mono);padding:.12rem .45rem;border-radius:5px;
 border:1px solid var(--line);background:var(--paper);text-decoration:none;
 margin:.15rem .2rem 0 0;color:var(--ink2)}
a.chip:hover{border-color:var(--copper);color:var(--copper)}
.chip.MUST{border-color:color-mix(in srgb,var(--must) 45%,transparent);color:var(--must)}
.chip.SHOULD{border-color:color-mix(in srgb,var(--should) 45%,transparent);color:var(--should)}
.chip.MAY{border-color:color-mix(in srgb,var(--may) 45%,transparent);color:var(--may)}
/* ---- rules catalogue ---- */
.tiles{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:.7rem}
.tile{all:unset;box-sizing:border-box;cursor:pointer;background:var(--card);
 border:1px solid var(--line);
 border-radius:12px;padding:.85rem .95rem;display:flex;flex-direction:column;gap:.2rem;
 transition:all .2s}
.tile:hover{border-color:var(--ink2);transform:translateY(-2px)}
.tile.on{border-color:var(--ink);box-shadow:0 0 0 1px var(--ink) inset}
.tile b{font:600 .95rem var(--mono)}
.tile span{font-size:.8rem;color:var(--ink2);line-height:1.35;min-height:2.2em}
.tile .meter{display:flex;height:4px;border-radius:2px;overflow:hidden;margin-top:.45rem;
 background:var(--paper2)}
.meter i{display:block}.meter .m{background:var(--must)}
.meter .s{background:var(--should)}.meter .y{background:var(--may)}
.tile small{font:500 .68rem var(--mono);color:var(--dim)}
.bar{position:sticky;top:3.6rem;z-index:10;background:color-mix(in srgb,var(--paper) 92%,
 transparent);
 backdrop-filter:blur(10px);padding:.9rem 0;margin:1.6rem 0 1rem;
 border-bottom:1px solid var(--line)}
.bar .row{display:flex;gap:.4rem;flex-wrap:wrap;align-items:center}
.bar .row+.row{margin-top:.55rem}
.bar label{font:600 .66rem var(--mono);letter-spacing:.08em;text-transform:uppercase;
 color:var(--dim);margin-right:.3rem}
.fbtn{font:500 .78rem var(--body);padding:.28rem .7rem;border:1px solid var(--line);
 border-radius:99px;
 background:var(--card);color:var(--ink2);cursor:pointer}
.fbtn:hover{color:var(--ink);border-color:var(--ink2)}
.fbtn.on{background:var(--ink);color:var(--paper);border-color:var(--ink)}
#q{flex:1;min-width:14rem;font:inherit;font-size:.92rem;padding:.55rem .9rem;
 border:1px solid var(--line);
 border-radius:10px;background:var(--card);color:var(--ink)}
#q:focus{outline:2px solid var(--copper);outline-offset:1px}
.count{font:500 .76rem var(--mono);color:var(--dim);margin-left:auto}
.cat-h{display:flex;align-items:baseline;gap:.8rem;margin:2.6rem 0 .9rem;font-family:var(--display);
 font-weight:500;font-size:1.5rem}
.cat-h b{font:600 .8rem var(--mono);color:var(--copper)}
.rule{background:var(--card);border:1px solid var(--line);border-radius:13px;margin-bottom:.6rem;
 display:grid;grid-template-columns:7.4rem minmax(0,1fr);overflow:hidden;
 transition:border-color .3s,
 box-shadow .3s}
.rule:target,.rule.flash{border-color:var(--copper);box-shadow:0 0 0 3px color-mix(in srgb,
 var(--copper) 25%,transparent)}
.r-id{padding:1rem 0 1rem 1.1rem;display:flex;flex-direction:column;gap:.45rem;
 align-items:flex-start;
 border-right:1px dashed var(--line)}
.rid{font:600 .95rem var(--mono);color:var(--ink);background:none;border:none;padding:0;
 cursor:pointer}
.rid:hover{color:var(--copper)}
.pill{font:700 .6rem var(--mono);letter-spacing:.09em;padding:.14rem .45rem;border-radius:4px;
 border:1px solid currentColor}
.sev-MUST{color:var(--must)}.sev-SHOULD{color:var(--should)}.sev-MAY{color:var(--may)}
.fix{font:600 .62rem var(--mono);letter-spacing:.06em;color:var(--good);background:var(--maskbg);
 padding:.14rem .4rem;border-radius:4px}
.r-body{padding:1rem 1.3rem 1rem 1.2rem;min-width:0}
.rt{font-family:var(--display);font-weight:500;font-size:1.13rem;margin:0}
.stm{margin:.3rem 0 0;color:var(--ink2);font-size:.94rem}
.enf{margin:.6rem 0 0;font:500 .72rem var(--mono);color:var(--dim)}
.enf b{color:var(--ink2);font-weight:600}
details.more summary{cursor:pointer;font-size:.8rem;font-weight:600;color:var(--copper);
 margin-top:.6rem;
 list-style:none;display:inline-flex;gap:.35rem;align-items:center}
details.more summary::-webkit-details-marker{display:none}
details.more summary:before{content:"+";font:600 .9rem var(--mono);width:.9rem}
details.more[open] summary:before{content:"\\2212"}
.why{margin:.6rem 0 0;font-size:.92rem;color:var(--ink2)}
.ex{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:.6rem;margin-top:.8rem}
.ex.stack{grid-template-columns:minmax(0,1fr)}
.ex .code{margin:0}
.ex .good .code-head{color:var(--cn)}.ex .bad .code-head{color:#F0776C}
.src{margin:.7rem 0 0;font-size:.75rem;color:var(--dim)}
.hidden{display:none!important}
#none{color:var(--dim);padding:2rem 0;text-align:center}
/* ---- tools ---- */
.split{display:flex;height:2.6rem;border-radius:10px;overflow:hidden;border:1px solid var(--line);
 margin:.4rem 0 .8rem}
.split div{display:flex;align-items:center;justify-content:center;font:600 .72rem var(--mono);
 color:#fff;
 min-width:0;white-space:nowrap;overflow:hidden}
.legend{display:flex;flex-wrap:wrap;gap:.4rem 1.2rem;font-size:.8rem;color:var(--ink2)}
.legend i{display:inline-block;width:.7rem;height:.7rem;border-radius:3px;margin-right:.4rem;
 vertical-align:-1px}
.tools{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:1.2rem;margin-top:2rem}
.tool-card{display:flex;flex-direction:column;gap:.2rem}
.tool-card header{display:flex;align-items:center;gap:.7rem;margin-bottom:.3rem}
.tool-card .sw{width:.85rem;height:.85rem;border-radius:3px;flex:none}
.tool-card h4{font:600 1.05rem var(--mono);margin:0}
.tool-card .kind{margin-left:auto;font:500 .66rem var(--mono);letter-spacing:.07em;
 text-transform:uppercase;color:var(--dim)}
.tool-card dl{display:grid;grid-template-columns:5.2rem minmax(0,1fr);gap:.35rem .8rem;
 margin:.9rem 0 0;
 font-size:.86rem}
.tool-card dt{font:600 .66rem var(--mono);letter-spacing:.07em;text-transform:uppercase;
 color:var(--dim);padding-top:.2rem}
.tool-card dd{margin:0;color:var(--ink2)}
.tool-card.wide{grid-column:1/-1}
/* ---- footer ---- */
footer{margin-top:6rem;border-top:1px solid var(--line);padding:2.4rem 0 3rem;font-size:.85rem;
 color:var(--dim)}
footer .wrap{display:flex;justify-content:space-between;gap:1rem;flex-wrap:wrap}
@media (max-width:980px){
 .hero,.anat,.grid2,.tools,.steps{grid-template-columns:minmax(0,1fr)}
.grid3{grid-template-columns:minmax(0,1fr) minmax(0,1fr)}
 .anat .code{position:static}.flow>li{grid-template-columns:2.7rem minmax(0,1fr)}
.flow .side{grid-column:2}
 .hero{padding-top:3rem}}
@media (max-width:640px){
 .wrap{padding:0 1rem}.grid3,.sev-legend,
 .ex{grid-template-columns:minmax(0,1fr)}.stats{grid-template-columns:minmax(0,1fr) minmax(0,1fr)}
 .sec-head{grid-template-columns:minmax(0,1fr)}.sec-no{width:4rem}
.rule{grid-template-columns:minmax(0,1fr)}
 .r-id{flex-direction:row;align-items:center;border-right:none;
 border-bottom:1px dashed var(--line);padding:.8rem 1.1rem}
 .top .wrap{gap:.6rem}.brand span{display:none}.bar{top:3.6rem}}
@media (prefers-reduced-motion:reduce){*,*:before{animation:none!important;
 transition:none!important}
 .wave .tr{stroke-dashoffset:0}.wave .bus,.wave .val{opacity:1}html{scroll-behavior:auto}}
"""

JS = """
const $=(s,r=document)=>r.querySelector(s),$$=(s,r=document)=>[...r.querySelectorAll(s)];
// Theme: follows the OS until the reader picks one.
const root=document.documentElement;
$('#theme').onclick=()=>{
  const dark=root.dataset.theme?root.dataset.theme==='dark'
    :matchMedia('(prefers-color-scheme:dark)').matches;
  root.dataset.theme=dark?'light':'dark';
  try{localStorage.setItem('theme',root.dataset.theme);}catch(e){}
};
// Rule filters.
const rules=$$('.rule');
const state={cat:'',sev:'',tool:'',q:''};
function apply(){
  let n=0;
  for(const el of rules){
    const ok=(!state.cat||el.dataset.cat===state.cat)&&(!state.sev||el.dataset.sev===state.sev)
      &&(!state.tool||el.dataset.tool.split(' ').includes(state.tool))
      &&(!state.q||el.dataset.text.includes(state.q));
    el.classList.toggle('hidden',!ok);n+=ok?1:0;
  }
  for(const h of $$('.cat-h'))
    h.classList.toggle('hidden',!rules.some(e=>e.dataset.cat===h.dataset.cat&&!e.classList.contains('hidden')));
  $('#none').classList.toggle('hidden',n>0);
  $('#shown').textContent=n;
}
function set(k,v){
  state[k]=v;
  for(const o of $$('[data-k="'+k+'"]'))o.classList.toggle('on',v!==''&&o.dataset.v===v);
  apply();
}
for(const b of $$('[data-k]'))b.onclick=()=>{
  set(b.dataset.k,state[b.dataset.k]===b.dataset.v?'':b.dataset.v);
  if(b.classList.contains('tile'))$('#catalogue').scrollIntoView();
};
// Normalise the query exactly as the index was built, so punctuation still matches.
const norm=s=>s.toLowerCase().replace(/[^a-z0-9 _-]+/g,' ');
$('#q').oninput=e=>{state.q=norm(e.target.value).trim();apply();};
$('#reset').onclick=()=>{$('#q').value='';state.q='';for(const k of['cat','sev','tool'])set(k,'');};
$('#expand').onclick=e=>{
  const open=e.target.dataset.open!=='1';e.target.dataset.open=open?'1':'0';
  e.target.textContent=open?'Collapse all':'Expand all';
  for(const d of $$('.rule details'))d.open=open;
};
for(const b of $$('.rid'))b.onclick=()=>{navigator.clipboard?.writeText(b.textContent);
  b.dataset.t=b.textContent;b.textContent='copied';setTimeout(()=>b.textContent=b.dataset.t,900);};
// A link to a rule clears whatever hides it, opens it and points at it.
function reveal(id){
  const el=document.getElementById(id);if(!el||!el.classList.contains('rule'))return false;
  if(el.classList.contains('hidden')){$('#reset').click();}
  const d=$('details',el);if(d)d.open=true;
  el.scrollIntoView({block:'center'});el.classList.add('flash');
  setTimeout(()=>el.classList.remove('flash'),1600);return true;
}
document.addEventListener('click',e=>{
  const a=e.target.closest('a[href^="#"]');if(!a)return;
  if(reveal(a.getAttribute('href').slice(1))){e.preventDefault();history.replaceState(null,'',a.hash);}
});
if(location.hash)setTimeout(()=>reveal(location.hash.slice(1)),50);
// Copy buttons on code blocks.
for(const b of $$('.copy'))b.onclick=()=>{
  navigator.clipboard?.writeText($('pre',b.closest('.code')).innerText.trim());
  b.textContent='copied';b.classList.add('ok');
  setTimeout(()=>{b.textContent='copy';b.classList.remove('ok');},1200);
};
// Template anatomy: a note lights its line.
for(const li of $$('.notes li')){
  const line=$('.ln[data-n="'+li.dataset.line+'"]');if(!line)continue;
  li.onmouseenter=()=>{line.classList.add('hl');line.scrollIntoView({block:'nearest'});};
  li.onmouseleave=()=>line.classList.remove('hl');
}
// Scroll-spy for the top navigation.
const links=$$('.nav a');
const io=new IntersectionObserver(es=>{for(const e of es)if(e.isIntersecting)
  for(const a of links)a.classList.toggle('on',a.hash==='#'+e.target.id);},
  {rootMargin:'-45% 0px -50% 0px'});
for(const s of $$('section[id]'))io.observe(s);
apply();
"""

# The SystemVerilog keywords the highlighter colours; anything else is a name.
_KEYWORDS = (
    "always always_comb always_ff always_latch and assign automatic begin bit byte case "
    "casez default else end endcase endfunction endgenerate endmodule endpackage endtask "
    "enum for function generate genvar if import inout input int integer localparam logic "
    "module negedge or output package parameter posedge priority reg return signed struct "
    "task typedef unique unique0 unsigned wire"
)
SV_KEYWORDS = frozenset(_KEYWORDS.split())
_TOKEN = re.compile(
    r"(?P<cm>//[^\n]*|/\*.*?\*/)|(?P<str>\"[^\"\n]*\")|(?P<mac>`\w+)|(?P<sys>\$\w+)"
    r"|(?P<num>\b\d*'[sS]?[bodhBODH][0-9a-fA-F_xXzZ?]+|\b\d+\b)|(?P<id>\b[A-Za-z_]\w*\b)",
    re.S,
)


def _esc(text: str) -> str:
    return html.escape(text, quote=True)


def _hl(code: str, lang: str = "sv") -> str:
    """Escape `code` and colour it: SystemVerilog tokens, or `#` comments for shell/TOML."""
    if lang != "sv":
        return re.sub(r"(?m)(^|\s)(#.*)$", r'\1<span class="cm">\2</span>', _esc(code))
    out, pos = [], 0
    for m in _TOKEN.finditer(code):
        out.append(_esc(code[pos : m.start()]))
        kind, text = m.lastgroup, m.group()
        if kind == "id":
            out.append(f'<span class="k">{text}</span>' if text in SV_KEYWORDS else text)
        else:
            out.append(f'<span class="{kind}">{_esc(text)}</span>')
        pos = m.end()
    return "".join(out) + _esc(code[pos:])


def _code(text: str, title: str, lang: str = "sv", cls: str = "") -> str:
    return (
        f'<div class="code {cls}"><div class="code-head"><span>{_esc(title)}</span>'
        f'<button class="copy">copy</button></div><pre>{_hl(text.strip(chr(10)), lang)}</pre></div>'
    )


def _md(text: str) -> str:
    """Inline Markdown as rules.toml writes it: ``double`` and `single` backtick code."""
    text = _esc(text)
    text = re.sub(r"``\s?(.+?)\s?``", r"<code>\1</code>", text)
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", text)


def _chips(ids, by_id: dict) -> str:
    return "".join(
        f'<a class="chip {by_id[i].severity}" href="#{i}">{i}</a>' if i in by_id else ""
        for i in ids
    )


def _wave_svg() -> str:
    """`assets/skeleton.sv` simulated by hand: the hero's timing diagram."""
    w, h, left, n, pitch = 52, 20, 74, 11, 38  # cycle width, trace height, labels, cycles
    rst_rise = 1.3  # rst_ni deasserts mid-cycle: it is asynchronous
    valid_i = [0, 0, 1, 1, 0, 1, 0, 1, 1, 0, 0]
    data_i = [None, None, "A0", "3F", None, "7C", None, "12", "E5", None, None]
    # valid_q is reset; data_q is not, so it is X until the first valid input lands.
    valid_o, data_o, held = [0], ["X"], "X"
    for k in range(n - 1):
        valid_o.append(valid_i[k] if k + 1 > rst_rise else 0)
        held = data_i[k] if valid_i[k] else held
        data_o.append(held)

    end = left + n * w
    parts = []

    def bits(vals, y, skew, i, extra=""):
        lvl = lambda v: y if v else y + h  # noqa: E731
        d = f"M{left},{lvl(vals[0])}"
        for k in range(1, n):
            if vals[k] != vals[k - 1]:
                d += f" H{left + k * w + skew} V{lvl(vals[k])}"
        parts.append(f'<path class="tr {extra}" style="--i:{i}" pathLength="1" d="{d} H{end}"/>')

    def bus(vals, y, skew, i):
        k0 = 0
        for k in range(1, n + 1):
            if k < n and vals[k] == vals[k0]:
                continue
            x0 = left + (k0 * w + skew if k0 else 0)
            x1 = left + (k * w + skew if k < n else n * w)
            v, s, ym = vals[k0], 4, y + h / 2
            pts = f"{x0},{ym} {x0 + s},{y} {x1 - s},{y} {x1},{ym} {x1 - s},{y + h} {x0 + s},{y + h}"
            cls = "bus" if v not in (None, "X") else "bus x"
            parts.append(f'<polygon class="{cls}" style="--i:{i}" points="{pts}"/>')
            if v not in (None, "X"):
                parts.append(
                    f'<text class="val" style="--i:{i}" x="{(x0 + x1) / 2}" y="{ym + 3.6}">'
                    f"{v}</text>"
                )
            k0 = k

    rows = ["clk_i", "rst_ni", "valid_i", "data_i", "valid_o", "data_o"]
    top = 26
    for k in range(n + 1):
        x = left + k * w
        parts.append(
            f'<line class="grid" x1="{x}" y1="{top - 6}" x2="{x}" y2="{top + 6 * pitch - 12}"/>'
        )
    for i, name in enumerate(rows):
        y = top + i * pitch
        parts.append(f'<text class="lbl" x="0" y="{y + h / 2 + 4}">{name}</text>')
    y = [top + i * pitch for i in range(6)]
    clk = f"M{left},{y[0] + h}" + f" V{y[0]} h{w / 2} V{y[0] + h} h{w / 2}" * n
    parts.append(f'<path class="tr clk" style="--i:0" pathLength="1" d="{clk}"/>')
    rst = f"M{left},{y[1] + h} H{left + rst_rise * w} V{y[1]} H{end}"
    parts.append(f'<path class="tr" style="--i:1" pathLength="1" d="{rst}"/>')
    bits(valid_i, y[2], 5, 2)
    bus(data_i, y[3], 5, 3)
    bits(valid_o, y[4], 3, 4)
    bus(data_o, y[5], 3, 5)
    # Point at the edge that captures A0, and at the cycle it appears on data_o.
    mx = left + 3 * w
    parts.append(f'<line class="mark" x1="{mx}" y1="{top - 10}" x2="{mx}" y2="{y[5] + h + 4}"/>')
    parts.append(
        f'<text class="note" x="{mx + 6}" y="{top - 12}">A0 captured → data_o next cycle</text>'
    )
    parts.append(
        f'<line class="sweep" style="--span:{n * w}px" x1="{left}" y1="{top - 6}" '
        f'x2="{left}" y2="{y[5] + h + 6}"/>'
    )
    return (
        f'<svg class="wave" viewBox="0 -4 {end + 4} {y[5] + h + 14}" role="img" '
        'aria-label="Timing diagram of the skeleton template: valid and data are registered '
        'one cycle after the input; the payload is not reset">'
        '<defs><pattern id="hatch" width="5" height="5" patternUnits="userSpaceOnUse" '
        'patternTransform="rotate(45)"><line x1="0" y1="0" x2="0" y2="5" stroke="#ffffff30" '
        'stroke-width="1.4"/></pattern></defs>' + "".join(parts) + "</svg>"
    )


# What each line of the skeleton template demonstrates, found by its text so the
# notes follow the template when it changes; a note whose text is gone is dropped.
ANATOMY = [
    (
        "// Copyright",
        ["DOC-001", "DOC-002"],
        "Every file opens with the copyright block and a <code>Description:</code> that names the "
        "non-obvious constraints. <code>svstyle fix</code> fills <code>&lt;Company&gt;</code> from "
        "<code>.svstyle.toml</code>.",
    ),
    (
        "`default_nettype none",
        ["LNG-014"],
        "A typo in a net name is an error, not a new implicit wire. The file ends with "
        "<code>`resetall</code>.",
    ),
    (
        "parameter int unsigned Width",
        ["NAM-006", "LNG-011", "DOC-003"],
        "Typed parameter, <code>UpperCamelCase</code>, with a trailing comment that says what it "
        "means and its legal range.",
    ),
    (
        "clk_i,",
        ["PRT-001", "PRT-002", "NAM-002"],
        "ANSI ports, one per line: clock first, then reset, then the rest. Every port ends in its "
        "direction: <code>_i</code>, <code>_o</code>, <code>_io</code>.",
    ),
    (
        "rst_ni,",
        ["RST-001", "NAM-003"],
        "Asynchronous, active-low reset. Suffixes stack in a fixed order: <code>_n</code> before "
        "<code>_i</code>.",
    ),
    (
        "// Payload on data_i",
        ["DOC-003", "FMT-002"],
        "A trailing comment on every port: meaning and validity, not type or direction. Verible "
        "aligns the columns.",
    ),
    (
        "gen_width_check",
        ["GEN-003", "GEN-001"],
        "An illegal parameter fails at elaboration, in a labelled <code>gen_</code> block.",
    ),
    (
        "logic valid_q, valid_d;",
        ["NAM-004", "DOC-004", "LNG-001"],
        "<code>logic</code> everywhere. A flop is <code>_q</code>; its computed next value "
        "<code>_d</code>. Every declaration carries a comment.",
    ),
    (
        "always_comb begin",
        ["DOC-005", "LNG-003", "LNG-006"],
        "A comment line above every block. <code>always_comb</code> with blocking assignments, and "
        "a default for every output so no latch is inferred.",
    ),
    (
        "always_ff @(posedge clk_i or negedge rst_ni)",
        ["LNG-002", "RST-001", "FMT-003"],
        "<code>always_ff</code> with nonblocking assignments, async reset in the sensitivity list, "
        "<code>begin</code>/<code>end</code> always written.",
    ),
    (
        "// Payload register, no reset",
        ["RST-004"],
        "Only control state is reset. The payload is qualified by <code>valid</code>, "
        "so a reset on "
        "it would only cost area and routing.",
    ),
    (
        "`ASSERT_KNOWN",
        ["VER-001", "VER-002"],
        "Outputs are checked for X through the standard macros, which compile to nothing under "
        "synthesis.",
    ),
]


def _anatomy(example: str, by_id: dict) -> str:
    lines = example.rstrip("\n").split("\n")
    pins, notes, used = {}, [], set()
    for needle, ids, note in ANATOMY:
        at = next((i for i, ln in enumerate(lines) if needle in ln and i not in used), None)
        if at is None:
            continue
        used.add(at)
        num = len(notes) + 1
        pins[at] = num
        notes.append(
            f'<li data-line="{at + 1}"><span class="pin">{num}</span><div><p>{note}</p>'
            f"<div>{_chips(ids, by_id)}</div></div></li>"
        )
    body = "".join(
        f'<span class="ln" data-n="{i + 1}">{_hl(ln) or " "}'
        + (f'<span class="pin">{pins[i]}</span>' if i in pins else "")
        + "</span>"
        for i, ln in enumerate(lines)
    )
    return (
        '<div class="anat"><div class="code"><div class="code-head"><span>assets/skeleton.sv'
        ' — passes svstyle check as shipped</span><button class="copy">copy</button></div>'
        f'<pre>{body}</pre></div><ol class="notes">{"".join(notes)}</ol></div>'
    )


def _card(r: Rule) -> str:
    owners = [r.tool] + [t for t, _ in r.also]
    enforced = f"<b>{TOOL_LABEL[r.tool]}</b>" + (
        f" · {_esc(' '.join(r.tool_rules))}" if r.tool_rules else ""
    )
    for t, codes in r.also:
        enforced += f" — also <b>{TOOL_LABEL[t]}</b> · {_esc(' '.join(codes))}"
    # Strip punctuation rather than escaping it: the raw text would put HTML
    # entities in the attribute, so searching "module's" could never match.
    searchable = re.sub(
        r"[^a-z0-9 _-]+",
        " ",
        " ".join([r.id, r.title, r.statement, r.rationale, *r.tool_rules]).lower(),
    )

    ex = ""
    if r.good or r.bad:
        widest = max((len(ln) for ln in (r.good + "\n" + r.bad).splitlines()), default=0)
        stack = " stack" if widest > 56 else ""
        cells = [
            f'<div class="{kind}">{_code(text, kind)}</div>'
            for kind, text in (("good", r.good), ("bad", r.bad))
            if text
        ]
        ex = f'<div class="ex{stack}">{"".join(cells)}</div>'
    fix = '<span class="fix">AUTOFIX</span>' if r.autofix else ""

    return (
        f'<article class="rule" id="{r.id}" data-cat="{r.category}" data-sev="{r.severity}"'
        f' data-tool="{" ".join(owners)}" data-text="{searchable}">'
        f'<div class="r-id"><button class="rid" title="Copy the rule ID">{r.id}</button>'
        f'<span class="pill sev-{r.severity}">{r.severity}</span>{fix}</div>'
        f'<div class="r-body"><h4 class="rt">{_md(r.title)}</h4>'
        f'<p class="stm">{_md(r.statement)}</p>'
        f'<p class="enf">enforced by {enforced}</p>'
        f'<details class="more"><summary>Why, and examples</summary>'
        f'<p class="why">{_md(r.rationale)}</p>{ex}'
        f'<p class="src">Sources: {_esc(", ".join(r.sources))}</p></details>'
        f"</div></article>"
    )


TOOL_COLOR = {
    "svstyle": "#B4531A",
    "verible-format": "#2D5E8C",
    "verible-lint": "#4F7FB0",
    "verilator": "#0E5A43",
    "yosys": "#7A4E9C",
    "review": "#7B7F86",
}

# One card per enforcer: (kind, what it does, how svstyle runs it, how to get it).
TOOL_INFO = {
    "svstyle": (
        "this repo",
        "The checker and fixer shipped with the skill. It owns the rules no open-source tool "
        "covers — the file header, port and declaration comments, port order, named "
        "connections, reset style — and folds every other tool's output into one report keyed "
        "by house rule IDs.",
        "<code>svstyle check</code> · <code>svstyle fix</code> · <code>svstyle rules</code>",
        "<code>uv tool install svstyle</code> or <code>pipx install svstyle</code>",
    ),
    "verible-format": (
        "external · pinned",
        "CHIPS Alliance's formatter owns layout: indentation, wrapping, and the tabular "
        "alignment of port lists, parameters and named connections. <code>check</code> reports "
        "a file it would change as FMT-002; <code>fix</code> runs it, then verifies that every "
        "token change is one it allows, or writes nothing.",
        "<code>verible-verilog-format</code> with the flags in "
        "<code>src/svstyle/data/verible-format.flags</code>",
        "{verible} from the Verible releases page; another version warns that alignment may "
        "drift. <code>fix</code> refuses to run without it.",
    ),
    "verible-lint": (
        "external · pinned",
        "The style linter: naming, <code>always_comb</code>/<code>always_ff</code> usage, "
        "<code>begin</code>/<code>end</code>, file names, literal widths. Each Verible rule "
        "name maps to the house ID that claims it.",
        "<code>verible-verilog-lint</code> with <code>src/svstyle/data/rules.verible_lint</code>",
        "{verible}, same release as the formatter.",
    ),
    "verilator": (
        "external",
        "<code>--lint-only -Wall</code> over every file of the design at once: widths, latches, "
        "multiple drivers, undriven and unused signals, missing pins. It is also the simulator "
        "for the skill's self-checking testbench step.",
        "<code>verilator --lint-only -Wall</code> (all files together so submodules elaborate)",
        "Verilator 5; CI uses 5.053 from the OSS CAD Suite.",
    ),
    "yosys": (
        "external",
        'Synthesis is the contract. <code>--synth</code>, or <code>synth = "yosys"</code> in '
        "<code>.svstyle.toml</code>, runs <code>read_verilog -sv; hierarchy; proc; check</code>: "
        "combinational loops, conflicting drivers, and whether Yosys reads the code at all "
        '(<code>EXT-YOSYS-read</code>, a MUST). With <code>synth = "yosys-slang"</code> the '
        "read is <code>plugin -i slang; read_slang</code>, which accepts nearly all "
        "synthesizable SystemVerilog. The subset the skill writes is backed by 149 "
        "one-construct probes proved with <code>sat</code>, rerun by CI on both frontends.",
        "<code>yosys</code>, or <code>yosys</code> + the <code>slang</code> plugin",
        "Yosys 0.69 from the OSS CAD Suite (which also ships yosys-slang); Homebrew's Yosys has "
        "no slang plugin.",
    ),
    "review": (
        "Claude + you",
        "What no tool can decide: reset scope, FSM structure, CDC patterns, signed arithmetic, "
        "whether a name says what it means. The skill walks this list before it calls the work "
        "done, and a human reviewer reads the same IDs.",
        "<code>svstyle rules --unmapped</code> lists them",
        "nothing to install",
    ),
}


def _verible() -> str:
    return " or ".join(f"<code>{v}</code>" for v in KNOWN_GOOD_VERIBLE_VERSIONS)


def _tools(rules: list[Rule], by_id: dict) -> str:
    total = len(rules) or 1
    counts = {t: sum(1 for r in rules if r.tool == t) for t in TOOL_INFO}
    split = "".join(
        f'<div style="flex:{c};background:{TOOL_COLOR[t]}" title="{TOOL_LABEL[t]}: {c}">'
        f"{c if c / total > 0.04 else ''}</div>"
        for t, c in counts.items()
        if c
    )
    legend = "".join(
        f'<span><i style="background:{TOOL_COLOR[t]}"></i>{TOOL_LABEL[t]} · {c}</span>'
        for t, c in counts.items()
        if c
    )
    cards = []
    for t, (kind, what, run, get) in TOOL_INFO.items():
        owned = [r.id for r in rules if r.tool == t]
        backs = [r.id for r in rules if any(a == t for a, _ in r.also)]
        get = get.replace("{verible}", _verible())
        rows = f"<dt>runs</dt><dd>{run}</dd><dt>get it</dt><dd>{get}</dd>"
        if owned:
            rows += f"<dt>owns {len(owned)}</dt><dd>{_chips(owned, by_id)}</dd>"
        if backs:
            rows += f"<dt>backs up</dt><dd>{_chips(backs, by_id)}</dd>"
        wide = " wide" if t in ("yosys", "review") else ""
        cards.append(
            f'<div class="card tool-card{wide}"><header><span class="sw" '
            f'style="background:{TOOL_COLOR[t]}"></span><h4>{TOOL_LABEL[t]}</h4>'
            f'<span class="kind">{kind}</span></header><p>{what}</p><dl>{rows}</dl></div>'
        )
    return (
        f'<h4>Who enforces the {len(rules)} rules</h4><div class="split">{split}</div>'
        f'<div class="legend">{legend}</div><div class="tools">{"".join(cards)}</div>'
        '<div class="callout"><h4>Tool findings without a house rule</h4><p class="small">'
        "A Verible or Verilator warning no rule claims passes through as "
        "<code>EXT-VL-&lt;rule&gt;</code> or <code>EXT-VLTR-&lt;CODE&gt;</code> at SHOULD. "
        "<code>EXT-VLTR-ERROR</code> (MUST) means the design did not elaborate: fix it first, "
        "the rest of the report is incomplete. <code>EXT-VLTR-MODMISSING</code> means a "
        "submodule's file was not on the command line. Missing tools are skipped with a "
        "warning by <code>check</code>; <code>--no-external</code> runs only svstyle's own "
        "checks.</p></div>"
    )


QUICKSTART = """
<div class="steps">
 <div class="card step"><h4>Install the skill</h4>
  <p>As a Claude Code plugin, from inside Claude Code:</p>
  {plugin}
  <p class="small">Without the plugin system, copy or symlink <code>skill/systemverilog-rtl</code>
  into <code>~/.claude/skills/</code>. The plugin also adds a hook that runs
  <code>svstyle check --no-external</code> after every <code>.sv</code> edit and tells Claude what
  it found. It never blocks.</p></div>
 <div class="card step"><h4>Install the checker</h4>
  <p>The CLI the skill runs. Then the external tools, which are used when present.</p>
  {cli}
  <p class="small">Verible {verible} (tested versions) for formatting and lint, Verilator 5,
  and Yosys. The <a href="https://github.com/YosysHQ/oss-cad-suite-build">OSS CAD Suite</a>
  ships Verilator, Yosys and the yosys-slang plugin in one download.</p></div>
 <div class="card step"><h4>Configure the project (optional)</h4>
  <p>One <code>.svstyle.toml</code> at the repository root covers the tree.</p>
  {toml}</div>
 <div class="card step"><h4>Ask for hardware</h4>
  <p>No need to name the skill: any SystemVerilog request loads it.</p>
  <ul class="prompts">
   <li>Design a 4-way round-robin arbiter with a ready/valid output.</li>
   <li>Add a 2-flop synchroniser for the <code>busy</code> flag into the 25 MHz domain.</li>
   <li>Review <code>rtl/fifo.sv</code> against the house style.</li>
   <li>Bring this Verilog-2001 UART into the house style without changing behaviour.</li>
   <li>Why does svstyle flag DOC-004 on this line?</li>
  </ul></div>
</div>
"""

FLOW = [
    (
        "01",
        "Read the rules",
        "",
        "<code>references/rules.md</code>: one line per rule, short on purpose. Then the synthesis "
        "subset for the configured tool, and the multi-clock guide if the design needs it.",
        "<ul><li><code>synth-yosys.md</code> when <code>synth</code> is <code>yosys</code> or unset"
        "</li><li><code>synth-yosys-slang.md</code> for <code>yosys-slang</code></li>"
        "<li><code>multi-clock.md</code> + <code>rules-cdc.md</code> "
        "with more than one clock or an "
        "asynchronous input</li></ul>",
    ),
    (
        "02",
        "Start from a template",
        "",
        "Never a blank file: each template in <code>assets/</code> already passes "
        "<code>svstyle check</code>, so header, port order, reset style and comment layout come "
        "for free. Module and file are renamed together.",
        "<ul><li><code>skeleton.sv</code>: any module</li><li><code>fsm.sv</code> + "
        "<code>fsm_pkg.sv</code>: a state machine</li><li><code>sync_ff.sv</code>: a synchroniser"
        "</li><li><code>skeleton_tb.sv</code>: the testbench</li><li><code>assert_macros.svh"
        "</code>: <code>`ASSERT</code>, <code>`ASSERT_KNOWN</code></li></ul>",
    ),
    (
        "03",
        "Write the comments as it goes",
        "",
        "The fixer can only insert <code>// TODO: describe</code>, "
        "which keeps the file passing and "
        "flags a gap. Real comments are written with the code: header description, every port and "
        "declaration, a line above every block and instance, every FSM arm.",
        "Widths match on every assignment, no keyword used as a name, no temporary with bits "
        "never read, no assertion the type already guarantees.",
    ),
    (
        "04",
        "svstyle fix",
        "tool",
        "Verible formats the file; svstyle inserts what is missing (header, "
        "<code>`default_nettype none</code> / <code>`resetall</code>, labels) and modernises "
        "legacy code only where the syntax tree proves the meaning is unchanged.",
        "<code>reg</code>/<code>wire</code> → <code>logic</code>, <code>always @*</code> → "
        "<code>always_comb</code>, <code>always @(posedge)</code> → <code>always_ff</code>, "
        "<code>generate</code> removed, functions made <code>automatic</code>.",
    ),
    (
        "05",
        "svstyle check --synth",
        "tool",
        "One report from four tools, every finding as <code>file:line:col: RULE-ID message</code>. "
        "<code>[fix available]</code> means <code>fix</code> handles it; the rest is the author's.",
        "Every file of the design in one call, so Verilator can elaborate the hierarchy. "
        "<code>-I DIR</code> for <code>`include</code>s elsewhere.",
    ),
    (
        "06",
        "Simulate",
        "tool",
        "A clean check means well formed, not correct. A self-checking Verilator testbench in "
        "<code>tb/&lt;name&gt;_tb.sv</code> compares the outputs, every cycle, against a model "
        "written from the spec, never from the RTL.",
        "Skipped for small blocks: one clock, no memory or protocol, simple arithmetic, no "
        "fairness or ordering promise, under ~40 lines of logic. On a FAIL: decide from the "
        "spec which side is wrong, fix, rerun once.",
    ),
    (
        "07",
        "Walk the judgement list",
        "",
        "About a third of the rules need judgement. Before calling it done the skill checks them "
        "against the code: reset scope, FSM shape, "
        "<code>unique case</code> + <code>default</code>, "
        "parameter checks, assertions, naming, structure.",
        "A genuine departure is waived where it happens, with the reason: "
        "<code>// svstyle: waive RST-001 DSP blocks need a synchronous reset</code>.",
    ),
]

DONE = """
<ul class="checks">
 <li><code>svstyle check --synth</code> exits 0 on every file of the design. SHOULD findings may
 remain, each one a deliberate choice that is reported.</li>
 <li>No <code>// TODO: describe</code> is left anywhere in the RTL.</li>
 <li>The testbench printed <code>PASS</code> and no <code>`ASSERT</code> fired, or the block was
 small enough to skip it, and the skill says so.</li>
 <li>The judgement list was walked; every departure carries a DOC-009 waiver with its reason.</li>
 <li>The summary says what ran, what it reported, which SHOULDs stayed and why, and what the
 testbench covered (directed cases, random cycles, seed) and did not.</li>
</ul>
"""

REFS = [
    ("rules.md", "always, before any code", "One line per rule, every category but CDC."),
    (
        "synth-yosys.md",
        '<code>synth = "yosys"</code> or no key',
        "The SystemVerilog subset Yosys reads, and the constructs it synthesises wrong silently.",
    ),
    (
        "synth-yosys-slang.md",
        '<code>synth = "yosys-slang"</code>',
        "The much shorter list left with the slang frontend.",
    ),
    (
        "multi-clock.md, rules-cdc.md",
        "more than one clock, an async input, or a reset crossing",
        "Synchronisers, reset synchronisers, and the patterns for multi-bit crossings.",
    ),
    (
        "existing-code.md",
        "reviewing RTL or bringing legacy code into the style",
        "Baselines, what <code>fix</code> may rewrite, how to report findings.",
    ),
    (
        "testbench-verilator.md",
        "the Simulate step",
        "Where the testbench lives, what it may use, what it must check, the build command.",
    ),
    (
        "rules-rationale.md",
        "a rule is questioned or a finding is unclear",
        "Every rule with its rationale and examples; searched by heading, never loaded whole.",
    ),
    (
        "tooling.md",
        "<code>svstyle</code> missing, exit codes, JSON, waivers",
        "The CLI reference, and which tool enforces which rule.",
    ),
]

PILLARS = [
    (
        "DOC",
        "Comments are part of the code",
        "A header with a real description; a trailing comment on every port and declaration; a "
        "line above every block, instance and FSM arm. Checked and inserted by svstyle; no other "
        "open-source tool does it.",
        ["DOC-001", "DOC-003", "DOC-004", "DOC-005", "DOC-008"],
    ),
    (
        "NAM",
        "Names carry the hardware",
        "Direction (<code>_i</code>/<code>_o</code>), register (<code>_q</code>/<code>_d</code>), "
        "polarity (<code>_n</code>) and type (<code>_e</code>/<code>_t</code>) are in the name, so "
        "a reader never scrolls up to a declaration.",
        ["NAM-001", "NAM-002", "NAM-003", "NAM-004", "NAM-006"],
    ),
    (
        "LNG",
        "One way to write each thing",
        "<code>logic</code> everywhere; <code>always_ff</code> with <code>&lt;=</code>, "
        "<code>always_comb</code> with <code>=</code> and a default for every output; every "
        "<code>case</code> has a <code>default</code>; literals state their width.",
        ["LNG-001", "LNG-002", "LNG-003", "LNG-006", "LNG-007"],
    ),
    (
        "RST",
        "Reset control, not data",
        "Asynchronous active-low <code>rst_ni</code>, through a synchroniser per clock domain. "
        "State, counters and valids are reset; the datapath they qualify is not.",
        ["RST-001", "RST-002", "RST-004"],
    ),
    (
        "FMT",
        "The formatter owns whitespace",
        "Four spaces, 100 columns, tabular port lists and connections: Verible's output, not "
        "anyone's taste. Nothing about layout is ever discussed in review.",
        ["FMT-001", "FMT-002", "FMT-003"],
    ),
    (
        "SYN",
        "Synthesis is the contract",
        "Code in the subset the synthesis tool reads; no <code>full_case</code>, no combinational "
        "loops, no <code>initial</code>, no recursion. What simulates must be what is built.",
        ["SYN-001", "SYN-002", "SYN-005", "SYN-006"],
    ),
]

NAMING = [
    (
        "<code>_i</code> <code>_o</code> <code>_io</code>",
        "port direction, always last",
        "data_i, valid_o, pad_io",
        ["NAM-002"],
    ),
    (
        "<code>_q</code> / <code>_d</code>",
        "flop output / its computed next value",
        "count_q, count_d",
        ["NAM-004"],
    ),
    ("<code>_n</code>", "active low, stacked first", "rst_ni, cs_no, cs_nq", ["NAM-003"]),
    (
        "<code>clk_i</code>, <code>rst_ni</code>",
        "clock first, then async active-low reset",
        "clk_i, rst_ni",
        ["PRT-002", "RST-001"],
    ),
    (
        "<code>_e</code> / <code>_t</code>",
        "enum type / other typedef",
        "state_e, pkt_t",
        ["NAM-005"],
    ),
    (
        "UpperCamelCase",
        "parameters and localparams derived from them",
        "Width, NumPorts",
        ["NAM-006"],
    ),
    ("ALL_CAPS", "true constants and macros", "AXI_RESP_OKAY, `ASSERT", ["NAM-006", "NAM-008"]),
    ("<code>gen_</code>", "generate block labels", "gen_port, gen_width_check", ["GEN-001"]),
    (
        "<code>&lt;name&gt;_pkg</code>",
        "a package, in <code>&lt;name&gt;_pkg.sv</code>",
        "fsm_pkg",
        ["STR-001"],
    ),
    (
        "lower_snake_case",
        "everything else, in whole words",
        "rd_ptr_q, tx_busy",
        ["NAM-001", "NAM-009"],
    ),
]

CLI_COMMANDS = """
svstyle check rtl/                 # report; exit 1 on any MUST finding
svstyle check --synth rtl/*.sv     # also run Yosys (loops, drivers, readability)
svstyle check -f files.f -I inc    # a Verilator/VCS filelist and include dirs
svstyle fix rtl/ --diff            # show what fix would change; exit 1 if anything
svstyle fix rtl/                   # format, insert header/comments, modernise legacy code
svstyle rules --id PRT-003         # one rule in full
svstyle rules --unmapped           # the rules that need human judgement
"""

CLI_TOML = """
company = "ACME Corp"      # the copyright holder in every file header
synth   = "yosys"          # or "yosys-slang"; either runs Yosys on every check
select  = ["DOC", "LNG"]   # optional: only these rule IDs/prefixes
ignore  = ["DOC-005"]      # optional: drop these
include = ["rtl/inc"]      # optional: `include dirs, relative to this file
exclude = ["tb/*"]         # optional: skip when walking a directory or filelist
"""

CLI_OUTPUT = """
rtl/fifo.sv:14:1: DOC-003 `rst_ni` has no trailing // comment [fix available]
rtl/fifo.sv:31:5: LNG-015 Operator ASSIGN expects 4 bits, got 5 (WIDTHTRUNC)
2 findings (MUST 2, SHOULD 0)
"""

CLI_WAIVE = """
// svstyle: waive RST-001 DSP blocks need a synchronous reset
always_ff @(posedge clk_i) begin
    acc_q <= acc_d;
end

logic pad_io;  // svstyle: waive LNG-001 bidirectional pad
"""

CLI_CI = """
# .pre-commit-config.yaml
- repo: https://github.com/leandrotozzi/sv-skill
  rev: v0.1.0
  hooks:
    - id: svstyle-check   # and/or svstyle-fix

# adopt the style on existing code: only new findings fail
svstyle check rtl/ --baseline .svstyle-baseline --write-baseline
svstyle check rtl/ --baseline .svstyle-baseline
"""

EXIT_CODES = [
    ("0", "clean", "no MUST findings (SHOULD allowed)"),
    ("1", "violations", "at least one MUST finding: fix and rerun"),
    ("2", "error", "unreadable file, bad config, or a required tool missing"),
    (
        "3",
        "refused",
        "the file does not parse; a missing <code>`include</code> needs <code>-I DIR</code>",
    ),
    ("4", "bug", "svstyle broke its own invariant; nothing was written"),
]


def _section(sid: str, no: str, title: str, lede: str, body: str) -> str:
    return (
        f'<section id="{sid}"><div class="wrap"><div class="sec-head"><div class="sec-no">§{no}'
        f"</div><div><h2>{title}</h2><p>{lede}</p></div></div>{body}</div></section>"
    )


def render_html(rules: list[Rule], company: str = "", example: str = "") -> str:
    """The documentation site: how to use the skill, every rule, and the tools behind them.

    `example` is the skeleton template's text; with it the page annotates it line by line.
    """
    grouped = by_category(rules)
    by_id = {r.id: r for r in rules}
    counts = {s: sum(1 for r in rules if r.severity == s) for s in ("MUST", "SHOULD", "MAY")}
    autofix = sum(1 for r in rules if r.autofix)
    tooled = sum(1 for r in rules if r.tool != "review")
    owner = f"{_esc(company)} · " if company else ""

    hero = f"""
<div class="wrap hero">
 <div>
  <div class="eyebrow">Claude Code skill · svstyle CLI · {len(rules)} rules</div>
  <h1>SystemVerilog that reads like <em>one engineer</em> wrote it.</h1>
  <p class="lede">A house style for synthesizable RTL, a Claude Code skill that writes in it, and
  <code>svstyle</code>, the checker that enforces it through Verible, Verilator and Yosys. The
  rules, this page and the skill are generated from one file, so they never disagree.</p>
  <div class="cta"><a class="btn solid" href="#start">Get started →</a>
  <a class="btn ghost" href="#rules">Browse the rules</a></div>
  <div class="stats"><div><b>{len(rules)}</b><span>rules</span></div>
  <div><b>{counts["MUST"]}</b><span>MUST · fail the check</span></div>
  <div><b>{tooled}</b><span>checked by a tool</span></div>
  <div><b>{autofix}</b><span>fixed automatically</span></div></div>
 </div>
 <figure class="scope" style="margin:0">
  <div class="scope-head"><span>fig. 1 · <i>skeleton.sv</i></span>
  <span>posedge clk_i · async rst_ni</span></div>
  {_wave_svg()}
  <figcaption>The template every module starts from: valid is control and is reset; the payload
  is not, so <code>data_o</code> is X until the first valid input lands (RST-004).</figcaption>
 </figure>
</div>"""

    quick = QUICKSTART.format(
        plugin=_code(
            "/plugin marketplace add leandrotozzi/sv-skill\n"
            "/plugin install systemverilog-rtl@sv-skill",
            "claude code",
            "sh",
        ),
        cli=_code(
            "uv tool install svstyle        # or: pipx install svstyle\n"
            "uvx svstyle check rtl/         # or run it once without installing",
            "shell",
            "sh",
        ),
        toml=_code(
            'company = "ACME Corp"   # fills <Company> in every header\n'
            'synth   = "yosys"       # or "yosys-slang"; checks synthesis on every run',
            ".svstyle.toml",
            "toml",
        ),
        verible=_verible(),
    )

    flow = "".join(
        f'<li class="{cls}"><div class="dot">{no}</div><div><h4>{title}</h4><p>{text}</p></div>'
        f'<div class="side">{side}</div></li>'
        for no, title, cls, text, side in FLOW
    )
    refs = "".join(
        f"<tr><td><code>{f}</code></td><td>{when}</td><td>{what}</td></tr>"
        for f, when, what in REFS
    )
    iface = _code(
        "input  logic clk,    // svstyle: waive NAM-002 fixed interface; system clock\n"
        "input  logic reset,  // svstyle: waive NAM-002 fixed interface; sync reset, active-high",
        "a port list fixed by a spec",
    )
    skill = f"""
<ol class="flow">{flow}</ol>
<div class="grid2" style="margin-top:2.4rem">
 <div class="card"><h4>Done means</h4>{DONE}</div>
 <div class="card"><h4>When the interface is given</h4>
  <p>A spec, a benchmark, vendor IP or existing code may fix the module name, port names or the
  reset style (<code>clk</code>, <code>reset</code>, a synchronous active-high reset). Then the
  skill keeps them exactly as given: the house style is for what it chooses, not for a contract
  it was handed. Everything inside still follows the style, and what the interface forces is
  waived with the reason, which doubles as the port comment.</p>{iface}
  <p class="small" style="margin-top:.9rem">Reviewing, or bringing legacy RTL into the style,
  follows <code>existing-code.md</code>: <code>fix</code> modernises only what it can prove
  unchanged, and <code>--baseline</code> lets CI fail only on new findings.</p></div>
</div>
<h3>What the skill reads, and when</h3>
<p class="muted small" style="margin-top:-.5rem">Only <code>SKILL.md</code> and
<code>rules.md</code> are always loaded; everything else is read on demand, to keep the context
small.</p>
<div class="tbl"><table>
<tr><th>reference</th><th>loaded when</th><th>holds</th></tr>{refs}</table></div>
"""

    pillars = "".join(
        f'<div class="card pillar"><span class="big">{cat}</span><h4>{title}</h4><p>{text}</p>'
        f'<div class="ids">{_chips(ids, by_id)}</div></div>'
        for cat, title, text, ids in PILLARS
    )
    naming = "".join(
        f"<tr><td>{pat}</td><td>{means}</td><td><code>{_esc(ex)}</code></td>"
        f"<td>{_chips(ids, by_id)}</td></tr>"
        for pat, means, ex, ids in NAMING
    )
    may = (
        f'<div class="card sev-MAY"><b>MAY · {counts["MAY"]}</b><p>A documented permission. '
        "Never reported.</p></div>"
        if counts["MAY"]
        else ""
    )
    style = f"""
<div class="grid3">{pillars}</div>
<h3>Severity</h3>
<div class="sev-legend">
 <div class="card sev-MUST"><b>MUST · {counts["MUST"]}</b><p>A violation fails
 <code>svstyle check</code> (exit 1).</p></div>
 <div class="card sev-SHOULD"><b>SHOULD · {counts["SHOULD"]}</b><p>Reported, does not fail.
 Leaving one is a choice the author can explain.</p></div>
{may}</div>
<p class="small muted">Any finding, from any tool, is waived with one comment that names the rule
and says why: <code>// svstyle: waive DOC-004 &lt;reason&gt;</code>. On its own line it covers the
next line; trailing a line, that line. A waiver without a reason is ignored (DOC-009).</p>
<h3>Naming at a glance</h3>
<div class="tbl"><table><tr><th>pattern</th><th>means</th><th>example</th><th>rule</th></tr>
{naming}</table></div>
"""
    if example:
        style += (
            '<h3>Anatomy of a module</h3><p class="muted small" style="margin-top:-.5rem">'
            "The template every new module starts from. Hover a note to find its line.</p>"
            + _anatomy(example, by_id)
        )

    tiles = "".join(
        f'<button class="tile" data-k="cat" data-v="{cat}"><b>{cat}</b>'
        f"<span>{CATEGORIES[cat]}</span>"
        '<div class="meter">'
        + "".join(
            f'<i class="{c}" style="flex:{n}"></i>'
            for c, n in (
                ("m", sum(r.severity == "MUST" for r in g)),
                ("s", sum(r.severity == "SHOULD" for r in g)),
                ("y", sum(r.severity == "MAY" for r in g)),
            )
            if n
        )
        + f"</div><small>{len(g)} rules</small></button>"
        for cat, g in grouped.items()
    )
    sev_btns = "".join(
        f'<button class="fbtn" data-k="sev" data-v="{s}">{s}</button>'
        for s in ("MUST", "SHOULD", "MAY")
        if counts[s]
    )
    tools_used = [t for t in TOOL_LABEL if any(r.tool == t for r in rules)]
    tool_btns = "".join(
        f'<button class="fbtn" data-k="tool" data-v="{t}">{TOOL_LABEL[t]}</button>'
        for t in tools_used
    )
    cards = []
    for cat, group in grouped.items():
        cards.append(f'<div class="cat-h" data-cat="{cat}"><b>{cat}</b>{CATEGORIES[cat]}</div>')
        cards += [_card(r) for r in group]
    catalogue = f"""
<div class="tiles">{tiles}</div>
<div class="bar" id="catalogue">
 <div class="row"><input id="q" type="search" aria-label="Search rules"
  placeholder="Search IDs, titles, rationale, tool rule names…">
  <button class="fbtn" id="expand">Expand all</button>
  <button class="fbtn" id="reset">Reset</button></div>
 <div class="row"><label>Severity</label>{sev_btns}
  <label style="margin-left:.8rem">Enforced by</label>
  {tool_btns}<span class="count">{owner}<span id="shown">{len(rules)}</span> / {len(rules)} shown ·
  click an ID to copy it</span></div>
</div>
{"".join(cards)}
<p id="none" class="hidden">No rule matches those filters.</p>
"""

    exits = "".join(
        f"<tr><td><code>{c}</code></td><td><code>{k}</code></td><td>{m}</td></tr>"
        for c, k, m in EXIT_CODES
    )
    cli = f"""
{_code(CLI_COMMANDS, "commands", "sh")}
<p class="small muted">A directory stands for every <code>*.sv</code> below it.
<code>--select</code>/<code>--ignore</code> take IDs or prefixes, ruff-style:
<code>--select DOC,PRT-003</code>. <code>--json</code> gives machine-readable output;
<code>--no-external</code> runs only svstyle's own checks.</p>
{_code(CLI_OUTPUT, "output", "text")}
{_code(CLI_TOML, ".svstyle.toml — the nearest one walking up from each file", "toml")}
<p class="small muted">An unknown key or a wrong type is an error (exit 2), so a typo never
silently disables a setting.</p>
<div class="tbl"><table><tr><th>exit</th><th>kind</th><th>meaning</th></tr>{exits}</table></div>
<div class="grid2" style="margin-top:1.4rem">
 <div><h4>Waivers</h4>{_code(CLI_WAIVE, "rtl/mac.sv")}
  <p class="small muted">The tools' own pragmas (<code>// verilog_lint: waive</code>,
  <code>// verilator lint_off</code>) also work.</p></div>
 <div><h4>In CI</h4>{_code(CLI_CI, "pre-commit and baselines", "sh")}
  <p class="small muted"><code>svstyle fix --diff</code> exits 1 when any file would change, so it
  gates formatting too.</p></div>
</div>
"""

    nav = "".join(
        f'<a href="#{i}">{t}</a>'
        for i, t in (
            ("start", "Quick start"),
            ("skill", "The skill"),
            ("style", "House style"),
            ("rules", "Rules"),
            ("tools", "Tools"),
            ("cli", "CLI"),
        )
    )
    logo = (
        '<svg viewBox="0 0 32 32" aria-hidden="true"><rect x="7" y="7" width="18" height="18" '
        'rx="3" fill="none" stroke="currentColor" stroke-width="2"/><path d="M11 19h3v-6h4v6h3" '
        'fill="none" stroke="var(--copper)" stroke-width="2" stroke-linejoin="round"/>'
        '<path d="M11 3v4M16 3v4M21 3v4M11 25v4M16 25v4M21 25v4M3 11h4M3 16h4M3 21h4M25 11h4'
        'M25 16h4M25 21h4" stroke="currentColor" stroke-width="2"/></svg>'
    )

    sections = "".join(
        [
            _section(
                "start",
                "01",
                "Quick start",
                "Four steps from nothing to a module that passes lint, synthesis and its own "
                "testbench.",
                quick,
            ),
            _section(
                "skill",
                "02",
                "How the skill works",
                "What Claude does between your prompt and the finished RTL. Each step exists "
                "because skipping it cost a round of check, edit, check in the evals.",
                skill,
            ),
            _section(
                "style",
                "03",
                "The house style",
                "lowRISC lineage: <code>_i</code>/<code>_o</code>, <code>clk_i</code>, "
                "<code>rst_ni</code>, <code>_q</code>/<code>_d</code>, CamelCase parameters, "
                "100 columns; four-space indent is ours. Six ideas carry the rules.",
                style,
            ),
            _section(
                "rules",
                "04",
                f"All {len(rules)} rules",
                "Each rule, why it exists, what good and bad look like, and which tool "
                "enforces it. Filter by category, severity or tool; link to any rule by its "
                "ID, e.g. <code>#RST-001</code>.",
                catalogue,
            ),
            _section(
                "tools",
                "05",
                "The tools behind the rules",
                "<code>svstyle</code> runs each tool, translates what it says into house "
                "rule IDs, and prints one report. What no tool can see is left to the "
                "skill's judgement list and to review.",
                _tools(rules, by_id),
            ),
            _section(
                "cli",
                "06",
                "svstyle reference",
                "Everything the skill runs is a normal CLI you can run yourself, in a "
                "terminal or in CI.",
                cli,
            ),
        ]
    )

    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>sv-skill · SystemVerilog RTL style</title>
<meta name="description" content="A Claude Code skill and the svstyle checker for synthesizable
SystemVerilog: how to use them, all {len(rules)} rules, and the tools that enforce them.">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="{FONTS}" rel="stylesheet">
<style>{CSS}</style>
<script>try{{const t=localStorage.getItem("theme");
if(t)document.documentElement.dataset.theme=t;}}catch(e){{}}</script></head><body>
<header class="top"><div class="wrap"><a class="brand" href="#">{logo}<span>sv-skill</span></a>
<nav class="nav">{nav}</nav>
<button class="icon-btn" id="theme" title="Toggle dark mode"
 aria-label="Toggle dark mode">◐</button>
<a class="icon-btn" href="{REPO_URL}">GitHub</a></div></header>
<main>{hero}{sections}</main>
<footer><div class="wrap"><span>Generated by <code>svstyle rules --gen</code> from
<code>rules.toml</code>, the single source for this page, the checker and the skill.</span>
<span><a href="{REPO_URL}">github.com/leandrotozzi/sv-skill</a> · MIT</span></div></footer>
<script>{JS}</script></body></html>
"""

"""One-off review page: accept/reject each rule, progress bar, export decisions.

    uv run python scripts/rule_review.py && open docs/rule-review.html

Decisions live in the browser (localStorage), keyed by rule ID plus a hash of
the rule's content: regenerate after editing a rule and only that rule comes
back as pending. "Exportar" downloads rule-review.json for Claude to read.
"""

import hashlib
from pathlib import Path

from svstyle.docgen import CSS, _card
from svstyle.rules import CATEGORIES, by_category, load_rules

OUT = Path(__file__).resolve().parents[1] / "docs" / "rule-review.html"


def rev(r) -> str:
    blob = "\0".join([r.severity, r.title, r.statement, r.rationale, r.good, r.bad])
    return hashlib.sha1(blob.encode()).hexdigest()[:8]


EXTRA_CSS = """
.top{position:sticky;top:0;z-index:3;background:var(--bg);padding:1rem 0 .8rem;
 border-bottom:1px solid var(--line);margin-bottom:1.2rem}
.prog{display:flex;height:12px;border-radius:6px;overflow:hidden;background:var(--line)}
.prog i{display:block;transition:width .35s ease}
.prog .ok{background:var(--green)}.prog .no{background:var(--red)}
.counts{display:flex;gap:1.2rem;margin:.55rem 0 .7rem;font-size:.85rem;flex-wrap:wrap}
.counts b{font-size:1.05rem}
.c-ok{color:var(--green)}.c-no{color:var(--red)}.c-pend{color:var(--dim)}
.tabs{display:flex;gap:.35rem;flex-wrap:wrap;align-items:center}
.tabs .sp{flex:1}
.kbd{font-size:.72rem;color:var(--dim)}
.item{display:grid;grid-template-columns:1fr 9.5rem;gap:.8rem;align-items:start;
 transition:opacity .3s ease,transform .3s ease}
.item.leave{opacity:0;transform:translateX(40px)}
.item.cur .rule{border-color:var(--accent);box-shadow:0 0 0 1px var(--accent)}
.act{position:sticky;top:9.5rem;display:flex;flex-direction:column;gap:.4rem}
.act button{font-size:.9rem;padding:.5rem;font-weight:600}
.act .a{color:var(--green);border-color:var(--green)}
.act .r{color:var(--red);border-color:var(--red)}
.act .a.sel{background:var(--green);color:#fff}
.act .r.sel{background:var(--red);color:#fff}
.act textarea{font:inherit;font-size:.78rem;min-height:4.5rem;padding:.4rem;resize:vertical;
 border:1px solid var(--line);border-radius:6px;background:var(--card);color:var(--fg)}
.item.hidden{display:none}
.done{text-align:center;padding:3rem 0;color:var(--dim);font-size:1.1rem}
@media(max-width:680px){.item{grid-template-columns:1fr}.act{position:static;flex-direction:row;flex-wrap:wrap}}
"""

JS = """
const KEY='svstyle-rule-review';
let db={};
try{db=JSON.parse(localStorage.getItem(KEY)||'{}')}catch(e){}
const save=()=>{try{localStorage.setItem(KEY,JSON.stringify(db))}catch(e){}};
const items=[...document.querySelectorAll('.item')];
// A decision only counts for the rule text it was made on.
const st=el=>{const d=db[el.dataset.id];return d&&d.rev===el.dataset.rev?d.s:'pend'};
let view='pend';
let keep=null;   // a just-rejected card stays open for its note

function render(){
  const n={ok:0,no:0,pend:0};
  for(const el of items){
    const s=st(el); n[s]++;
    el.classList.toggle('hidden',view!=='all'&&s!==view&&el.dataset.id!==keep);
    el.querySelector('.a').classList.toggle('sel',s==='ok');
    el.querySelector('.r').classList.toggle('sel',s==='no');
    const note=el.querySelector('textarea');
    note.classList.toggle('hidden',s!=='no');
    if(document.activeElement!==note)note.value=(db[el.dataset.id]||{}).note||'';
  }
  const T=items.length;
  document.getElementById('pok').style.width=100*n.ok/T+'%';
  document.getElementById('pno').style.width=100*n.no/T+'%';
  for(const k in n)document.getElementById('n'+k).textContent=n[k];
  for(const h of document.querySelectorAll('h2')){
    const any=items.some(e=>e.dataset.cat===h.dataset.cat&&!e.classList.contains('hidden'));
    h.classList.toggle('hidden',!any);
  }
  const visible=items.filter(e=>!e.classList.contains('hidden')&&e.dataset.id!==keep);
  document.getElementById('done').classList.toggle('hidden',visible.length>0||keep);
  for(const e of items)e.classList.remove('cur');
  if(visible[0])visible[0].classList.add('cur');
}

function decide(el,s){
  const id=el.dataset.id,prev=db[id];
  if(prev&&prev.rev===el.dataset.rev&&prev.s===s){delete db[id]}   // click again = undo
  else db[id]={s,rev:el.dataset.rev,note:s==='no'?(prev&&prev.note)||'':''};
  save();
  if(keep&&keep!==id)dismiss();
  if(view==='pend'&&s==='no'&&db[id]){keep=id;render();el.querySelector('textarea').focus()}
  else if(view==='pend'&&db[id])leave(el);
  else{keep=null;render()}
}
function leave(el){
  el.classList.add('leave');
  setTimeout(()=>{el.classList.remove('leave');render()},300);
}
function dismiss(){
  const el=items.find(e=>e.dataset.id===keep);keep=null;
  if(el)leave(el);
}

for(const el of items){
  el.querySelector('.a').onclick=()=>decide(el,'ok');
  el.querySelector('.r').onclick=()=>decide(el,'no');
  const note=el.querySelector('textarea');
  note.oninput=e=>{db[el.dataset.id].note=e.target.value;save();};
  note.onkeydown=e=>{if(e.key==='Enter'&&!e.shiftKey){e.preventDefault();note.blur();
    if(keep===el.dataset.id)dismiss();}};
}
for(const b of document.querySelectorAll('button[data-view]'))
  b.onclick=()=>{view=b.dataset.view;keep=null;
    for(const o of document.querySelectorAll('button[data-view]'))o.classList.toggle('on',o===b);
    render();window.scrollTo(0,0);};

document.getElementById('export').onclick=()=>{
  const out=items.map(el=>({id:el.dataset.id,rev:el.dataset.rev,
    status:st(el),note:st(el)==='no'?db[el.dataset.id].note:''}));
  const a=document.createElement('a');
  a.href=URL.createObjectURL(new Blob([JSON.stringify(out,null,2)],{type:'application/json'}));
  a.download='rule-review.json';a.click();
};

// Keyboard: a = accept, r = reject the highlighted (first visible) rule.
document.addEventListener('keydown',e=>{
  if(e.target.tagName==='TEXTAREA'||e.metaKey||e.ctrlKey)return;
  const cur=document.querySelector('.item.cur');if(!cur)return;
  if(e.key==='a')decide(cur,'ok');
  if(e.key==='r')decide(cur,'no');
});
render();
"""


def main() -> None:
    rules = load_rules()
    body = []
    for cat, group in by_category(rules).items():
        body.append(f'<h2 data-cat="{cat}">{cat} — {CATEGORIES[cat]}</h2>')
        for r in group:
            body.append(
                f'<div class="item" data-id="{r.id}" data-rev="{rev(r)}" data-cat="{cat}">'
                f"{_card(r)}"
                '<div class="act"><button class="a">✓ Accept</button>'
                '<button class="r">✗ Reject</button>'
                '<textarea class="hidden" placeholder="¿Qué cambiarías? Enter para seguir"></textarea>'
                "</div></div>"
            )
    OUT.write_text(f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Rule review</title>
<style>{CSS}{EXTRA_CSS}</style></head><body><div class="wrap">
<div class="mast"><h1>Rule review</h1>
<p>{len(rules)} reglas. Aceptá o rechazá cada una; las decididas salen de la cola.
Si rechazás, dejá una nota de qué cambiarías.</p></div>
<div class="top">
<div class="prog"><i id="pok" class="ok"></i><i id="pno" class="no"></i></div>
<div class="counts">
<span class="c-ok"><b id="nok">0</b> aceptadas</span>
<span class="c-no"><b id="nno">0</b> rechazadas</span>
<span class="c-pend"><b id="npend">0</b> pendientes</span></div>
<div class="tabs">
<button data-view="pend" class="on">Pendientes</button>
<button data-view="ok">Aceptadas</button>
<button data-view="no">Rechazadas</button>
<button data-view="all">Todas</button>
<span class="sp"></span><span class="kbd">teclas: <b>a</b> aceptar · <b>r</b> rechazar</span>
<button id="export">⬇ Exportar</button></div>
</div>
{"".join(body)}
<p id="done" class="done hidden">🎉 Nada por acá. Mirá otra pestaña o apretá Exportar.</p>
</div><script>{JS}</script></body></html>
""")
    print(f"wrote {OUT.relative_to(Path.cwd()) if OUT.is_relative_to(Path.cwd()) else OUT}")


if __name__ == "__main__":
    main()

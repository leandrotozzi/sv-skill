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

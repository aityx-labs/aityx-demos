const SAMPLES={
  baby:{label:"Baby on the way",members:[{id:"maya",name:"Maya",age:31},{id:"sam",name:"Sam",age:33}],
    text:"Maya is pregnant with our first baby, due in March. She sees her OB every month until then. Sam is healthy, he just does his yearly physical."},
  asthma:{label:"Kid with asthma",members:[{id:"dana",name:"Dana",age:40},{id:"leo",name:"Leo",age:9},{id:"ava",name:"Ava",age:6}],
    text:"Leo has asthma. He uses an inhaler every day and sees his lung specialist every few months. Ava only needs her yearly checkup. I take a thyroid pill every day, nothing else."},
  solo:{label:"Just me",members:[{id:"chris",name:"Chris",age:27}],
    text:"I'm 27 and rarely get sick. One checkup a year, maybe urgent care if I hurt myself skiing again."}
};
// Extra years for Fill random when a key is connected (priced live; no recordings, so not offered without a key).
const EXTRA={
  diabetes:{label:"Couple, one with diabetes",members:[{id:"jordan",name:"Jordan",age:45},{id:"riley",name:"Riley",age:43}],
    text:"Jordan has type 2 diabetes, takes metformin every day and sees an endocrinologist every three months. Riley is healthy and only needs a yearly checkup."},
  knee:{label:"Knee surgery",members:[{id:"morgan",name:"Morgan",age:52}],
    text:"I'm having knee surgery in February, then a few weeks of physical therapy. Otherwise I'm healthy."},
  four:{label:"Healthy family of four",members:[{id:"pat",name:"Pat",age:38},{id:"jamie",name:"Jamie",age:37},{id:"mia",name:"Mia",age:8},{id:"noah",name:"Noah",age:5}],
    text:"We're all healthy. Just yearly checkups for everyone and maybe a sick visit or two for the kids."},
  adhd:{label:"Parent and son",members:[{id:"taylor",name:"Taylor",age:34},{id:"eli",name:"Eli",age:12}],
    text:"Eli takes ADHD medication every day and sees his doctor every few months. I only need my yearly checkup."},
  expecting:{label:"Baby on the way, plus asthma",members:[{id:"sofia",name:"Sofia",age:29},{id:"marcus",name:"Marcus",age:31}],
    text:"Sofia is pregnant and due in June. Marcus has asthma and uses an inhaler every day."},
  heart:{label:"Ongoing heart care",members:[{id:"lee",name:"Lee",age:61}],
    text:"I have high blood pressure, take a pill every day and see a cardiologist twice a year."}
};
const yearOf=k=>SAMPLES[k]||EXTRA[k];
// What-if switches: each one changes one person's facts and re-prices with the same rules (one call, no AI).
const WHATIF={
  baby:[{id:"nobaby",label:"No baby this year",set:{maya:{pregnant:0}}},
        {id:"samdiab",label:"Sam is diagnosed with diabetes",set:{sam:{care:"regular"}}}],
  asthma:[{id:"leocalm",label:"Leo only needs checkups",set:{leo:{care:"light"}}},
          {id:"avadiab",label:"Ava is diagnosed with diabetes",set:{ava:{care:"regular"}}},
          {id:"danababy",label:"Dana is expecting",set:{dana:{pregnant:1}}}],
  solo:[{id:"knee",label:"Chris needs knee surgery",set:{chris:{care:"some"}}},
        {id:"chrisdiab",label:"Chris is diagnosed with diabetes",set:{chris:{care:"regular"}}}]
};
const whatNow=()=>S&&S.what?(WHATIF[S.key]||[]).find(w=>w.id===S.what):null;
// The facts actually priced: what Jev read (or the person fixed), with the active what-if on top.
function effMembers(){
  const set=(whatNow()||{}).set||{};
  return S.members.map(m=>{ const o=set[m.id]; if(!o) return m;
    return {...m,care:o.care!=null?o.care:m.care,pregnant:o.pregnant!=null?o.pregnant:m.pregnant,
      src:{care:o.care!=null?"whatif":m.src.care,pregnant:o.pregnant!=null?"whatif":m.src.pregnant}}; });
}
const DEFAULT_PLANS=[
  {id:"bronze",name:"Bronze",premium_single:720,premium_family:3425,deductible:4000,coinsurance:0.4,oop_max:12000},
  {id:"silver",name:"Silver",premium_single:1440,premium_family:6850,deductible:1886,coinsurance:0.2,oop_max:6000},
  {id:"gold",name:"Gold",premium_single:2304,premium_family:10960,deductible:500,coinsurance:0.1,oop_max:3000}];
const DEFAULT_PRICES={light:300,some:1500,regular:6000,birth:20416,newborn:5820};
const CARE={light:"light year",some:"some care",regular:"ongoing care"};
const DEADLINE="2026-12-15";
const EVIDENCE=0.8;   // same cut-off as the decision's evidence_threshold
const ON_TOPIC=0.5;   // below this, we warn that the message doesn't read like a health year
const MAX_PEOPLE=6;

let S;
const $=id=>document.getElementById(id);
const esc=s=>String(s).replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
const money=n=>"$"+Math.round(Number(n)).toLocaleString("en-US");
const fmtDate=s=>new Date(s+"T00:00:00Z").toLocaleDateString("en-US",{weekday:"short",month:"short",day:"numeric",timeZone:"UTC"});
const isAdult=m=>m.age>=18;
const born=m=>m.pregnant>=EVIDENCE;
// aityx answers carry their value under a typed field
const V=(a,k)=>{ const x=a&&a[k]; if(x==null) return undefined; if(typeof x!=="object"||Array.isArray(x)) return x; for(const f of ["value","choice","number","date","noul","level","score"]) if(f in x) return x[f]; return x; };

/* ---------- the decision: every number on the page comes from here ---------- */
const feelPlans=ps=>"["+ps.map(p=>`{id: "${p.id}", name: "${p.name}", premium_single: ${p.premium_single}, premium_family: ${p.premium_family}, deductible: ${p.deductible}, coinsurance: ${p.coinsurance}, oop_max: ${p.oop_max}}`).join(", ")+"]";
// Per-person facts are inputs: in the one call Jev answers them; when the person corrects one, it comes in the state.
function buildDecision(plans,prices,members){
  const adults=members.filter(isAdult), inputs={"members":{"type":["Person"],"desc":"People on the plan: id, name and age","from":"page JSON"}};
  members.forEach(m=>{
    inputs[`${m.id}_care`]={"type":"light|some|regular","desc":`Care level member ${m.id} needs in 2027, read by Jev from message or set by the person`,"from":"Jev"};
    if(isAdult(m)) inputs[`${m.id}_pregnant`]={"type":"number [0..1]","desc":`Jev probability that member ${m.id} gives birth in 2027 (1 or 0 when the person sets it)`,"from":"Jev"};
  });
  const careOf=members.map(m=>`if m.id = "${m.id}" then ${m.id}_care else `).join("")+`"light"`;
  const birthOf=adults.map(m=>`if m.id = "${m.id}" then ${m.id}_pregnant else `).join("")+`0`;
  return {"name":"Example · Pick a 2027 health plan",
  "types":{
    "Person":{"id":"string","name":"string","age":"number >= 0"},
    "Member":{"id":"string","name":"string","age":"number >= 0","care":"light|some|regular","pregnant":"number [0..1]"},
    "Plan":{"id":"string","name":"string","premium_single":"number >= 0","premium_family":"number >= 0","deductible":"number >= 0","coinsurance":"number [0..1]","oop_max":"number >= 0"},
    "Spend":{"id":"string","name":"string","care":"string","birth":"boolean","spend":"number"},
    "Line":{"id":"string","name":"string","care":"string","birth":"boolean","spend":"number","pays":"number"},
    "PlanResult":{"plan":"string","name":"string","premium":"number","deductible":"number","coinsurance":"number","oop_max":"number","cap":"number","lines":["Line"],"care_cost":"number"},
    "Total":{"plan":"string","total":"number","worst_case":"number"}},
  "inputs":inputs,
  "functions":{
    "person_oop":{"desc":"What one person pays in a year: everything up to the deductible, then the coinsurance share of the rest, never above the per-person cap, in USD","params":{"spend":"number","deductible":"number","coinsurance":"number","cap":"number"},"returns":"number","body":"min(cap, min(spend, deductible) + coinsurance * max(0, spend - deductible))"}},
  "decisions":{
    "plans":{"type":["Plan"],"desc":"The three plans on offer: yearly premium share for single and family coverage, per-person deductible, coinsurance after the deductible, per-person out-of-pocket cap. Fictional, built on public averages","expr":feelPlans(plans)},
    "family_cap_factor":{"type":"number","desc":"A family's out-of-pocket cap is this many times the per-person cap","expr":"2"},
    "price_light":{"type":"number","desc":"Expected yearly care for a light year (a sick visit or urgent care), in USD","expr":String(prices.light)},
    "price_some":{"type":"number","desc":"Expected yearly care with a few visits or a short treatment, in USD","expr":String(prices.some)},
    "price_regular":{"type":"number","desc":"Expected yearly care for an ongoing condition (daily medication, regular specialist), in USD","expr":String(prices.regular)},
    "price_birth":{"type":"number","desc":"Pregnancy, birth and postpartum care, in USD","expr":String(prices.birth)},
    "price_newborn":{"type":"number","desc":"A newborn's care in the first months, in USD","expr":String(prices.newborn)},
    "evidence_threshold":{"type":"number [0..1]","desc":"Minimum Jev probability to treat someone as giving birth in 2027 (inclusive)","expr":String(EVIDENCE)},
    "choose_by":{"type":"date","desc":"Last day to pick a plan for coverage that starts Jan 1 (HealthCare.gov)","expr":`date("${DEADLINE}")`},
    "people":{"type":["Member"],"desc":"Each person with the care level and birth probability used for them","expr":`for m in members return {id: m.id, name: m.name, age: m.age, care: (${careOf}), pregnant: (${birthOf})}`},
    "baby_coming":{"type":"boolean","desc":"Does anyone on the plan give birth in 2027?","expr":"count(people[pregnant >= evidence_threshold]) > 0"},
    "coverage":{"type":"single|family","desc":"Single when one person is covered, family otherwise. A newborn counts","expr":"if count(people) + (if baby_coming then 1 else 0) > 1 then \"family\" else \"single\""},
    "spend_list":{"type":["Spend"],"desc":"Expected 2027 care per person before the plan pays, in USD. A birth adds to the person giving birth, and the newborn joins the plan","expr":"concatenate(for m in people return {id: m.id, name: m.name, care: m.care, birth: m.pregnant >= evidence_threshold, spend: (if m.care = \"regular\" then price_regular else if m.care = \"some\" then price_some else price_light) + (if m.pregnant >= evidence_threshold then price_birth else 0)}, if baby_coming then [{id: \"newborn\", name: \"Newborn\", care: \"newborn\", birth: false, spend: price_newborn}] else [])"},
    "plan_results":{"type":["PlanResult"],"desc":"Per plan: the premium for this coverage, what each person pays for care, and the care total after the family cap, in USD","expr":"for p in plans return {plan: p.id, name: p.name, premium: (if coverage = \"family\" then p.premium_family else p.premium_single), deductible: p.deductible, coinsurance: p.coinsurance, oop_max: p.oop_max, cap: (if coverage = \"family\" then p.oop_max * family_cap_factor else p.oop_max), lines: for s in spend_list return {id: s.id, name: s.name, care: s.care, birth: s.birth, spend: s.spend, pays: decimal(person_oop(s.spend, p.deductible, p.coinsurance, p.oop_max), 2)}, care_cost: decimal(min((if coverage = \"family\" then p.oop_max * family_cap_factor else p.oop_max), sum(concatenate([0], for s in spend_list return person_oop(s.spend, p.deductible, p.coinsurance, p.oop_max)))), 2)}"},
    "plan_totals":{"type":["Total"],"desc":"Per plan: expected 2027 total (premium plus care) and the worst case (premium plus the full cap), in USD","expr":"for r in plan_results return {plan: r.plan, total: r.premium + r.care_cost, worst_case: r.premium + r.cap}"},
    "best_plan":{"type":"string","desc":"The plan with the lowest expected 2027 total","expr":"(sort(plan_totals, function(x, y) x.total < y.total))[1].plan"},
    "savings":{"type":"number","desc":"How much less the best plan costs than the next cheapest, in USD","let":{"sorted":"sort(plan_totals.total, function(x, y) x < y)"},"expr":"decimal(sorted[2] - sorted[1], 2)"}
  }};
}
function jevQuestions(){
  const q={about_health:{type:"noul",
    instructions:"Does message describe the health or medical care expected next year for the people in members?",
    criteria:{"true":"The message talks about health, doctor visits, medication, conditions, a pregnancy or staying healthy.","false":"The message is about something else, or is empty or nonsense."}}};
  S.members.forEach(m=>{
    if(m.src.care!=="you") q[`${m.id}_care`]={type:"choice",
      instructions:`How much medical care does message say ${m.name} (id ${m.id} in members) will need next year? Do not count pregnancy or birth; that is asked separately. Do not estimate costs.`,
      criteria:{light:`At most a yearly checkup or one minor visit, no ongoing condition, or the message says nothing about ${m.name}'s health.`,
                some:`A few visits, urgent care, physical therapy or a one-off procedure, but no ongoing condition that needs regular care.`,
                regular:`An ongoing condition that needs daily medication or regular specialist visits, such as asthma, diabetes or a thyroid condition.`}};
    if(isAdult(m)&&m.src.pregnant!=="you") q[`${m.id}_pregnant`]={type:"noul",
      instructions:`Does message say that ${m.name} (id ${m.id} in members) is pregnant or will give birth next year?`,
      criteria:{"true":`The message says ${m.name} is pregnant, expecting, or due to give birth.`,
                "false":`The message says someone else is pregnant, or does not say ${m.name} is pregnant.`}};
  });
  return q;
}

/* ---------- live calls, on the aityx key set on the aityx demos page (aityx.js) ---------- */
let REC_MODE=/record/i.test(location.hash+location.search); // team only: add #record to the address to see the recording buttons
addEventListener("hashchange",()=>{ REC_MODE=/record/i.test(location.hash+location.search); connectUI(); });
// conn: where calls go and on whose key (Aityx.resolve): the user's key, the index server's dev key, or none.
const LIVE={conn:Aityx.NONE,resolved:false,seq:0,timer:0,call:null,read:null};
const live=()=>LIVE.conn.source!=="none";
const endpoint=()=>LIVE.conn.systemone;
function liveNote(t,cls){ const n=$("live"); n.className="live"+(cls?" "+cls:""); n.textContent=t; }
// Connection status: "Connected" only after aityx answers, never just because a key is set.
const CONN={state:"connecting",seq:0};
const NO_KEY_TEXT="You're seeing real aityx calls we recorded. Set your key on the aityx demos page to price your own year live.";
function okText(){
  const c=LIVE.conn;
  return c.source==="dev"?`You haven't set a key, so this server lends ${c.whose}${c.url?` (${c.url})`:""}. Every answer on this page now comes from a live aityx call.`
    :`Your key works${c.url&&c.url!=="https://api.aityx.ai"?` with ${c.url}`:""}. Every answer on this page now comes from a live aityx call.`;
}
const failText=(c,d)=>{ const why=d&&d.detail?`: ${d.detail}`:"";
  return c===401||c===403?`aityx rejected ${LIVE.conn.whose}${why}. Check it in the aityx console and set it again on the aityx demos page.`
    :c===502&&LIVE.conn.source==="dev"?`The dev proxy couldn't reach aityx${why}.`
    :`aityx answered with HTTP ${c}${why}. Try again in a moment.`; };
const MODE_TEXT={idle:"No key",connecting:"Checking key…",ok:"Live · aityx",fail:"Key problem"};
function setConn(state,detail){
  CONN.state=state; $("connpanel").dataset.state=state; $("mode").dataset.state=state; $("modetext").textContent=MODE_TEXT[state];
  const [t,x]=state==="fail"?["Connection failed",detail]:state==="ok"?[LIVE.conn.source==="dev"?"Connected to aityx, on the dev key":"Connected to aityx",okText()]
    :state==="idle"?["No aityx key yet",NO_KEY_TEXT]:["Checking your aityx key…","One quick call to aityx, no AI."];
  $("conn-title").textContent=t; $("conn-text").textContent=x;
  $("mode").title=`aityx: ${t}. ${x} Click to set your key.`;
  $("setkey").textContent=LIVE.conn.source==="user"?"Change your key":LIVE.conn.source==="dev"?"Set your own key":"Set your aityx key";
}
async function post(body){
  const conn=LIVE.conn, n=++CONN.seq, mine=()=>n===CONN.seq&&LIVE.conn===conn;
  if(CONN.state!=="ok") setConn("connecting");
  let res;
  try{ res=await fetch(conn.systemone,{method:"POST",headers:conn.headers(),body:JSON.stringify(body)}); }
  catch(e){ if(mine()) setConn("fail",`We couldn't reach ${conn.source==="dev"?"the dev proxy":conn.url}. Check your internet connection.`); throw e; }
  const data=await res.json().catch(()=>null);
  // A rejected key or a server problem breaks the connection; a call aityx refused (400, 422) doesn't.
  if(mine()) setConn(res.status===401||res.status===403||res.status>=500?"fail":"ok",failText(res.status,data));
  return {status:res.status,ok:res.ok,data};
}
// Which key, and does aityx take it (one empty call, no model runs): on start, when the key
// changes (the aityx demos page, in another tab), and when the page comes back into view, at
// most every 30 s. A different key from before resets the page, as its results were priced on the other.
const connId=c=>`${c.source}|${c.systemone}|${c.headers().Authorization||""}`;
let lastCheck=0;
async function refreshConnection(){
  const n=++CONN.seq; lastCheck=Date.now(); setConn("connecting");
  const conn=await Aityx.resolve(); if(n!==CONN.seq) return;
  const changed=connId(conn)!==connId(LIVE.conn), first=!LIVE.resolved;
  LIVE.conn=conn; LIVE.resolved=true;
  if(changed&&!first&&S){ S.recorded=null; load(S.key); }
  connectUI();
  if(conn.source==="none"){ setConn("idle"); return; }
  setConn("connecting");
  const st=await Aityx.check(conn); if(n!==CONN.seq) return;
  setConn(st.kind==="ready"?"ok":"fail",
    st.kind==="rejected"?`aityx rejected ${conn.whose} (${st.detail}). Check it in the aityx console and set it again on the aityx demos page.`
    :st.kind==="unreachable"?`We couldn't reach aityx: ${st.detail}.`:`${st.detail}. Try again in a moment.`);
}
addEventListener("storage",e=>{ if(e.key===null||e.key===Aityx.KEY_NAME||e.key===Aityx.URL_NAME) refreshConnection(); });
addEventListener("focus",()=>{ if(Date.now()-lastCheck>30000) refreshConnection(); });
addEventListener("pageshow",e=>{ if(e.persisted) refreshConnection(); });
const errOf=r=>!r.ok?(r.data&&(r.data.detail||r.data.title))||`HTTP ${r.status}`:r.data&&r.data.decision_error?(r.data.decision_error.message||r.data.decision_error.code):!r.data||!r.data.answers?"no answers":null;
const stateMembers=()=>S.members.map(m=>({id:m.id,name:m.name,age:m.age,care:m.care,pregnant:m.pregnant}));

const persons=()=>S.members.map(m=>({id:m.id,name:m.name,age:m.age}));
// Facts for the state. youOnly: only what the person set (Jev answers the rest in the same call).
function factsState(youOnly){
  const st={};
  effMembers().forEach(m=>{
    if(!youOnly||m.src.care==="you") st[`${m.id}_care`]=m.care;
    if(isAdult(m)&&(!youOnly||m.src.pregnant==="you")) st[`${m.id}_pregnant`]=m.pregnant;
  });
  return st;
}
// One call: Jev reads the message, then the rules price the plans with what Jev read.
async function readLive(){
  if(!live()) return;
  clearTimeout(LIVE.timer);
  S.what=null; clearDirty();
  const seq=++LIVE.seq;
  const body={questions:jevQuestions(),decision:buildDecision(S.plans,S.prices,S.members),state:{message:$("msg").value,members:persons(),...factsState(true)}};
  S.A=null; renderResult(); liveNote("aityx is reading your message and pricing the plans…");
  const t0=performance.now(); let r;
  try{ r=await post(body); }catch(e){ if(seq===LIVE.seq) liveNote(`Couldn't reach aityx (${e.message}). Nothing was priced.`,"warn"); return; }
  if(seq!==LIVE.seq) return;
  LIVE.call={req:body,res:r.data,status:r.status};
  const a=r.data&&r.data.answers;
  if(a){
    const used=Object.fromEntries((V(a,"people")||[]).map(p=>[p.id,p]));
    S.members.forEach(m=>{
      const u=used[m.id]||{}, c=u.care!=null?u.care:V(a,`${m.id}_care`), p=u.pregnant!=null?u.pregnant:V(a,`${m.id}_pregnant`);
      if(m.src.care!=="you"&&CARE[c]){ m.care=c; m.src.care="ai"; }
      if(isAdult(m)&&m.src.pregnant!=="you"&&typeof p==="number"){ m.pregnant=p; m.src.pregnant="ai"; }
    });
    S.about=V(a,"about_health"); S.jevRead=true;
  }
  const err=errOf(r); if(err){ S.A=null; renderResult(); liveNote(`aityx couldn't price this: ${err}.`,"warn"); return; }
  S.A=a; renderResult(true);
  const ms=Math.round(performance.now()-t0), off=typeof S.about==="number"&&S.about<ON_TOPIC;
  liveNote(off?`This doesn't read like a health year, so aityx assumed a light year for everyone. Try Fill random for another year.`
    :`One aityx call: it read your message and the rules priced the plans (${ms} ms).`, off?"warn":"ok");
  captureRecording();
}
// Re-price after a fix or a rule change: one call, rules only, no AI.
async function settleLive(){
  if(!live()) return;
  clearTimeout(LIVE.timer);
  const seq=++LIVE.seq, body={decision:buildDecision(S.plans,S.prices,S.members),state:{members:persons(),...factsState(false)}};
  liveNote("aityx is pricing the plans again…");
  const t0=performance.now(); let r;
  try{ r=await post(body); }catch(e){ if(seq===LIVE.seq) liveNote(`Couldn't reach aityx (${e.message}). Nothing was priced.`,"warn"); return; }
  if(seq!==LIVE.seq) return;
  LIVE.call={req:body,res:r.data,status:r.status};
  const err=errOf(r); if(err){ S.A=null; renderResult(); liveNote(`aityx couldn't price this: ${err}.`,"warn"); return; }
  clearDirty(); S.A=r.data.answers; renderResult(true);
  const w=whatNow();
  liveNote(w?`What if: ${w.label}. Priced by aityx in one call, rules only, no AI (${Math.round(performance.now()-t0)} ms).`:`Priced again by aityx in one call. No AI. ${Math.round(performance.now()-t0)} ms`,"ok");
}
// A change after the results are on screen does not re-price by itself: the results fade and Compare again shows up.
function queueLive(){
  if(!live()||document.body.classList.contains("pending")||!S.A) return;
  S.dirty=true; document.body.classList.add("dirty"); updateGo();
  liveNote("You changed something. Press Compare again to update the results.","warn");
}
function clearDirty(){ if(S) S.dirty=false; document.body.classList.remove("dirty"); }
function updateGo(){ $("go").textContent=live()&&S&&S.jevRead?"Compare again":"Compare plans"; }
function compareAgain(){
  settleLive();
  $("result").scrollIntoView({behavior:matchMedia("(prefers-reduced-motion: reduce)").matches?"auto":"smooth",block:"start"});
}

/* ---------- recordings: real calls made with a key, shown to visitors without one ---------- */
// RECORDINGS: real aityx calls, in recordings.js.
// For the team: runs every example untouched with your key and saves the real calls as one file.
async function recordAll(){
  if(!live()) return;
  const out={}, keys=Object.keys(SAMPLES);
  for(let i=0;i<keys.length;i++){ const k=keys[i], rec=RECORDINGS[k];
    load(k); document.body.classList.remove("pending"); LIVE.rec=null;
    toast(`Recording example ${i+1} of ${keys.length}…`);
    if(rec){ // reuse the recorded Jev read: no new AI call
      rec.members.forEach(rm=>{ const m=S.members.find(x=>x.id===rm.id); if(m){ m.care=rm.care; m.pregnant=rm.pregnant; m.src={care:"ai",pregnant:"ai"}; } });
      S.jevRead=true; out[k]={key:rec.key,when:rec.when,about:rec.about,members:rec.members,call:rec.call};
    } else {
      await readLive();
      if(!LIVE.rec||LIVE.rec.key!==k){ toast(`Stopped on "${SAMPLES[k].label}". See the note under the results.`); return; }
      out[k]=LIVE.rec;
    }
    out[k].whatif={};
    for(const w of WHATIF[k]||[]){
      S.what=w.id; await settleLive(); const c=LIVE.call;
      if(!c||c.status!==200||!c.res||c.res.decision_error||!c.res.answers){ toast(`Stopped on "${w.label}". See the note under the results.`); return; }
      out[k].whatif[w.id]={when:new Date().toLocaleDateString("en-CA"),call:{req:c.req,res:c.res}};
    }
    S.what=null; }
  const a=document.createElement("a"); a.href=URL.createObjectURL(new Blob([JSON.stringify(out)],{type:"application/json"})); a.download="health-recordings.json";
  document.body.appendChild(a); a.click(); a.remove();
  liveNote(`Recorded all ${keys.length} examples and their what-ifs with real aityx calls. Saved health-recordings.json to your Downloads.`,"ok");
}

const untouched=()=>!!SAMPLES[S.key]&&$("msg").value===SAMPLES[S.key].text&&JSON.stringify(S.plans)===JSON.stringify(DEFAULT_PLANS)&&JSON.stringify(S.prices)===JSON.stringify(DEFAULT_PRICES)
  &&JSON.stringify(S.members.map(m=>[m.id,m.name,m.age]))===JSON.stringify(yearOf(S.key).members.map(m=>[m.id,m.name,m.age]))&&!S.members.some(m=>m.src.care==="you"||m.src.pregnant==="you")&&!S.what;
function captureRecording(){
  const c=LIVE.call;
  if(!untouched()||!c||!c.req.questions||c.status!==200||!c.res||c.res.decision_error||!c.res.answers) return;
  LIVE.rec={key:S.key,when:new Date().toLocaleDateString("en-CA"),about:S.about,members:S.members.map(m=>({id:m.id,name:m.name,age:m.age,care:m.care,pregnant:m.pregnant})),call:{req:c.req,res:c.res}};
  $("rec").hidden=!REC_MODE;
}
function showRecorded(){
  const rec=RECORDINGS[S.key];
  if(!rec){ S.A=null; renderResult(); liveNote("This family has no recorded aityx call yet. Set your aityx key above and aityx prices it live.","warn"); return; }
  rec.members.forEach(rm=>{ const m=S.members.find(x=>x.id===rm.id); if(m){ m.care=rm.care; m.pregnant=rm.pregnant; m.src={care:"ai",pregnant:"ai"}; } });
  S.jevRead=true; S.recorded=rec; S.what=null; S.recCall=rec.call; S.A=rec.call.res.answers;
  renderResult(true);
  liveNote(`Recorded from a real aityx call on ${rec.when}. Set your aityx key above to change the plans and price them live.`,"ok");
}

/* ---------- state ---------- */
function load(key){
  const s=yearOf(key);
  S={key,members:s.members.map(m=>({...m,care:"light",pregnant:0,src:{care:"new",pregnant:"new"}})),
    plans:structuredClone(DEFAULT_PLANS),prices:{...DEFAULT_PRICES},A:null,focus:null,jevRead:false,recorded:null,recCall:null,what:null,about:null,n:0};
  LIVE.call=null; LIVE.seq++; $("rec").hidden=true; clearDirty();
  $("msg").value=s.text; $("msgq").textContent=s.text; countChars(); setNote();
  renderPicker();
  renderFamily(); renderRules(); renderResult();
  document.body.classList.add("pending");
}
/* ---------- result picker ---------- */
const MEDAL={bronze:"#C98A5E",silver:"#B8BEC8",gold:"#E3B341"};
const medal=id=>`<svg width="26" height="26" viewBox="0 0 26 26" aria-hidden="true"><circle cx="13" cy="13" r="10.5" fill="none" stroke="${MEDAL[id]||"#A9ACB6"}" stroke-width="2"/><circle cx="13" cy="13" r="5.5" fill="${MEDAL[id]||"#A9ACB6"}"/></svg>`;
// One entry per possible result, read from the recorded aityx answers (the page never decides who wins).
function results(){
  return Object.keys(SAMPLES).filter(k=>RECORDINGS[k]).map(k=>{
    const A=RECORDINGS[k].call.res.answers, best=V(A,"best_plan"), r=(V(A,"plan_results")||[]).find(x=>x.plan===best);
    return r?{k,plan:best,name:r.name}:null; }).filter(Boolean)
    .sort((a,b)=>["bronze","silver","gold"].indexOf(a.plan)-["bronze","silver","gold"].indexOf(b.plan));
}
function renderPicker(){
  const y=yearOf(S.key), res=results();
  $("pickcur").innerHTML=`${SAMPLES[S.key]?"Example":"Random year"}: <b>${esc(y.label)}</b>`;
  $("menu").innerHTML=`<div class="mh">Possible results</div>`+res.map(x=>`<button type="button" role="menuitemradio" aria-checked="${x.k===S.key}" data-k="${x.k}">${medal(x.plan)}<span>${esc(x.name)} wins</span><small>${esc(SAMPLES[x.k].label)}</small><span class="ck">${x.k===S.key?"✓":""}</span></button>`).join("");
}
function menuOpen(open){
  $("menu").hidden=!open; $("caret").setAttribute("aria-expanded",String(open));
  if(open){ const f=$("menu").querySelector("button"); if(f) f.focus(); }
}
// Fill a year. Without a key, if results are already on screen, show that year's recorded result right away.
function pick(k){
  const showing=!document.body.classList.contains("pending");
  menuOpen(false); load(k);
  if(showing&&!live()&&RECORDINGS[k]){ document.body.classList.remove("pending"); showRecorded(); }
}
function fillRandom(){
  const pool=Object.keys(SAMPLES).filter(k=>RECORDINGS[k]).concat(live()?Object.keys(EXTRA):[]).filter(k=>k!==S.key);
  if(pool.length) pick(pool[Math.floor(Math.random()*pool.length)]);
}
document.addEventListener("keydown",e=>{
  if($("menu").hidden) return;
  if(e.key==="Escape"){ menuOpen(false); $("caret").focus(); return; }
  if(e.key==="ArrowDown"||e.key==="ArrowUp"){ e.preventDefault(); const items=[...$("menu").querySelectorAll("button")], i=items.indexOf(document.activeElement);
    items[(i+(e.key==="ArrowDown"?1:-1)+items.length)%items.length].focus(); }
});
document.addEventListener("click",e=>{ if(!$("menu").hidden&&!e.target.closest("#split")) menuOpen(false); });

function setNote(){
  $("msgnote").classList.remove("warn");
  $("msgnote").textContent="aityx reads this message for each person's care and any pregnancy. Try a what-if under the results to see the winner change.";
  $("chips").hidden=true;
}
function msgChanged(){ const n=$("msgnote"); n.textContent="Message changed. Press Compare plans and aityx reads it again."; n.classList.add("warn"); liveNote("Message changed. Press Compare plans and aityx reads it again.","warn"); }
function countChars(){ const n=$("msg").value.length; $("count").textContent=`${n}/600`; }
function lockInputs(){
  const lk=!live(); document.body.classList.toggle("locked",lk);
  document.querySelectorAll("#fam input,#fam button,#add,#ptable input,#prices input,#understood select,#understood input").forEach(el=>el.disabled=lk);
}
function connectUI(){
  $("recall").hidden=!(live()&&REC_MODE);
  if(S){ setNote(); lockInputs(); updateGo(); renderWhatIf(); renderCall(); }
}

/* ---------- rendering ---------- */
function renderFamily(){
  $("fam").innerHTML=S.members.map(m=>`<div class="mem">
    <input type="text" value="${esc(m.name)}" data-m="${m.id}" data-f="name" maxlength="24" aria-label="Name">
    <span class="lbl">age</span><input type="number" min="0" max="110" value="${m.age}" data-m="${m.id}" data-f="age" aria-label="${esc(m.name)} age">
    <button class="x" type="button" data-del="${m.id}" aria-label="Remove ${esc(m.name)}" ${S.members.length<2?"disabled":""}>×</button></div>`).join("");
  $("add").hidden=S.members.length>=MAX_PEOPLE;
  lockInputs();
}
function renderRules(){
  const rows=[["premium_single","Premium, just you","$ a year"],["premium_family","Premium, family","$ a year"],["deductible","Deductible","$ per person"],["coinsurance","Your share after it","% of each bill"],["oop_max","Out-of-pocket limit","$ per person, 2× for a family"]];
  $("ptable").innerHTML=`<thead><tr><th></th>${S.plans.map(p=>`<th>${esc(p.name)}</th>`).join("")}</tr></thead><tbody>`+
    rows.map(([f,l,u])=>`<tr><td>${l}<small>${u}</small></td>${S.plans.map(p=>`<td><input type="number" min="0" ${f==="coinsurance"?'max="100" step="5"':'step="50"'} data-plan="${p.id}" data-f="${f}" value="${f==="coinsurance"?Math.round(p[f]*100):p[f]}" aria-label="${esc(p.name)} ${l}"></td>`).join("")}</tr>`).join("")+`</tbody>`;
  const pr=[["light","A light year","a sick visit or urgent care"],["some","Some care","a few visits or a short treatment"],["regular","Ongoing care","daily medication, regular specialist"],["birth","Having a baby","pregnancy, birth and postpartum"],["newborn","A newborn","care in the first months"]];
  $("prices").innerHTML=pr.map(([k,l,d])=>`<div class="rule">${l} costs $<input type="number" min="0" step="100" data-price="${k}" value="${S.prices[k]}" aria-label="${l} cost"><small>${d}</small></div>`).join("");
  lockInputs();
}
const srcTag=s=>s==="whatif"?`<span class="src src-what">what if</span>`:s==="you"?`<span class="src src-you">your input</span>`:s==="ai"?`<span class="src src-ai">AI read this</span>`:`<span class="src src-new">not read yet</span>`;
function renderUnderstood(){
  $("understood").innerHTML=S.members.map(m=>`<div class="um"><b>${esc(m.name)}</b>
    <span class="grp"><select data-m="${m.id}" data-f="care" aria-label="${esc(m.name)} care">${Object.entries(CARE).map(([k,l])=>`<option value="${k}" ${m.care===k?"selected":""}>${l}</option>`).join("")}</select>${srcTag(m.src.care)}</span>
    ${isAdult(m)?`<span class="grp"><label><input type="checkbox" data-m="${m.id}" data-f="pregnant" aria-label="${esc(m.name)} giving birth in 2027" ${born(m)?"checked":""}> giving birth in 2027</label>${srcTag(m.src.pregnant)}</span>`:""}</div>`).join("");
  lockInputs();
}
function renderResult(flash){
  const A=S.A; document.body.classList.toggle("noans",!A);
  renderUnderstood(); setNote(); renderWhatIf(); updateGo();
  if(A){
    const res=V(A,"plan_results")||[], tot=V(A,"plan_totals")||[], best=V(A,"best_plan"), sav=Number(V(A,"savings")), by=V(A,"choose_by");
    const T=Object.fromEntries(tot.map(t=>[t.plan,t])), bp=res.find(r=>r.plan===best)||res[0];
    const second=res.filter(r=>r.plan!==bp.plan).sort((a,b)=>T[a.plan].total-T[b.plan].total)[0];
    $("hero").innerHTML=heroHTML(bp,second,T,sav,by);
    renderStories();
    const maxT=Math.max(...res.map(r=>T[r.plan].total));
    $("plans").innerHTML=res.map(r=>`<button class="plan${r.plan===best?" best":""}" type="button" data-plan-pick="${r.plan}">
      <span class="pn">${esc(r.name)}${r.plan===best?" · cheapest for you":""}</span>
      <span class="rowv"><span>Premium <i>same for everyone</i></span><span>${money(r.premium)}</span></span>
      <span class="rowv"><span>+ Your care <i>your year</i></span><span>${money(r.care_cost)}</span></span>
      <span class="stack" aria-hidden="true"><span class="p" style="width:${r.premium/maxT*100}%"></span><span class="c" style="width:${r.care_cost/maxT*100}%"></span></span>
      <span class="rowv tot"><span>= Your 2027</span><b>${money(T[r.plan].total)}</b></span>
      <small>Worst case: up to ${money(T[r.plan].worst_case)}</small>
      <span class="terms">Deductible ${money(r.deductible)} · then ${Math.round(r.coinsurance*100)}% · limit ${money(r.oop_max)}</span>
      <span class="seer">See its receipt ↓</span></button>`).join("");
    if(flash){ const h=$("hero"); h.classList.remove("flash"); void h.offsetWidth; h.classList.add("flash"); }
  }
  renderReceipts(); renderCall();
}
// Presentation only: every amount below comes from the decision output.
const delta=(a,b)=>{ const d=Number(a)-Number(b); return Math.abs(d)<1?`<span class="d same">same</span>`:`<span class="d ${d<0?"good":"bad"}">${d<0?"−":"+"}${money(Math.abs(d))}</span>`; };
function whyText(w,r){
  const dp=w.premium-r.premium, dc=w.care_cost-r.care_cost, W=esc(w.name), R=esc(r.name);
  if(Math.abs(dp)<0.5) return `${W} and ${R} have the same premium, and you'd pay ${money(-dc)} less for care on ${W}.`;
  if(dp>0) return `${W}'s premium is ${money(dp)} higher than ${R}'s, but you'd pay ${money(-dc)} less for care.`;
  if(Math.abs(dc)<1) return `${W}'s premium is ${money(-dp)} lower than ${R}'s, and your care costs the same.`;
  if(dc>0) return `${W}'s premium is ${money(-dp)} lower than ${R}'s, more than the ${money(dc)} extra you'd pay for care.`;
  return `${W} costs less than ${R} on both the premium and your care.`;
}
function heroHTML(bp,second,T,sav,by){
  const wn=whatNow();
  const main=`<div class="hero-main"><span class="kick">${wn?`What if: ${esc(wn.label)}`:"Cheapest for your 2027"}</span><div class="win">${esc(bp.name)}</div>
    <div class="amt"><b>${money(T[bp.plan].total)}</b> expected</div>
    ${second?`<div class="save">Saves ${money(sav)} vs ${esc(second.name)}</div>`:""}
    <div class="due">Pick by ${fmtDate(V(S.A,"choose_by")||DEADLINE)}, the HealthCare.gov deadline for coverage from Jan 1.</div></div>`;
  if(!second) return main;
  const rows=[["Premium",bp.premium,second.premium],["Your care",bp.care_cost,second.care_cost],["Expected 2027",T[bp.plan].total,T[second.plan].total],["Bad year",T[bp.plan].worst_case,T[second.plan].worst_case]];
  return main+`<div class="hero-diff"><span class="kick">Key differences vs ${esc(second.name)}</span>
    <div class="tablewrap"><table class="diff"><thead><tr><th></th><th class="w">${esc(bp.name)}</th><th>${esc(second.name)}</th><th></th></tr></thead><tbody>
    ${rows.map(([l,a,b])=>`<tr><td>${l}</td><td class="w">${money(a)}</td><td>${money(b)}</td><td>${delta(a,b)}</td></tr>`).join("")}</tbody></table></div>
    <p class="whyline">${whyText(bp,second)}</p></div>`;
}
function renderWhatIf(){
  const ws=WHATIF[S.key]||[], rec=RECORDINGS[S.key], box=$("whatif");
  if(!ws.length){ box.innerHTML=""; box.hidden=true; return; }
  box.hidden=false;
  box.innerHTML=`<span class="kick">What if…</span><div class="wis">${ws.map(w=>{
    const off=!live()&&!(rec&&rec.whatif&&rec.whatif[w.id]);
    return `<button class="wi" type="button" data-what="${w.id}" aria-pressed="${S.what===w.id}"${off?' disabled title="Set your aityx key to try this one live"':""}><span class="sw" aria-hidden="true"></span>${esc(w.label)}</button>`; }).join("")}</div>`;
}
function toggleWhat(id){
  S.what=S.what===id?null:id;
  if(live()){ renderWhatIf(); settleLive(); return; }
  const rec=RECORDINGS[S.key]; if(!rec) return;
  const w=whatNow(), r=w&&rec.whatif&&rec.whatif[w.id];
  if(w&&!r){ S.what=null; renderWhatIf(); return; }
  S.recCall=r?r.call:rec.call; S.A=S.recCall.res.answers; renderResult(true);
  liveNote(w?`What if: ${w.label}. Recorded rules-only aityx call on ${r.when}, no AI.`:`Recorded from a real aityx call on ${rec.when}. Set your aityx key above to change the plans and price them live.`,"ok");
}
function renderStories(){
  const box=$("stories");
  box.innerHTML=Object.keys(SAMPLES).filter(k=>RECORDINGS[k]).map(k=>{
    const A=RECORDINGS[k].call.res.answers, best=V(A,"best_plan"), r=(V(A,"plan_results")||[]).find(x=>x.plan===best), t=(V(A,"plan_totals")||[]).find(x=>x.plan===best);
    if(!r||!t) return "";
    return `<button class="story" type="button" data-story="${k}" aria-current="${k===S.key}"><span class="w">${esc(SAMPLES[k].label)}: <em>${esc(r.name)}</em> wins</span><span class="n">${money(t.total)}</span><small>${esc(SAMPLES[k].members.map(m=>m.name).join(", "))}</small></button>`;
  }).join("");
  box.parentElement.hidden=!box.innerHTML.trim();
}
function compare(){
  document.body.classList.remove("pending"); if(live()) readLive(); else showRecorded();
  $("result").scrollIntoView({behavior:matchMedia("(prefers-reduced-motion: reduce)").matches?"auto":"smooth",block:"start"});
}
function receiptHTML(r,T,best,bp,cov){
  const pct=Math.round(r.coinsurance*100), byId=Object.fromEntries(effMembers().map(m=>[m.id,m]));
  const sumPays=r.lines.reduce((s,l)=>s+Number(l.pays),0), capped=sumPays-Number(r.care_cost);
  const lines=[`<div class="line"><span><span class="src src-rule">plan rule</span>Premium, ${cov==="family"?"family":"just you"}</span><span class="v">${money(r.premium)}</span><span class="why">Your share for the whole year.</span></div>`]
    .concat(r.lines.map(l=>{ const m=byId[l.id];
      const tag=l.id==="newborn"?`<span class="src src-rule">plan rule</span>`:srcTag(m&&(m.src.care==="whatif"||m.src.pregnant==="whatif")?"whatif":l.birth?(m&&m.src.pregnant):(m&&m.src.care));
      const what=l.id==="newborn"?"":`, ${CARE[l.care]||l.care}${l.birth?" + birth":""}`;
      return `<div class="line"><span>${tag}${esc(l.name)}${what}</span><span class="v">${money(l.pays)}</span><span class="why">Care expected: ${money(l.spend)}. You pay the first ${money(r.deductible)}, then ${pct}% of the rest, up to ${money(r.oop_max)}.</span></div>`; }));
  if(capped>0.5) lines.push(`<div class="line"><span><span class="src src-rule">plan rule</span>Family limit</span><span class="v">−${money(capped)}</span><span class="why">A family never pays more than ${money(r.cap)} for care.</span></div>`);
  const diff=T[r.plan].total-T[best].total;
  return `<div class="rh"><b>${esc(r.name)} plan · 2027</b><span>${esc(S.members.map(m=>m.name).join(", "))}${S.members.length&&r.lines.some(l=>l.id==="newborn")?" + newborn":""}</span></div>
    <div class="lines">${lines.join("")}</div>
    <div class="total"><span>Expected 2027</span><span class="v">${money(T[r.plan].total)}</span></div>
    <div class="verdict">${r.plan===best?`<b>Cheapest for you.</b> In a bad year: up to ${money(T[r.plan].worst_case)}.`:`<b>${money(diff)} more</b> than ${esc(bp.name)}. In a bad year: up to ${money(T[r.plan].worst_case)}.`}</div>
    <div class="key"><span class="src src-ai">AI read this</span> aityx read it in your message · <span class="src src-you">your input</span> you entered or changed it · <span class="src src-rule">plan rule</span> from the plan's rules${whatNow()?` · <span class="src src-what">what if</span> the switch you turned on`:""}</div>
    <div class="stamp">${S.recorded?`Recorded aityx call · ${esc(S.recorded.when)}`:`Priced by aityx · ${new Date().toLocaleDateString("en-CA")}`}</div>`;
}
function renderReceipts(){
  const A=S.A; if(!A){ $("receipts").innerHTML=""; return; }
  const res=V(A,"plan_results")||[], tot=V(A,"plan_totals")||[], best=V(A,"best_plan"), cov=V(A,"coverage");
  const T=Object.fromEntries(tot.map(t=>[t.plan,t])), bp=res.find(x=>x.plan===best)||res[0];
  $("receipts").innerHTML=res.map(r=>`<div class="rcol${r.plan===best?" best":""}" id="rc-${r.plan}">
    <span class="rtag">${r.plan===best?"★ Cheapest for you":`+${money(T[r.plan].total-T[best].total)} vs ${esc(bp.name)}`}</span>
    <div class="receipt">${receiptHTML(r,T,best,bp,cov)}</div>
    <button class="ghost" type="button" data-copyrc="${r.plan}">Copy ${esc(r.name)} receipt</button></div>`).join("");
}
function receiptText(plan){
  const A=S.A; if(!A) return "";
  const r=(V(A,"plan_results")||[]).find(x=>x.plan===plan), t=(V(A,"plan_totals")||[]).find(x=>x.plan===plan); if(!r||!t) return "";
  return [`${r.name} plan, 2027`,`Premium: ${money(r.premium)}`].concat(r.lines.map(l=>`${l.name}: ${money(l.pays)} (care ${money(l.spend)})`))
    .concat([`Expected 2027: ${money(t.total)}`,`Bad year: up to ${money(t.worst_case)}`,"Priced with aityx"]).join("\n");
}
function hl(o){ return esc(JSON.stringify(o,null,2)).replace(/&quot;([^&]*?)&quot;(\s*:)/g,'<span class="k">"$1"</span>$2').replace(/: &quot;(.*?)&quot;/g,': <span class="s">"$1"</span>'); }
// Developer view: the exact request and response bodies, pretty-printed, with the fields that matter highlighted.
const COPYJ={};
const VALUE_FIELDS=["choice","noul","value","number","date","level","score"];
function hotOf(kind,p,jev){
  if(kind==="req") return p.length===1&&p[0]==="state"?2:0;
  if(p[0]!=="answers"||p.length<2) return 0;
  if(p.length===2&&["best_plan","savings","plan_totals"].includes(p[1])) return 1;
  if(p.length===3&&jev.has(p[1])&&VALUE_FIELDS.includes(p[2])) return 1;
  if(p.length===5&&p[1]==="plan_results"&&p[2]==="value"&&["premium","care_cost"].includes(p[4])) return 2;
  return 0;
}
function jsonHTML(v,kind,path,ind,jev){
  if(v===null||typeof v!=="object") return `<span class="${typeof v==="string"?"s":"n"}">${esc(JSON.stringify(v))}</span>`;
  const arr=Array.isArray(v), ents=arr?v.map((x,i)=>[i,x]):Object.entries(v);
  if(!ents.length) return arr?"[]":"{}";
  const pad="  ".repeat(ind);
  return (arr?"[":"{")+"\n"+ents.map(([k,x])=>{
    const p=path.concat(k), h=hotOf(kind,p,jev);
    const kv=(arr?"":`<span class="k">${esc(JSON.stringify(k))}</span>: `)+jsonHTML(x,kind,p,ind+1,jev);
    return pad+"  "+(h?`<span class="hot${h===2?" soft":""}"${h===1?` id="res-${esc(String(p[1]))}"`:""}>${kv}</span>`:kv);
  }).join(",\n")+"\n"+pad+(arr?"]":"}");
}
function renderCall(){
  let c=null, note="";
  if(live()&&LIVE.call){ c=LIVE.call; note=LIVE.conn.source==="dev"?`Live. POST ${endpoint()}, the index server's dev proxy, which adds its key.`:`Live. POST ${endpoint()} with Authorization: Bearer aityx_sk_…`; }
  else if(S&&S.recorded&&!live()){ c=S.recCall||S.recorded.call; note=`Recorded from a real aityx call on ${S.recorded.when}. POST /v1/systemone.`; }
  $("devnote").textContent=note;
  if(!c){ $("calls").innerHTML=`<p class="note">${live()?"Press Compare plans to see the real call.":"Set your aityx key above to see the real call."} Nothing runs without aityx.</p>`; return; }
  const jevKeys=Object.keys(c.req&&c.req.questions||{}), jev=new Set(jevKeys), ans=c.res&&c.res.answers||{};
  COPYJ.req=JSON.stringify(c.req,null,2); COPYJ.res=JSON.stringify(c.res,null,2);
  const firstJev=jevKeys.find(k=>k in ans);
  const jumps=["best_plan","savings","plan_totals"].filter(k=>k in ans).map(k=>[k,`res-${k}`]).concat(firstJev?[["What aityx read",`res-${firstJev}`]]:[]);
  const title=jevKeys.length?"One call · aityx reads the message, then the rules price the plans":"One call · the rules price the plans again, no AI";
  $("calls").innerHTML=`<div class="call"><div class="callh"><b>${title}</b><span>${c.status?`HTTP ${c.status}`:"recorded"}</span></div>
    <div class="json">
      <div><div class="jh"><h4>Request</h4><button class="mini" type="button" data-copy="req">Copy JSON</button></div><pre>${jsonHTML(c.req,"req",[],0,jev)}</pre></div>
      <div><div class="jh"><h4>Response</h4>${jumps.map(([l,t])=>`<button class="jump" type="button" data-jump="${esc(t)}">${esc(l)}</button>`).join("")}<button class="mini" type="button" data-copy="res">Copy JSON</button></div><pre>${jsonHTML(c.res,"res",[],0,jev)}</pre></div>
    </div></div>`;
}
function countdown(){
  const days=Math.ceil((new Date(DEADLINE+"T23:59:59-05:00")-Date.now())/864e5);
  $("countdown").innerHTML=days>0?`<b>${days}</b> days to pick a plan`:"Open enrollment deadline passed";
}

/* ---------- misc ---------- */
let toastT;
function toast(m){ let t=document.querySelector(".toast"); if(!t){t=document.createElement("div");t.className="toast";t.setAttribute("role","status");document.body.appendChild(t);} t.textContent=m; t.hidden=false; clearTimeout(toastT); toastT=setTimeout(()=>t.hidden=true,1800); }
async function copy(txt){ try{ await navigator.clipboard.writeText(txt); toast("Copied"); }catch(e){ const ta=document.createElement("textarea"); ta.value=txt; document.body.appendChild(ta); ta.select(); try{document.execCommand("copy");toast("Copied");}catch(_){toast("Select and copy the text");} ta.remove(); } }

// The key lives on the aityx demos page. Embedded in the aityx website, the page around asks for it instead.
document.addEventListener("click",e=>{ const a=e.target.closest("a.keylink"); if(a&&Aityx.embedded){ e.preventDefault(); Aityx.openKeyPage(); } });
document.addEventListener("click",e=>{
  const b=e.target.closest("button"); if(!b||b.disabled) return;
  if(b.dataset.what){ toggleWhat(b.dataset.what); return; }
  if(b.id==="caret"){ menuOpen($("menu").hidden); return; }
  if(b.id==="rand"){ fillRandom(); return; }
  if(b.dataset.k){ pick(b.dataset.k); return; }
  if(b.dataset.planPick){ const el=$("rc-"+b.dataset.planPick); if(el){ el.scrollIntoView({behavior:matchMedia("(prefers-reduced-motion: reduce)").matches?"auto":"smooth",block:"center"}); el.classList.remove("flash"); void el.offsetWidth; el.classList.add("flash"); } return; }
  if(b.dataset.copyrc){ copy(receiptText(b.dataset.copyrc)); return; }
  if(b.dataset.copy){ copy(COPYJ[b.dataset.copy]||""); return; }
  if(b.dataset.jump){ const el=document.getElementById(b.dataset.jump); if(!el) return; const pre=el.closest("pre");
    pre.scrollTo({top:Math.max(0,el.offsetTop-8),behavior:matchMedia("(prefers-reduced-motion: reduce)").matches?"auto":"smooth"});
    el.classList.remove("flash"); void el.offsetWidth; el.classList.add("flash"); return; }
  if(b.dataset.chip){ const t=$("msg"); const add=(t.value.trim()?" ":"")+b.dataset.chip; if(t.value.length+add.length<=600){ t.value=t.value.trimEnd()+add; countChars(); msgChanged(); } return; }
  if(b.dataset.chipr){ $("msg").value=b.dataset.chipr; countChars(); msgChanged(); return; }
  if(b.dataset.del){ if(S.members.length<2) return; S.members=S.members.filter(m=>m.id!==b.dataset.del); renderFamily(); setNote(); queueLive(); return; }
  if(b.id==="add"){ if(S.members.length>=MAX_PEOPLE) return; S.n++; S.members.push({id:`p${S.n}`,name:`Person ${S.members.length+1}`,age:30,care:"light",pregnant:0,src:{care:"you",pregnant:"you"}});
    renderFamily(); setNote(); if(S.A) renderUnderstood(); queueLive(); const i=$("fam").querySelectorAll("input[type=text]"); i[i.length-1].select(); return; }
  if(b.id==="go"){ if(live()&&S.jevRead&&!document.body.classList.contains("pending")) compareAgain(); else compare(); return; }
  if(b.classList.contains("againbtn")){ compareAgain(); return; }
  if(b.dataset.story){ load(b.dataset.story); compare(); return; }
  if(b.id==="recall"){ recordAll(); return; }
  if(b.id==="recheck"){ refreshConnection(); return; }
  if(b.id==="rec"&&LIVE.rec){ copy(JSON.stringify({[LIVE.rec.key]:LIVE.rec})); return; }
});
document.addEventListener("input",e=>{
  const t=e.target;
  if(t.id==="msg"){ countChars(); if(live()) msgChanged(); return; }
  if(t.dataset.m&&(t.dataset.f==="name"||t.dataset.f==="age")){ const m=S.members.find(x=>x.id===t.dataset.m);
    if(t.dataset.f==="name"){ m.name=t.value.trim()||"Someone"; } else { const v=parseInt(t.value,10); if(isNaN(v)) return; m.age=Math.max(0,Math.min(110,v)); if(!isAdult(m)){ m.pregnant=0; } }
    if(S.A) renderUnderstood(); queueLive(); return; }
  if(t.dataset.plan){ const p=S.plans.find(x=>x.id===t.dataset.plan), v=parseFloat(t.value); if(isNaN(v)) return;
    p[t.dataset.f]=t.dataset.f==="coinsurance"?Math.max(0,Math.min(100,v))/100:Math.max(0,v); queueLive(); return; }
  if(t.dataset.price){ const v=parseFloat(t.value); if(isNaN(v)) return; S.prices[t.dataset.price]=Math.max(0,v); queueLive(); return; }
});
document.addEventListener("change",e=>{
  const t=e.target; if(!t.closest("#understood")) return;
  const m=S.members.find(x=>x.id===t.dataset.m);
  if(t.dataset.f==="care"){ m.care=t.value; m.src.care="you"; }
  if(t.dataset.f==="pregnant"){ m.pregnant=t.checked?1:0; m.src.pregnant="you"; }
  renderUnderstood(); queueLive();
});

countdown(); load("baby"); connectUI(); refreshConnection();

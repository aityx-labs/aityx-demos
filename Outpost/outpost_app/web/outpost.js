(()=>{
'use strict';
const $=id=>document.getElementById(id);
const esc=s=>String(s).replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
const HOURS=["8 PM","10 PM","Midnight","2 AM","4 AM","6 AM"];
const PHASES=[
  {name:"Village",text:"A few houses and streetlights. Learn the ropes.",houses:5,has_lights:true,has_hospital:false,has_factory:false,sun:8,wind:[2,2,1,1,2,2]},
  {name:"Town",text:"A hospital opens tonight. It must never go dark.",houses:7,has_lights:true,has_hospital:true,has_factory:false,sun:7,wind:[2,1,1,1,1,2]},
  {name:"Industry",text:"A factory arrives. It pays to keep it running, but it is hungry.",houses:8,has_lights:true,has_hospital:true,has_factory:true,sun:7,wind:[2,2,1,1,1,2]},
  {name:"Storm",text:"Clouds all day, strong wind all night.",houses:9,has_lights:true,has_hospital:true,has_factory:true,sun:3,wind:[5,6,6,5,4,3],wx:"storm"},
  {name:"Winter",text:"The longest, coldest night. More houses than ever.",houses:10,has_lights:true,has_hospital:true,has_factory:true,sun:5,wind:[2,2,1,1,2,2],wx:"snow"},
  // from night 6 the city grows south: each new public building counts as one more house on the grid (same energy, same penalty)
  {name:"Market",text:"A supermarket opens on the south side. One more building to keep lit.",houses:11,civic:["market"],has_lights:true,has_hospital:true,has_factory:true,sun:6,wind:[2,1,1,1,1,2],wx:"autumn"},
  {name:"School",text:"The new school opens just as a storm rolls in.",houses:12,civic:["market","school"],has_lights:true,has_hospital:true,has_factory:true,sun:3,wind:[4,5,5,4,3,3],wx:"storm"},
  {name:"Pharmacy",text:"A pharmacy opens. A hot, still night: almost no wind.",houses:13,civic:["market","school","pharmacy"],has_lights:true,has_hospital:true,has_factory:true,sun:6,wind:[1,1,1,1,1,1]},
  {name:"Fire station",text:"The fire station opens on the first snow of the year.",houses:14,civic:["market","school","pharmacy","fire"],has_lights:true,has_hospital:true,has_factory:true,sun:4,wind:[2,2,1,1,2,2],wx:"snow"},
  {name:"Library",text:"The library opens. A heavy storm and little sun.",houses:15,civic:["market","school","pharmacy","fire","library"],has_lights:true,has_hospital:true,has_factory:true,sun:3,wind:[4,4,3,3,3,2],wx:"storm"}];
PHASES.forEach(p=>{ p.civic=p.civic||[]; p.homes=p.houses-p.civic.length; p.wx=p.wx||(PHASES.indexOf(p)===5?"autumn":"clear"); });
// after night 10 there is no new building, only a little less sun every night: the city cannot hold forever
function ensurePhase(n){ while(PHASES.length<=n){ const i=PHASES.length, L=PHASES[9];
  PHASES.push({...L,civic:[...L.civic],name:"The long dark",text:"A little less sun every night. How long can the city hold?",sun:Math.max(1,4-Math.floor((i-9)/2)),wind:[2,2,1,1,2,2],wx:i%2?"snow":"storm"}); } return PHASES[n]; }
const START={panels:5,capacity:100,turbines:0};
const BUILDS={panel:{name:"Solar panel",what:"More energy stored by day"},battery:{name:"Battery",what:"+30 storage for the night"},turbine:{name:"Wind turbine",what:"Adds the wind, every hour"}};
const ITEMS={lights:"Streetlights",factory:"Factory",houses:"Houses"};
const REC=window.OUTPOST_RECORDINGS||{}; if(REC.factory) REC.factory.label="Houses go dark first";
let REC_MODE=/record/i.test(location.hash+location.search);
addEventListener("hashchange",()=>{REC_MODE=/record/i.test(location.hash+location.search);ui();});

/* ---------- the decision: the night, hour by hour. Every number on the page comes from here ---------- */
function decision(rules){
  const n=(d,e,t="number")=>({type:t,desc:d,expr:String(e)});
  const serve=[...rules.order].reverse(); // last to go dark is served first
  const D={
    "panel_yield":n("Energy one panel stores per point of sunlight",4),"battery_step":n("Storage one battery adds",30),
    "house_load":n("Energy one house uses per night hour",2),"lights_load":n("Energy the streetlights use per hour",3),
    "hospital_load":n("Energy the hospital uses per hour",4),"factory_load":n("Energy the factory uses per hour",6),
    "house_dark_penalty":n("Approval lost per house per hour in the dark",3),"lights_dark_penalty":n("Approval lost per hour of dark streetlights",1),
    "factory_storage":n("Battery storage the city gains for each hour the factory runs",5),"pass_approval":n("Approval needed to pass the night",50),
    "lights_off_after_midnight":n("Player rule: switch the streetlights off after midnight",rules.lightsMidnight,"boolean"),
    "factory_at_night":n("Player rule: keep the factory running at night",rules.factoryNight,"boolean"),
    "panels_now":{type:"number",desc:"Panels after today's build",expr:"panels + (if build = \"panel\" then 1 else 0)"},
    "turbines_now":{type:"number",desc:"Turbines after today's build",expr:"turbines + (if build = \"turbine\" then 1 else 0)"},
    "capacity_now":{type:"number",desc:"Battery capacity after today's build",expr:"capacity + (if build = \"battery\" then battery_step else 0)"},
    "dusk_battery":{type:"number",desc:"Energy stored at dusk: what the panels made by day, up to capacity",expr:"min(capacity_now, panels_now * sun * panel_yield)"}
  };
  for(let h=1;h<=6;h++){
    const p=`h${h}_`, prev=h===1?"dusk_battery":`h${h-1}_left`;
    D[p+"avail"]={type:"number",desc:`Energy available in night hour ${h}: battery plus wind`,expr:`${prev} + wind[${h}] * turbines_now`};
    D[p+"hospital_on"]={type:"boolean",desc:`Hospital powered in hour ${h}. It is always served first`,expr:`has_hospital and ${p}avail >= hospital_load`};
    let cur=`(${p}avail - (if ${p}hospital_on then hospital_load else 0))`;
    serve.forEach((it,i)=>{
      const k=`${p}s${i}`;
      if(it==="lights"){
        D[p+"lights_on"]={type:"boolean",desc:`Streetlights on in hour ${h}`,expr:`has_lights and ${h>3?"not(lights_off_after_midnight) and ":""}${cur} >= lights_load`};
        D[k]={type:"number",desc:"Energy left after the streetlights",expr:`${cur} - (if ${p}lights_on then lights_load else 0)`};
      } else if(it==="factory"){
        const lightsNeed=k2=>`(if has_lights${k2>3?" and not(lights_off_after_midnight)":""} then lights_load else 0)`;
        const need=k2=>`max(0, houses * house_load + (if has_hospital then hospital_load else 0) + ${lightsNeed(k2)} - wind[${k2}] * turbines_now)`;
        const after=serve.slice(i+1), now=[];   // what is still served after the factory in this same hour
        if(after.includes("houses")) now.push("houses * house_load");
        if(after.includes("lights")) now.push(lightsNeed(h));
        const later=Array.from({length:6-h},(_,q)=>need(h+q+1));
        D[p+"reserve"]={type:"number",desc:"Energy the factory must leave for the houses, hospital and streetlights until morning",expr:[...now,...later].join(" + ")||"0"};
        D[p+"factory_on"]={type:"boolean",desc:`Factory on in hour ${h}: it only uses spare power, never what the houses, hospital and streetlights will need before morning`,expr:`has_factory and factory_at_night and ${cur} - factory_load >= ${p}reserve`};
        D[k]={type:"number",desc:"Energy left after the factory",expr:`${cur} - (if ${p}factory_on then factory_load else 0)`};
      } else {
        D[p+"houses_lit"]={type:"number",desc:`Houses with power in hour ${h}`,expr:`min(houses, floor(${cur} / house_load))`};
        D[k]={type:"number",desc:"Energy left after the houses",expr:`${cur} - ${p}houses_lit * house_load`};
      }
      cur=k;
    });
    D[p+"left"]={type:"number",desc:`Energy stored after hour ${h}`,expr:`min(capacity_now, ${cur})`};
    D[p+"approval"]={type:"number",desc:`Approval so far, after hour ${h}`,expr:`max(0, 100 - (${Array.from({length:h},(_,k)=>`(houses - h${k+1}_houses_lit)`).join(" + ")}) * house_dark_penalty - (${Array.from({length:h},(_,k)=>`(if h${k+1}_lights_wanted and not(h${k+1}_lights_on) then 1 else 0)`).join(" + ")}) * lights_dark_penalty)`};
    D[p+"lights_wanted"]={type:"boolean",desc:`Streetlights should be on in hour ${h} under your rules`,expr:`has_lights${h>3?" and not(lights_off_after_midnight)":""}`};
  }
  const H=[1,2,3,4,5,6];
  Object.assign(D,{
    "dark_house_hours":{type:"number",desc:"House-hours spent in the dark",expr:H.map(h=>`(houses - h${h}_houses_lit)`).join(" + ")},
    "dark_light_hours":{type:"number",desc:"Hours the streetlights should have been on but were dark",expr:H.map(h=>`(if h${h}_lights_wanted and not(h${h}_lights_on) then 1 else 0)`).join(" + ")},
    "hospital_failed":{type:"boolean",desc:"Did the hospital go dark at any hour?",expr:`has_hospital and not(${H.map(h=>`h${h}_hospital_on`).join(" and ")})`},
    "factory_all_night":{type:"boolean",desc:"Did the factory run every hour?",expr:`has_factory and factory_at_night and ${H.map(h=>`h${h}_factory_on`).join(" and ")}`},
    "factory_hours":{type:"number",desc:"Hours the factory ran tonight",expr:H.map(h=>`(if h${h}_factory_on then 1 else 0)`).join(" + ")},
    "approval":{type:"number",desc:"City approval at dawn, 0 to 100",expr:"max(0, min(100, 100 - dark_house_hours * house_dark_penalty - dark_light_hours * lights_dark_penalty))"},
    "passed":{type:"boolean",desc:"The city made it: the hospital never went dark and approval stayed at or above the bar",expr:"not(hospital_failed) and approval >= pass_approval"},
    "stars":{type:"number",desc:"Stars for the night",table:[["passed","approval","=> number","# why"],["false","-","0","The night was lost."],["-",">= 90","3","Almost nobody noticed the night."],["-",">= 70","2","Some houses went dark, but the city coped."],["-","-","1","The city made it, barely."]]},
    "hours":{type:["Hour"],desc:"Each night hour, for drawing",expr:"["+H.map(h=>`{hour: ${h}, available: h${h}_avail, hospital_on: h${h}_hospital_on, lights_on: h${h}_lights_on, factory_on: h${h}_factory_on, houses_lit: h${h}_houses_lit, battery: h${h}_left, approval: h${h}_approval}`).join(", ")+"]"},
    "city_next":{type:"City",desc:"What the city keeps for the next night",expr:"{panels: panels_now, capacity: capacity_now + factory_hours * factory_storage, turbines: turbines_now}"},
    "lines":{type:["Line"],desc:"The night, line by line, with the rule behind each",expr:"[{label: \"Battery at dusk\", value: dusk_battery, why: string(panels_now) + \" panels x sunlight \" + string(sun) + \" x \" + string(panel_yield) + \", up to \" + string(capacity_now)}, {label: \"Wind over the night\", value: (wind[1] + wind[2] + wind[3] + wind[4] + wind[5] + wind[6]) * turbines_now, why: string(turbines_now) + \" turbines\"}, {label: \"House-hours in the dark\", value: dark_house_hours, why: \"Each costs \" + string(house_dark_penalty) + \" approval\"}, {label: \"Streetlight hours in the dark\", value: dark_light_hours, why: if lights_off_after_midnight then \"Your rule turns them off after midnight, that is not counted\" else \"Each costs \" + string(lights_dark_penalty) + \" approval\"}, {label: \"Factory hours\", value: factory_hours, why: if factory_at_night then \"On spare power only. +\" + string(factory_hours * factory_storage) + \" battery storage for the next nights\" else \"Your rule keeps it off at night\"}, {label: \"Hospital\", value: if hospital_failed then 0 else 1, why: if has_hospital then (if hospital_failed then \"It went dark. The night is lost\" else \"Always served first, it stayed on\") else \"No hospital yet\"}, {label: \"Approval at dawn\", value: approval, why: \"You need \" + string(pass_approval) + \" to pass, 90 for three stars\"}]"}
  });
  // order rule shown in the model, for reading
  D["off_first"]={type:"string",desc:"Player rule: what goes dark first when power runs short",expr:`"${rules.order.map(i=>ITEMS[i]).join(", then ")}"`};
  return {"name":"OUTPOST · Mission 02 · How many nights",
    "types":{"Hour":{"hour":"number","available":"number","hospital_on":"boolean","lights_on":"boolean","factory_on":"boolean","houses_lit":"number","battery":"number","approval":"number"},
      "City":{"panels":"number","capacity":"number","turbines":"number"},"Line":{"label":"string","value":"number","why":"string"}},
    "inputs":{
      "phase":{"type":"number > 0","desc":"Which night, 1 to 5","from":"game"},
      "houses":{"type":"number >= 0","desc":"Houses in the city tonight; from night 6 this also counts each new public building, which uses as much as a house","from":"phase"},
      "has_lights":{"type":"boolean","desc":"The city has streetlights","from":"phase"},
      "has_hospital":{"type":"boolean","desc":"The city has a hospital","from":"phase"},
      "has_factory":{"type":"boolean","desc":"The city has a factory","from":"phase"},
      "sun":{"type":"number >= 0","desc":"Sunlight during the day, 0 to 10","from":"phase"},
      "wind":{"type":["number"],"desc":"Wind for each of the 6 night hours, energy per turbine","from":"phase"},
      "panels":{"type":"number >= 0","desc":"Solar panels before today's build","from":"city"},
      "capacity":{"type":"number >= 0","desc":"Battery capacity before today's build","from":"city"},
      "turbines":{"type":"number >= 0","desc":"Wind turbines before today's build","from":"city"},
      "build":{"type":"none|panel|battery|turbine","desc":"What the player builds today","from":"player"}},
    "decisions":D};
}

/* ---------- state ---------- */
/* ---------- the aityx key, as in every aityx demo (packages/aityx_web) ----------
   1. The user's key, set once on the demos page (/demos/#aityx-key): sessionStorage, else localStorage,
      "aityx.key", with "aityx.url" from the same storage (https://api.aityx.ai by default).
      The app calls <url>/v1/systemone itself, with the key as a bearer token.
   2. Else the index server's dev key: GET /demos/aityx/config says whether the server holds one (never the
      key), and calls go through /demos/aityx/v1/systemone, where the server adds it.
   3. Else none: recorded games only.
   This page never saves, shows or logs a key. */
const DEMOS="/demos/", DEFAULT_URL="https://api.aityx.ai";
const EMBED=new URLSearchParams(location.search).get("embed")==="1"&&window.parent!==window;
const LIVE={conn:null};             // the connection aityx accepted: live mode while it is set
const CONN={state:"checking",msg:""};   // none | checking | ok | invalid | error
const live=()=>!!LIVE.conn;
function normUrl(u){ u=String(u||"").trim().replace(/\/+$/,""); try{ const p=new URL(u); if((p.protocol==="https:"||p.protocol==="http:")&&p.host) return u; }catch(_){} return DEFAULT_URL; }
function userKey(){ for(const s of ["sessionStorage","localStorage"]){ try{ const st=window[s], k=st.getItem("aityx.key"); if(k) return {key:k,url:normUrl(st.getItem("aityx.url"))}; }catch(_){} } return null; }
async function resolveConn(){
  const u=userKey(); if(u) return {source:"user",systemone:u.url+"/v1/systemone",key:u.key,url:u.url,whose:"your key"};
  if(!/^https?:$/.test(location.protocol)) return null;
  const ctl=new AbortController(), to=setTimeout(()=>ctl.abort(),10000);
  try{ const r=await fetch(DEMOS+"aityx/config",{headers:{Accept:"application/json"},cache:"no-store",signal:ctl.signal}), c=await r.json();
    if(r.ok&&c&&c.available===true) return {source:"dev",systemone:location.origin+DEMOS+"aityx/v1/systemone",key:null,url:typeof c.url==="string"?c.url:"",
      whose:c.source===".env"?"dev key from .env":c.source==="environment"?"dev key from the environment":"dev key"}; }
  catch(_){} finally{ clearTimeout(to); }
  return null;
}
const headersFor=c=>Object.assign({"Content-Type":"application/json"},c&&c.key?{Authorization:"Bearer "+c.key}:{});
const endpoint=()=>LIVE.conn?LIVE.conn.systemone:DEFAULT_URL+"/v1/systemone";
// the demos page's key section; embedded (?embed=1), the page around the app shows its own key form
function openKey(){ if(EMBED){ window.parent.postMessage("aityx:key","*"); return; } location.assign(DEMOS+"#aityx-key"); }
// the header's way back to the demos page: not shown embedded, where the user stays on the page around the app
if(EMBED) document.getElementById("demoslink").hidden=true;
const V=(a,k)=>{const x=a&&a[k]; if(x==null) return undefined; if(typeof x!=="object"||Array.isArray(x)) return x; for(const f of ["value","choice","number","date","noul","level","score"]) if(f in x) return x[f]; return x;};
let bestNights=0; try{ bestNights=+localStorage.getItem("outpost.nights.survived")||0; }catch(_){}
const RULES_V=2; // v2: the factory runs on spare power only and adds battery storage
const RUNORDER=["perfect","careful","fstop","factory"];
const RUNTITLE={perfect:"Three stars every night",careful:"Careful mayor",fstop:"Factory on at night",factory:"Houses go dark first"};
const RUNINFO={perfect:"Picks every build and rule to get three stars each night.",
  careful:"Plays it safe: the factory stays off at night, the streetlights go off after midnight from night 4, and it builds mostly wind turbines.",
  fstop:"Same builds as the careful mayor, with the factory on at night. It runs on spare power only and adds battery storage.",
  factory:"Puts the houses first in line to go dark and builds only solar panels."};
const freshRules=()=>({order:["lights","factory","houses"],lightsMidnight:false,factoryNight:true});
let G, RP={run:RUNORDER.find(k=>REC[k])||null,timer:0,phase:0,hour:-1,hold:1};
function newGame(){ G={phase:0,city:{...START},start:{...START},build:"panel",rules:freshRules(),stars:[],state:"plan",a:null,hour:-1,timer:0,busy:false}; }
newGame();

/* ---------- aityx ---------- */
function stateFor(ph,city,build){ const P=PHASES[ph]; return {phase:ph+1,houses:P.houses,has_lights:P.has_lights,has_hospital:P.has_hospital,has_factory:P.has_factory,sun:P.sun,wind:P.wind,panels:city.panels,capacity:city.capacity,turbines:city.turbines,build}; }
async function callNight(ph,city,build,rules){
  const body={decision:decision(rules),state:stateFor(ph,city,build)};
  const c=LIVE.conn;
  const res=await fetch(c.systemone,{method:"POST",headers:headersFor(c),body:JSON.stringify(body)});
  const data=await res.json().catch(()=>null);
  if(data&&c.key&&JSON.stringify(data).includes(c.key)) throw Error("Unexpected response.");
  const err=!res.ok?(data&&(data.detail||data.title))||`HTTP ${res.status}`:data&&data.decision_error?(data.decision_error.message||data.decision_error.code):!data||!data.answers?"no answers":null;
  return {req:body,res:data,status:res.status,err};
}
const CONN_TEXT={none:["Replay · no key","No aityx key yet. Set yours on the demos page to play live."],checking:["Checking key…","Checking for an aityx key…"],ok:["Live · ready","Live mode is ready: your nights run on aityx."],invalid:["Key rejected","aityx did not accept the key. Set a new one on the demos page."],error:["Connection error","Couldn't reach aityx."]};
function setConn(st,msg){ CONN.state=st; CONN.msg=msg||""; ui(); }
function dropLive(){ if(!LIVE.conn) return; LIVE.conn=null; clearInterval(G.timer); resetReplay(RP.run); }
// The check the status light makes in every aityx demo: POST {} to systemone. aityx checks the key first,
// so a working key gets 400 invalid_request and no model runs; a bad one, 401.
let checking=null, lastCheck=0;
function checkKey(){
  if(checking) return checking;
  return checking=(async()=>{ try{
    lastCheck=Date.now(); setConn("checking");
    const c=await resolveConn();
    if(!c){ dropLive(); setConn("none"); return; }
    const same=LIVE.conn&&LIVE.conn.systemone===c.systemone&&LIVE.conn.key===c.key;
    const where=c.source==="dev"?"the dev proxy":c.url;
    const ctl=new AbortController(), to=setTimeout(()=>ctl.abort(),15000); let res, data;
    try{ res=await fetch(c.systemone,{method:"POST",signal:ctl.signal,headers:headersFor(c),body:"{}"}); data=await res.json().catch(()=>null); }
    catch(e){ if(!same) dropLive(); setConn("error",e.name==="AbortError"?`No answer from ${where} in 15 s. Check again in a moment.`:`No answer from ${where} (network, CORS or a blocker).`); return; }
    finally{ clearTimeout(to); }
    const str=k=>data&&typeof data[k]==="string"&&(!c.key||!data[k].includes(c.key))?data[k].slice(0,160):"";
    const code=str("code"), detail=str("detail"), said=`HTTP ${res.status}${detail?": "+detail:""}`;
    if(res.status===400&&code==="invalid_request"){
      LIVE.conn=c; setConn("ok",`Live mode is ready, on ${c.whose}: your nights run on aityx.`);
      if(!same){ stopReplay(); newGame(); drawPlan(); setBanner("",""); $("result").textContent=""; note("Connected. Night 1: build something, check your rules, start the night.","ok"); ui(); }
      return; }
    if(res.status===401||res.status===403){ dropLive(); setConn("invalid",c.source==="user"?`aityx answered ${said}: set a new key on the demos page.`:`aityx did not accept the dev key (${said}).`); return; }
    if(!same) dropLive();
    if(c.source==="dev"&&res.status===502&&/^proxy_(unreachable|redirect)$/.test(code)) setConn("error",detail||"The dev proxy could not reach aityx.");
    else setConn("error",`aityx answered ${said}.`);
  } finally{ checking=null; } })();
}
async function startNight(){
  if(!live()||G.busy||G.state!=="plan") return;
  G.busy=true; ui(); note("aityx is running the night…");
  let r; try{ r=await callNight(G.phase,G.city,G.build,G.rules); }catch(e){ G.busy=false; note("Couldn't reach aityx. Check your connection, then start the night again.","warn"); setConn("error","Couldn't reach aityx on the last night. Start the night again to retry."); return; }
  showCall(r.req,r.res,r.status); G.busy=false;
  if(r.status===401||r.status===403){ dropLive(); note("aityx stopped accepting this key. Set a new one on the demos page to keep playing live.","warn"); setConn("invalid","aityx stopped accepting this key. Set a new one on the demos page to keep playing live."); showTab("play"); return; }
  if(!r.res&&r.status>=500){ note(`aityx couldn't run this night (HTTP ${r.status}).`,"warn"); setConn("error",`aityx answered HTTP ${r.status}. Start the night again to retry.`); return; }
  if(r.err){ note(`aityx couldn't run this night: ${r.err}`,"warn"); ui(); return; }
  if(CONN.state!=="ok") CONN.state="ok";
  G.a=r.res.answers; G.state="night"; G.hour=-1; note("");
  G.timer=setInterval(tick,2000); tick();
}
function tick(){
  const hours=V(G.a,"hours")||[];
  if(G.hour>=hours.length-1){ clearInterval(G.timer); G.timer=0; endNight(); return; }
  G.hour++; drawNight(G.phase,G.a,G.hour); ui();
}
function endNight(){
  const a=G.a, ok=V(a,"passed"), st=V(a,"stars");
  drawMorning(G.phase,a); // daylight returns when the night ends (drawing only)
  G.state=ok?"won":"lost"; renderReceipt(a);
  if(ok){ G.stars[G.phase]=Math.max(G.stars[G.phase]||0,st); G.city=V(a,"city_next");
    $("result").innerHTML=`Night ${G.phase+1} survived <span class="stars">${"★".repeat(st)}${"☆".repeat(3-st)}</span> Approval ${Math.round(V(a,"approval"))}%.`;
    setBanner("ok",`Morning · the city made it`);
    if(live()){ clearTimeout(nextDay.t); nextDay.t=setTimeout(nextDay,3200); }   // the next day starts on its own
  } else {
    $("result").innerHTML=`Night ${G.phase+1}: the city went dark. ${V(a,"hospital_failed")?"The hospital lost power.":`Approval fell to ${Math.round(V(a,"approval"))}%.`} It survived ${G.phase} night${G.phase===1?"":"s"}.`;
    setBanner("out",V(a,"hospital_failed")?"Blackout at the hospital":"The city lost faith in you");
    setTimeout(()=>gameOver(G.phase,false),900);
  }
  ui();
}
async function recordAll(){
  if(!live()) return;
  const games={careful:{label:"Careful mayor",plan:[["battery", {"order": ["lights", "factory", "houses"], "lightsMidnight": false, "factoryNight": false}], ["turbine", {"order": ["lights", "factory", "houses"], "lightsMidnight": false, "factoryNight": false}], ["turbine", {"order": ["lights", "factory", "houses"], "lightsMidnight": false, "factoryNight": false}], ["turbine", {"order": ["lights", "factory", "houses"], "lightsMidnight": true, "factoryNight": false}], ["panel", {"order": ["lights", "factory", "houses"], "lightsMidnight": true, "factoryNight": false}], ["turbine", {"order": ["lights", "factory", "houses"], "lightsMidnight": true, "factoryNight": false}], ["panel", {"order": ["lights", "factory", "houses"], "lightsMidnight": true, "factoryNight": false}], ["turbine", {"order": ["lights", "factory", "houses"], "lightsMidnight": true, "factoryNight": false}], ["turbine", {"order": ["lights", "factory", "houses"], "lightsMidnight": true, "factoryNight": false}], ["turbine", {"order": ["lights", "factory", "houses"], "lightsMidnight": true, "factoryNight": false}], ["panel", {"order": ["lights", "factory", "houses"], "lightsMidnight": true, "factoryNight": false}], ["panel", {"order": ["lights", "factory", "houses"], "lightsMidnight": true, "factoryNight": false}]]},
    perfect:{label:"Three stars every night",plan:[["battery", {"order": ["lights", "factory", "houses"], "lightsMidnight": false, "factoryNight": false}], ["turbine", {"order": ["lights", "factory", "houses"], "lightsMidnight": false, "factoryNight": false}], ["turbine", {"order": ["lights", "factory", "houses"], "lightsMidnight": false, "factoryNight": false}], ["turbine", {"order": ["lights", "factory", "houses"], "lightsMidnight": false, "factoryNight": false}], ["panel", {"order": ["lights", "factory", "houses"], "lightsMidnight": true, "factoryNight": false}], ["turbine", {"order": ["lights", "factory", "houses"], "lightsMidnight": true, "factoryNight": false}], ["panel", {"order": ["lights", "factory", "houses"], "lightsMidnight": false, "factoryNight": false}], ["battery", {"order": ["lights", "factory", "houses"], "lightsMidnight": true, "factoryNight": false}], ["panel", {"order": ["lights", "factory", "houses"], "lightsMidnight": true, "factoryNight": false}]]},
    fstop:{label:"Factory on at night",plan:[["battery", {"order": ["factory", "lights", "houses"], "lightsMidnight": false, "factoryNight": true}], ["turbine", {"order": ["factory", "lights", "houses"], "lightsMidnight": false, "factoryNight": true}], ["turbine", {"order": ["factory", "lights", "houses"], "lightsMidnight": false, "factoryNight": true}], ["turbine", {"order": ["factory", "lights", "houses"], "lightsMidnight": true, "factoryNight": true}], ["panel", {"order": ["factory", "lights", "houses"], "lightsMidnight": true, "factoryNight": true}], ["turbine", {"order": ["factory", "lights", "houses"], "lightsMidnight": true, "factoryNight": true}], ["panel", {"order": ["factory", "lights", "houses"], "lightsMidnight": true, "factoryNight": true}], ["turbine", {"order": ["factory", "lights", "houses"], "lightsMidnight": true, "factoryNight": true}], ["turbine", {"order": ["factory", "lights", "houses"], "lightsMidnight": true, "factoryNight": true}], ["turbine", {"order": ["factory", "lights", "houses"], "lightsMidnight": true, "factoryNight": true}], ["panel", {"order": ["factory", "lights", "houses"], "lightsMidnight": true, "factoryNight": true}], ["panel", {"order": ["factory", "lights", "houses"], "lightsMidnight": true, "factoryNight": true}]]},
    factory:{label:"Houses go dark first",plan:[["panel",{order:["houses","lights","factory"],lightsMidnight:false,factoryNight:true}],["panel",{order:["houses","lights","factory"],lightsMidnight:false,factoryNight:true}]]}};
  // only the games that are not embedded yet; the file still carries all of them
  const missing=Object.keys(games).filter(k=>!REC[k]||REC[k].rv!==RULES_V), todo=missing.length?missing:Object.keys(games);
  const out=Object.fromEntries(Object.entries(REC).filter(([k])=>games[k]&&!todo.includes(k))), when=new Date().toLocaleDateString("en-CA");
  for(const [k,g] of Object.entries(games).filter(([k])=>todo.includes(k))){
    let city={...START}; const nights=[];
    for(let ph=0;ph<g.plan.length;ph++){
      const [build,rules]=g.plan[ph]; ensurePhase(ph); note(`Recording "${g.label}", night ${ph+1}…`);
      const r=await callNight(ph,city,build,rules);
      if(r.err){ note(`Recording stopped on "${g.label}", night ${ph+1}: ${r.err}`,"warn"); return; }
      nights.push({build,rules,req:r.req,res:r.res});
      if(!V(r.res.answers,"passed")) break;
      city=V(r.res.answers,"city_next");
    }
    out[k]={label:g.label,when,nights,rv:RULES_V};
  }
  const a=document.createElement("a"); a.href=URL.createObjectURL(new Blob([JSON.stringify(out)],{type:"application/json"})); a.download="outpost-nights-recordings.json";
  document.body.appendChild(a); a.click(); a.remove();
  note(`Recorded ${todo.length} game${todo.length===1?"":"s"} with real aityx calls. Saved outpost-nights-recordings.json (all ${Object.keys(out).length} games) to your Downloads.`,"ok");
}

/* ---------- replay (no key) ---------- */
/* replay only: a cursor makes the recorded choices by day, the way a player does with a key (drawing only; the choices come from the recording) */
function demoPick(night,prev,done){
  const box=$("demopick"), gh=$("ghost"), wrap=box, P=PHASES[RP.phase]||{}, r=night.rules, p=prev||freshRules();
  if(calm()){ done(); return; }
  const ord=o=>o.filter(i=>i!=="factory"||P.has_factory);
  const rules=(o,lm,fn,mv)=>`<span class="lab">Night rules · off first</span><span class="dpo">${ord(o).map(i=>`<span class="${i===mv?"moved":""}">${ITEMS[i]}</span>`).join("›")}</span><span class="dpt ${lm?"on":""}" id="dplm"><i></i>Streetlights off after midnight</span>`+(P.has_factory?`<span class="dpt ${fn?"on":""}" id="dpfn"><i></i>Factory at night</span>`:"");
  $("dpbuild").innerHTML=$("buildbar").innerHTML; $("dpbuild").querySelectorAll("button").forEach(b=>{ b.disabled=false; b.setAttribute("aria-pressed","false"); b.tabIndex=-1; });
  $("dprules").innerHTML=rules(p.order,p.lightsMidnight,p.factoryNight);
  box.classList.remove("out"); box.hidden=false; gh.hidden=false;
  const W=wrap.getBoundingClientRect(); gh.style.transition="none"; gh.style.transform=`translate(${W.width*.85}px,-140px)`; gh.getBoundingClientRect(); gh.style.transition="";
  const to=el=>{ if(!el) return; const a=el.getBoundingClientRect(), w=wrap.getBoundingClientRect(); gh.style.transform=`translate(${a.left-w.left+a.width*.5}px,${a.top-w.top+a.height*.55}px)`; };
  const tap=()=>{ gh.classList.remove("tap"); void gh.getBoundingClientRect(); gh.classList.add("tap"); };
  const steps=[];
  const ordChanged=ord(p.order).join()!==ord(r.order).join(), mv=ordChanged?ord(r.order)[0]:null;
  if(ordChanged) steps.push([()=>to([...$("dprules").querySelectorAll(".dpo span")][ord(p.order).indexOf(mv)]),()=>{ $("dprules").innerHTML=rules(r.order,p.lightsMidnight,p.factoryNight,mv); }]);
  if(!!r.lightsMidnight!==!!p.lightsMidnight) steps.push([()=>to($("dplm")),()=>$("dplm").classList.toggle("on")]);
  if(P.has_factory&&!!r.factoryNight!==!!p.factoryNight) steps.push([()=>to($("dpfn")),()=>$("dpfn").classList.toggle("on")]);
  steps.push([()=>to($("dpbuild").querySelector(`[data-build="${night.build}"]`)),()=>{ const b=$("dpbuild").querySelector(`[data-build="${night.build}"]`); if(b) b.setAttribute("aria-pressed","true"); }]);
  steps.push([()=>to($("dpbuild").querySelector("[data-go]")),()=>{}]);
  let i=0, t=0;
  const next=()=>{ if(!RP.picking){ end(); return; }
    if(i>=steps.length){ t=setTimeout(()=>{ box.classList.add("out"); gh.hidden=true; t=setTimeout(()=>{ box.hidden=true; done(); },300); },350); return; }
    const [move,act]=steps[i++]; move(); t=setTimeout(()=>{ tap(); act(); t=setTimeout(next,550); },800); };
  const end=()=>{ clearTimeout(t); box.hidden=true; gh.hidden=true; };
  demoPick.end=end; t=setTimeout(next,500);
}
function rTick(){
  const run=REC[RP.run]; if(!run){ stopReplay(); return false; }
  if(RP.picking) return true;
  if(RP.hold>0){ RP.hold--; return true; }
  if(RP.hour<0&&!RP.picked){ const nt=run.nights[RP.phase], pv=RP.phase?run.nights[RP.phase-1].rules:null; if(nt){ RP.picking=true; RP.picked=true; demoPick(nt,pv,()=>{ RP.picking=false; if(RP.timer){ clearInterval(RP.timer); RP.timer=setInterval(()=>{ if(!rTick()) stopReplay(); },2800); if(!rTick()) stopReplay(); } }); return true; } }   // the day stays on screen a little longer before night falls
  const night=run.nights[RP.phase]; if(!night){ stopReplay(); return false; }
  const a=night.res.answers, hours=V(a,"hours")||[];
  if(RP.hour<0){ G.rules=night.rules; G.build=night.build; G.phase=RP.phase; showCall(night.req,night.res,200); }
  if(RP.hour<hours.length-1){ RP.hour++; G.state="night"; G.a=a; G.hour=RP.hour; drawNight(RP.phase,a,RP.hour); ui(); return true; }
  // end of this night
  G.a=a; endNight(); note(`Recorded aityx game "${run.label}" · night ${RP.phase+1} · built a ${night.build} · recorded ${run.when}.`,"ok");
  if(V(a,"passed")&&RP.phase<run.nights.length-1){ RP.phase++; ensurePhase(RP.phase); RP.hour=-1; RP.picked=false; RP.hold=1; previewNext(RP.phase); return true; }
  if(V(a,"passed")) setTimeout(()=>gameOver(RP.phase+1,true),900);   // the city was still standing: the recording just ends here
  stopReplay(); return false;
}
function stopReplay(){ clearInterval(RP.timer); RP.timer=0; if(RP.picking){ RP.picking=false; RP.picked=false; if(demoPick.end) demoPick.end(); } ui(); }
function resetReplay(k){ stopReplay(); RP.run=k; RP.phase=0; RP.hour=-1; RP.hold=0; RP.picked=false; RP.picking=false; newGame(); $("result").textContent=""; setBanner("",""); drawPlan(); ui(); }

/* ---------- drawing ---------- */
function setBanner(cls,t){ const b=$("banner"); b.className="banner"+(cls?" "+cls:""); b.textContent=t; b.hidden=!t; }
let shownPhase=null, lastTod=null, frameId=0, duskTimer=0;
const SVGNS="http://www.w3.org/2000/svg", calm=()=>matchMedia("(prefers-reduced-motion: reduce)").matches;
function announce(ph){
  // chapter card + a short fade of the city when the night changes (drawing only)
  const P=PHASES[ph], el=$("levelup"), sc=$("scene"); if(!el) return;
  el.hidden=true; void el.offsetWidth;
  el.className="levelup"; el.style.setProperty("--lv",{storm:"#9ab3eb",snow:"#dff1ff",autumn:"#f2a33a"}[P.wx]||["#a6d6b7","#f07a52","#f2c14e"][Math.min(ph,2)]);
  el.innerHTML=`<div class="k">Night ${ph+1}</div><div class="t">${esc(P.name)}</div><div class="s">${esc(P.text)}</div>`;
  el.hidden=false; clearTimeout(announce.t); announce.t=setTimeout(()=>{ el.hidden=true; },2900);
}
/* ---------- time of day: the light for each step of the existing clock (drawing only) ----------
   tod = "day" (planning) | "dusk" (the moment before 8 PM) | 0..5 (the six night steps: 8 PM .. 6 AM) | "morning" (after the night) */
function light(tod,ph){
  const WX=ensurePhase(ph).wx, STORM=WX==="storm", SNOW=WX==="snow", IND=ph>=2;
  const day=STORM?["#39424f","#6b7584"]:SNOW?["#a8bfd4","#e7eef4"]:IND?["#6aaee3","#ddd5bd"]:["#5db7f2","#a7dbfb"];
  const nTop=STORM?"#04070c":SNOW?"#0b1a36":"#0a1330", nBot=STORM?"#141b27":SNOW?"#2b4068":"#16204a";
  // dark 0..1, warm 0..1, sky top, sky bottom, stars, moon, sun [x,y,r,colour] or null, horizon glow [colour,opacity] or null
  const L={
    day:     [0,0,day[0],day[1],0,0,[640,60,18,SNOW?"#fbfbf3":IND?"#ffd98a":"#ffe08a"],null],
    dusk:    [.5,.7,STORM?"#1d2230":SNOW?"#34497c":"#2b3a78",STORM?"#5b4a4d":SNOW?"#f0b48e":"#f39a62",.15,.35,[668,170,24,"#ff8a4c"],["#ff9a5c",.6]],
    0:       [.92,0,nTop,STORM?"#1b2030":SNOW?"#34467a":"#2a2a5c",.75,1,null,["#6a4f8a",.2]],
    1:       [1,0,nTop,nBot,1,1,null,null],
    2:       [1,0,nTop,nBot,1,1,null,null],
    3:       [1,0,nTop,nBot,1,1,null,null],
    4:       [.86,.08,nTop,STORM?"#232838":SNOW?"#41588a":"#33427a",.5,.75,null,["#e7a3a0",.28]],
    5:       [.42,.6,STORM?"#2c3442":SNOW?"#6f8fc0":"#4f78c0",STORM?"#7d6f6e":SNOW?"#ffd0a6":"#ffb37a",0,0,[676,132,22,"#ffb04c"],["#ffc27a",.65]]};
  L.morning=L.day;
  const [dark,warm,top,bot,stars,moon,sun,glow]=L[tod]??L.day;
  return {dark,warm,top,bot,stars:STORM?0:stars,moon:STORM?0:moon,sun:STORM?null:sun,glow};
}
function paint(inner,dur){
  // new frame fades in over the last one, so light changes smoothly without touching the clock
  const svg=$("scene");
  if(!svg.querySelector("style.sc")) svg.innerHTML=`<style class="sc">${SCENE_CSS}</style>`;
  const frames=[...svg.querySelectorAll("g.frame")]; frames.slice(0,-1).forEach(f=>f.remove());
  const old=frames[frames.length-1], g=document.createElementNS(SVGNS,"g");
  g.setAttribute("class","frame"); g.innerHTML=inner;
  // safety net: whatever the browser does with animations, the frame ends fully drawn
  if(g.querySelector(".grow")) setTimeout(()=>{ g.querySelectorAll(".dust").forEach(e=>e.remove()); g.querySelectorAll(".grow").forEach(e=>e.classList.remove("grow")); },2600);
  if(!old||!dur||calm()){ if(old) old.remove(); svg.appendChild(g); return; }
  g.style.opacity="0"; svg.appendChild(g); g.getBoundingClientRect();
  g.style.transition=`opacity ${dur}ms ease`; g.style.opacity="1";
  setTimeout(()=>{ if(old.isConnected) old.remove(); g.style.transition="none"; g.style.opacity=""; },dur+80);
}
function scene(ph,state,shown){
  // shown(tod) runs when the frame for that moment is on screen (lets the clock read "Dusk" during the sunset)
  clearTimeout(duskTimer); duskTimer=0;
  const grow=shownPhase!==null&&ph===shownPhase+1&&!calm();   // a new chapter: what is new in it gets built on screen
  if(shownPhase!==null&&ph!==shownPhase) announce(ph);
  shownPhase=ph;
  const tod=state.tod??"day", gs=grow?{...state,grow:true}:state, WX=PHASES[ph].wx, gdur=WX==="snow"?1600:WX==="storm"?900:450;
  if(tod===0&&(lastTod==="day"||lastTod==="morning")&&!calm()){
    // Play starts the night at 8 PM: show the sunset first, then settle into 8 PM on the same step
    paint(sceneFrame(ph,gs,"dusk"),grow?gdur:700); lastTod="dusk"; if(shown) shown("dusk");
    duskTimer=setTimeout(()=>{ duskTimer=0; paint(sceneFrame(ph,state,0),900); lastTod=0; if(shown) shown(0); },grow?1500:850);
    return;
  }
  paint(sceneFrame(ph,gs,tod),grow?gdur:lastTod===null?0:tod===5?1300:tod==="morning"?1100:tod===4?1000:800);
  lastTod=tod; if(shown) shown(tod);
}
function previewNext(ph){
  // replay only: after the morning of a won night, build the next chapter in daylight before its dusk (same tick, no timer change)
  clearTimeout(previewNext.t);
  previewNext.t=setTimeout(()=>{ if(lastTod!=="morning"||shownPhase!==ph-1) return;
    scene(ph,{city:G.city,tod:"day"});
    const keep=G.phase; G.phase=ph; ui(); G.phase=keep;   // labels follow the map; the replay itself moves to this night on its next tick
  },400);
}
const SCENE_CSS=`.spin{animation:sp 2.4s linear infinite;transform-box:fill-box;transform-origin:center}@keyframes sp{to{transform:rotate(360deg)}}.spin.fast{animation-duration:.7s}.smoke circle{animation:sm 3s ease-out infinite}@keyframes sm{from{transform:translateY(6px);opacity:.7}to{transform:translateY(-12px);opacity:0}}.smoke.wind circle{animation-name:smw;animation-duration:1.6s}@keyframes smw{from{transform:translate(0,4px);opacity:.7}to{transform:translate(-30px,-2px);opacity:0}}.rain{animation:rn .6s linear infinite}@keyframes rn{to{transform:translate(-110px,480px)}}.snowf{animation:sf 9s linear infinite}@keyframes sf{to{transform:translate(-40px,480px)}}.flash{opacity:0;animation:fl 7s linear infinite}@keyframes fl{0%,86%{opacity:0}87%{opacity:.45}88%{opacity:.05}90%{opacity:.3}93%,100%{opacity:0}}.bolt{opacity:0;animation:bo 7s linear infinite}@keyframes bo{0%,86%{opacity:0}87%,89.5%{opacity:1}90.5%,100%{opacity:0}}.sway{animation:sw 2.2s ease-in-out infinite alternate}@keyframes sw{from{transform:rotate(-6deg)}to{transform:rotate(5deg)}}.windline{opacity:0;animation:wl 2.6s linear infinite}@keyframes wl{0%{transform:translateX(-160px);opacity:0}15%,80%{opacity:.75}100%{transform:translateX(620px);opacity:0}}.ripple{animation:rp 1.4s ease-out infinite}@keyframes rp{from{transform:scale(.4);opacity:.9}to{transform:scale(1.8);opacity:0}}.ghost{opacity:.5;animation:gho 1.4s ease-in-out infinite}@keyframes gho{50%{opacity:.9}}.grow{animation:grow .65s cubic-bezier(.2,.9,.3,1.12) both}@keyframes grow{from{transform:scaleY(0);opacity:0}45%{opacity:1}to{transform:scaleY(1);opacity:1}}.dust{opacity:0;animation:dust .9s ease-out both}@keyframes dust{0%{opacity:0;transform:scale(.3)}25%{opacity:.75}100%{opacity:0;transform:scale(1.7)}}.flash1{opacity:0;animation:f1 1.1s ease-out .15s both}@keyframes f1{0%{opacity:0}8%{opacity:.75}20%{opacity:.1}30%{opacity:.5}100%{opacity:0}}.fadein{animation:fi .5s ease both}@keyframes fi{from{opacity:0}to{opacity:1}}.flow{animation:fw 1.4s linear infinite}@keyframes fw{to{stroke-dashoffset:-14}}.flow.slow{animation-duration:2.8s}.glint{opacity:0;animation:gl 3.4s ease-in-out infinite}@keyframes gl{0%,58%,100%{opacity:0}74%{opacity:var(--gl,.5)}}.flick{opacity:0;animation:fk 1.1s linear 1 both}@keyframes fk{0%{opacity:1}20%{opacity:.15}35%{opacity:.9}55%{opacity:0}70%{opacity:.6}100%{opacity:0}}.alarm{opacity:0;animation:al 1.4s ease-out 3 both}@keyframes al{from{transform:scale(.6);opacity:.9}to{transform:scale(1.25);opacity:0}}.chev{animation:cv 1.6s ease-in-out infinite}.chev.up{animation-name:cvu}@keyframes cv{0%{transform:translateY(-2px);opacity:0}40%{opacity:1}100%{transform:translateY(3px);opacity:0}}@keyframes cvu{0%{transform:translateY(2px);opacity:0}40%{opacity:1}100%{transform:translateY(-3px);opacity:0}}.chv{opacity:.2;animation:cvf 1.2s linear infinite}@keyframes cvf{0%,100%{opacity:.18}25%{opacity:1}55%{opacity:.18}}.pulse2{animation:p2 .9s ease-in-out 3}@keyframes p2{50%{opacity:.35}}@media (prefers-reduced-motion:reduce){.flow,.glint,.chev,.chv,.pulse2{animation:none}.chv{opacity:.7}.flick{animation:none;opacity:0}.alarm{animation:none;opacity:.6}.ghost{animation:none}.grow,.fadein{animation:none}.dust,.flash1{animation:none;opacity:0}.spin,.smoke circle,.rain,.snowf,.sway,.ripple{animation:none}.flash,.bolt,.windline{animation:none;opacity:0}}`;
function sceneFrame(ph,state,tod){
  // Isometric island city in a soft "toy" style. Grid 10x10; x=(gx-gy)*TW/2, y=(gx+gy)*TH/2.
  // Only drawing: every number shown in the game comes from aityx. Each night is a chapter of the same city:
  // Village (farm, dirt roads) > Town (paved, shops, hospital) > Industry (factory district, rail) > Storm (rain, wind) > Winter (snow).
  // Only powered things light up at night (houses, streetlights, hospital, factory); new decor stays dark.
  const P=PHASES[ph], c=state.city, NX=10, NY=12, TW=70, TH=35, OX=360, OY=44;   // the island grew south: two more rows where the city expands from night 6
  const VIL=ph===0, TOWN=ph>=1, IND=ph>=2, STORM=P.wx==="storm", SNOW=P.wx==="snow", AUT=P.wx==="autumn";
  const LT=light(tod,ph), DARK=LT.dark, WARM=LT.warm, LIT=DARK>=.3, NIGHTISH=DARK>.55;
  const fid=++frameId, SKY="sky"+fid, LG="lg"+fid, HG="hg"+fid;
  const X=(gx,gy)=>OX+(gx-gy)*TW/2, Y=(gx,gy)=>OY+(gx+gy)*TH/2;
  const pt=(gx,gy,z=0)=>`${X(gx,gy).toFixed(1)},${(Y(gx,gy)-z).toFixed(1)}`;
  const poly=(pts,fill,extra="")=>`<polygon points="${pts.join(" ")}" fill="${fill}" ${extra}/>`;
  const now=Date.now()/1000, sync=(p,o=0)=>`animation-delay:-${((now+o)%p).toFixed(2)}s`;
  const rgb=h=>{ const n=parseInt(h.slice(1),16); return [n>>16,n>>8&255,n&255]; };
  const out=(r,g,b)=>`rgb(${[r,g,b].map(v=>Math.max(0,Math.min(255,Math.round(v)))).join(",")})`;
  const mixc=(a,b,t)=>{ const A=rgb(a), B=rgb(b); return out(...A.map((v,i)=>v+(B[i]-v)*t)); };
  // every surface colour: stage tone, then the light of this moment (darkness and sunrise/sunset warmth)
  const shade=(hex,k)=>{ let [r,g,b]=rgb(hex);
    if(STORM){ const l=(r+g+b)/3; r=(r*.55+l*.45)*.66; g=(g*.55+l*.45)*.69; b=(b*.55+l*.45)*.8; }
    else if(SNOW){ r*=.95; g*=.98; b=b*1.02+8; }
    if(DARK){ r+=(r*.5+6-r)*DARK; g+=(g*.5+8-g)*DARK; b+=(b*.56+(SNOW?30:20)-b)*DARK; }
    if(WARM){ const w=WARM*(1-DARK*.4); r+=w*30; g+=w*6; b-=w*22; }
    return out(r*k,g*k,b*k); };
  const SNOWC="#f4f7fb";
  const quad=(g0,g1,z=0)=>[pt(g0[0],g0[1],z),pt(g1[0],g0[1],z),pt(g1[0],g1[1],z),pt(g0[0],g1[1],z)];
  // a box: top, front (+gy face) and side (+gx face); in winter every top carries snow
  const box=(gx,gy,w,d,h,top,front,side,z0=0)=>poly(quad([gx,gy],[gx+w,gy+d],h),shade(SNOW?SNOWC:top,1))+
    poly([pt(gx,gy+d,h),pt(gx+w,gy+d,h),pt(gx+w,gy+d,z0),pt(gx,gy+d,z0)],shade(front,1))+
    poly([pt(gx+w,gy,h),pt(gx+w,gy+d,h),pt(gx+w,gy+d,z0),pt(gx+w,gy,z0)],shade(side,1));
  const WARMW="#ffd36b", DAYWIN=shade("#a9dcf5",1), OFF="#232a36";
  const winF=(gx,gy,z,on,w=.16,h=8)=>poly([pt(gx,gy,z),pt(gx+w,gy,z),pt(gx+w,gy,z-h),pt(gx,gy,z-h)],LIT?(on?WARMW:OFF):DAYWIN,`stroke="${shade("#ffffff",.9)}" stroke-width=".6"`);
  const winS=(gx,gy,z,on,w=.16,h=8)=>poly([pt(gx,gy,z),pt(gx,gy+w,z),pt(gx,gy+w,z-h),pt(gx,gy,z-h)],LIT?(on?WARMW:OFF):DAYWIN,`stroke="${shade("#ffffff",.9)}" stroke-width=".6"`);
  const GL=Math.min(1,DARK*1.15);
  const glow=(gx,gy,rx,o=.22,col=WARMW)=>`<ellipse cx="${X(gx,gy)}" cy="${Y(gx,gy)}" rx="${rx}" ry="${rx/2}" fill="${col}" opacity="${(o*GL).toFixed(3)}"/>`;
  const smoke=(x,y,k=1,cls="smoke")=>`<g class="${cls}"><circle cx="${x}" cy="${y}" r="${5*k}" fill="#ffffff" opacity=".7"/><circle cx="${x+5*k}" cy="${y-7*k}" r="${6.5*k}" fill="#f1f1f1" opacity=".5"/></g>`;
  // ---- sky: gradient, horizon glow, sun, moon, stars, clouds, all from the time of day ----
  let s=`<defs><linearGradient id="${SKY}" x1="0" y1="0" x2="0" y2="1"><stop stop-color="${LT.top}"/><stop offset="1" stop-color="${LT.bot}"/></linearGradient>
  <radialGradient id="${LG}"><stop stop-color="#ffd36b" stop-opacity=".55"/><stop offset="1" stop-color="#ffd36b" stop-opacity="0"/></radialGradient>
  <radialGradient id="${HG}"><stop stop-color="${LT.glow?LT.glow[0]:"#000000"}" stop-opacity="1"/><stop offset="1" stop-color="${LT.glow?LT.glow[0]:"#000000"}" stop-opacity="0"/></radialGradient></defs>
  <rect x="-80" width="840" height="480" fill="url(#${SKY})"/>`;
  if(LT.glow) s+=`<ellipse cx="640" cy="190" rx="300" ry="130" fill="url(#${HG})" opacity="${LT.glow[1]}"/>`;
  if(LT.stars) for(let i=0;i<60;i++) s+=`<circle cx="${(i*97+13)%840-80}" cy="${(i*53)%150}" r="${i%7?0.9:1.6}" fill="#ffffff" opacity="${((i%3?.55:.85)*LT.stars).toFixed(2)}"/>`;
  if(LT.moon){ const M="mn"+fid, my=SNOW?54:52, mr=SNOW?21:20;
    s+=`<mask id="${M}"><rect x="-80" width="840" height="480" fill="#fff"/><circle cx="650" cy="${my-7}" r="${mr-1}" fill="#000"/></mask><g opacity="${LT.moon}">`+(SNOW?`<circle cx="640" cy="54" r="34" fill="#cfe2ff" opacity=".12"/>`:"")+
      `<circle cx="640" cy="${my}" r="${mr}" fill="${SNOW?"#eef4ff":"#ffe08a"}" mask="url(#${M})"/></g>`; }
  if(LT.sun){ const [x,y,r,col]=LT.sun; s+=`<circle cx="${x}" cy="${y}" r="${r*1.9}" fill="${col}" opacity="${tod==="day"||tod==="morning"?(IND?.25:.35):.3}"/><circle cx="${x}" cy="${y}" r="${r}" fill="${col}"${SNOW&&(tod==="day"||tod==="morning")?' opacity=".75"':""}/>`; }
  const cloud=(x,y,k,fill="#ffffff",o=.95)=>`<g opacity="${o}" fill="${fill}"><ellipse cx="${x}" cy="${y}" rx="${26*k}" ry="${11*k}"/><ellipse cx="${x-14*k}" cy="${y+3*k}" rx="${16*k}" ry="${9*k}"/><ellipse cx="${x+6*k}" cy="${y-7*k}" rx="${15*k}" ry="${11*k}"/></g>`;
  const tint=base=>mixc(WARM?mixc(base,"#ffc4a0",WARM*.75):base,"#3a4466",DARK*.5);
  if(STORM){ const a=mixc("#262d38","#0c1119",DARK), b=mixc("#3e4755","#151c28",DARK);
    s+=cloud(40,92,1.5,a,1)+cloud(120,48,2.1,b,1)+cloud(235,24,1.6,a,1)+cloud(560,40,2.2,b,1)+cloud(675,74,1.6,a,1)+cloud(470,16,1.2,a,.9); }
  else if(DARK<.6){ const o=((1-DARK/.6)*.95).toFixed(2);
    if(SNOW){ const f1=tint("#f3f6f9"), f2=tint("#eef2f6"); s+=cloud(90,62,1.5,f1,o)+cloud(235,30,1.3,f2,o)+cloud(540,46,1.6,f1,o)+cloud(665,104,1.2,f2,o)+cloud(400,10,1,f1,o*.85); }
    else { const cf=tint(IND?"#f4f0e6":"#ffffff"); s+=cloud(90,70,1,cf,o)+cloud(250,34,.8,cf,o)+cloud(560,62,1.1,cf,o)+cloud(660,120,.7,cf,o); } }

  if(IND&&!STORM&&!SNOW&&DARK<.6){ const o=1-DARK/.6; s+=`<ellipse cx="360" cy="235" rx="430" ry="85" fill="#b39a74" opacity="${(.3*o).toFixed(2)}"/><ellipse cx="575" cy="150" rx="150" ry="24" fill="#8f8a80" opacity="${(.32*o).toFixed(2)}"/><ellipse cx="150" cy="175" rx="120" ry="18" fill="#9a907f" opacity="${(.22*o).toFixed(2)}"/>`; }
  if(STORM) s+=`<rect x="-80" width="840" height="130" fill="${mixc("#1c222c","#05070b",DARK)}" opacity=".55"/>`+cloud(330,-10,2.4,mixc("#2a313c","#0b1017",DARK),1)+cloud(620,6,2,mixc("#30384a","#0e131c",DARK),1)+cloud(90,20,1.9,mixc("#2a313c","#0b1017",DARK),1);
  // ---- floating island ----
  s+=poly([pt(0,NY),pt(NX,NY),pt(NX,NY,-22),pt(0,NY,-22)],shade("#7a5434",1))+poly([pt(NX,0),pt(NX,NY),pt(NX,NY,-22),pt(NX,0,-22)],shade("#5f3f26",1))
    +poly([pt(0,NY),pt(NX,NY),pt(NX,NY,-6),pt(0,NY,-6)],shade(SNOW?"#e6edf3":"#5aa53d",1))+poly([pt(NX,0),pt(NX,NY),pt(NX,NY,-6),pt(NX,0,-6)],shade(SNOW?"#d3dce6":"#4b8f33",1));
  // ground: grass, or snow in winter
  for(let gx=0;gx<NX;gx++) for(let gy=0;gy<NY;gy++){ const a=(gx*7+gy*3)%5<2; s+=poly(quad([gx,gy],[gx+1,gy+1]),shade(SNOW?(a?"#f4f7fa":"#eaf0f5"):AUT?(a?"#a6c95a":"#9bbf52"):(a?"#8fd160":"#86c957"),1)); }
  // fields: the village farm (where the hospital will stand) and the small field by the barn, which stays all game
  const field=(g0,g1,crop,soil)=>{ let f=poly(quad(g0,g1),shade(soil,1)); const n=Math.floor((g1[0]-g0[0])/.24);
    for(let i=0;i<n;i++){ const a=g0[0]+i*.24+.06; f+=poly(quad([a,g0[1]+.06],[a+.12,g1[1]-.06]),shade(crop,1)); } return f; };
  if(VIL) s+=field([6.35,.45],[8.4,2.45],"#9ccf5a","#a77b4f");
  s+=field([8.55,2.6],[9.6,3.7],SNOW?"#eef3f8":STORM?"#6f8f3e":IND?"#e2c45c":"#9ccf5a",SNOW?"#dbe3ec":"#a77b4f");
  // industrial district: concrete lot where the meadow was
  if(IND){ s+=poly(quad([6.2,5.2],[9.05,8.42]),shade(SNOW?"#e1e7ed":"#b7b2a7",1));
    for(let i=0;i<4;i++) s+=poly(quad([6.35+i*.5,5.3],[6.4+i*.5,5.85]),shade(SNOW?"#cfd7e0":"#e8e4da",1)); }

  // ---- roads: dirt lanes in the village, paved with sidewalks from the town on ----
  const dash=(a,b,col,o=.85)=>`<line x1="${X(...a)}" y1="${Y(...a)}" x2="${X(...b)}" y2="${Y(...b)}" stroke="${col}" stroke-width="1.6" opacity="${o}"/>`;
  if(VIL){ const D=shade("#c9a877",1), R=shade("#b08d60",1);
    s+=poly(quad([0,4.1],[NX,4.9]),D)+poly(quad([5.1,0],[5.9,NY]),D);
    s+=poly(quad([0,4.3],[NX,4.36]),R)+poly(quad([0,4.64],[NX,4.7]),R)+poly(quad([5.3,0],[5.36,NY]),R)+poly(quad([5.64,0],[5.7,NY]),R); }
  else { const SIDE=shade(SNOW?"#f4f7fa":"#d8d2c4",1), ROAD=shade(SNOW?"#c4ccd6":STORM?"#3f454e":"#4b525c",1), DC=mixc("#ffffff","#9aa1aa",DARK);
    s+=poly(quad([0,3.86],[NX,5.14]),SIDE)+poly(quad([4.86,0],[6.14,NY]),SIDE);
    s+=poly(quad([0,4],[NX,5]),ROAD)+poly(quad([5,0],[6,NY]),ROAD);
    for(let gx=0;gx<NX;gx++) if(gx!==5) s+=dash([gx+.15,4.5],[gx+.6,4.5],DC,SNOW?0:.85);
    for(let gy=0;gy<NY;gy++) if(gy!==4) s+=dash([5.5,gy+.15],[5.5,gy+.6],DC,SNOW?0:.85);
    // crosswalks around the crossing
    for(let i=0;i<5;i++){ s+=poly(quad([4.35,4.08+i*.18],[4.8,4.18+i*.18]),DC);
      s+=poly(quad([5.08+i*.18,5.2],[5.18+i*.18,5.65]),DC); }
    if(SNOW){ [[0,3.98],[0,5.02]].forEach(([a,b])=>s+=poly(quad([a,b],[NX,b+.04]),shade("#ffffff",1)));
      const T=shade("#8c96a2",1); [4.22,4.36,4.64,4.78].forEach(b=>s+=poly(quad([0,b],[NX,b+.05]),T)); [5.22,5.36,5.64,5.78].forEach(a=>s+=poly(quad([a,0],[a+.05,NY]),T));
      for(let i=0;i<NY;i++) if(i!==4&&i!==5){ s+=`${i<NX?`<ellipse cx="${X(i+.5,3.92)}" cy="${Y(i+.5,3.92)}" rx="13" ry="4.5" fill="${shade("#ffffff",1)}"/>`:""}<ellipse cx="${X(4.92,i+.5)}" cy="${Y(4.92,i+.5)}" rx="11" ry="4" fill="${shade("#ffffff",1)}"/>`; } }
    if(STORM) [[2.2,4.45],[7.8,4.6],[5.45,2.3],[5.6,7.4],[3.6,4.3],[8.9,4.4]].forEach(([gx,gy],i)=>{ const x=X(gx,gy), y=Y(gx,gy);
      s+=`<ellipse cx="${x}" cy="${y}" rx="14" ry="5" fill="${mixc("#8ea3bb","#24344d",DARK)}" opacity=".6"/><ellipse class="ripple" cx="${x}" cy="${y}" rx="6" ry="2" fill="none" stroke="#dfe8f2" stroke-width=".8" style="transform-origin:${x}px ${y}px;${sync(1.4,i*.3)}"/>`; }); }
  // railway along the east edge, from the industrial night on
  if(IND){ for(let gy=.05;gy<NY;gy+=.3) s+=poly(quad([9.7,gy],[9.98,gy+.1]),shade("#7b5b3e",1));
    [9.78,9.9].forEach(gx=>s+=`<line x1="${X(gx,0)}" y1="${Y(gx,0)}" x2="${X(gx,NY)}" y2="${Y(gx,NY)}" stroke="${shade("#a3acb6",1)}" stroke-width="1.5"/>`); }

  // ================= objects =================
  // Every object has a grid footprint [x0,y0]-[x1,y1] and a height. Buildings and machines are "solids";
  // props (streetlights, trees, flowers, people, park lamps) are placed afterwards, only where they clear every solid.
  const items=[], solids=[], zones=[], props=[]; let late="";
  const hullOf=(x0,y0,x1,y1,h)=>[[X(x0,y0),Y(x0,y0)-h],[X(x1,y0),Y(x1,y0)-h],[X(x1,y0),Y(x1,y0)],[X(x1,y1),Y(x1,y1)],[X(x0,y1),Y(x0,y1)],[X(x0,y1),Y(x0,y1)-h]];
  const inHull=(H,x,y)=>{ let sg=0; for(let i=0;i<H.length;i++){ const [ax,ay]=H[i], [bx,by]=H[(i+1)%H.length], c=(bx-ax)*(y-ay)-(by-ay)*(x-ax); if(Math.abs(c)>1e-9){ const t=Math.sign(c); if(sg&&t!==sg) return false; sg=t; } } return true; };
  const add=(x0,y0,x1,y1,h,svg,o={})=>{ const it={x0,y0,x1,y1,h,svg,name:o.name||""}; items.push(it); if(o.solid!==false) solids.push({...it,hull:(o.parts||[[x0,y0,x1,y1,h]]).map(q=>hullOf(...q))}); return it; };   // parts: one outline per piece (body, chimney, mast), so checks match what is drawn
  const addAt=(gx,gy,w,d,h,svg,o)=>add(gx,gy,gx+w,gy+d,h,svg,o);
  const zone=(x0,y0,x1,y1)=>zones.push([x0,y0,x1,y1]);   // ground that props must not sit on (fields, lots, panel rows)
  const prop=(kind,gx,gy,r,h,samples,svg)=>props.push({kind,gx,gy,r,h,samples,svg});
  // construction: on the first frame of a new chapter, what is new in it rises from the ground with a puff of dust
  const GROW=state.grow?ph:-1, PREVH=ph>0?PHASES[ph-1].homes:null;
  const rise=(svg,gx,gy,w,d,stage,delay)=>{ if(stage!==GROW) return svg; const ox=X(gx+w/2,gy+d/2).toFixed(1), oy=Y(gx+w,gy+d).toFixed(1), dl=delay.toFixed(2);
    return `<g class="grow" style="transform-origin:${ox}px ${oy}px;animation-delay:${dl}s">${svg}</g><ellipse class="dust" cx="${ox}" cy="${oy}" rx="${(18+w*12).toFixed(0)}" ry="${(7+w*4).toFixed(0)}" fill="#e6dccb" style="transform-origin:${ox}px ${oy}px;animation-delay:${dl}s"/>`; };
  const dk=(h,k)=>"#"+rgb(h).map(v=>Math.round(v*k).toString(16).padStart(2,"0")).join("");

  // ---- energy state for this moment, only from aityx answers and the night's inputs ----
  const E0=state.energy||{mode:tod==="morning"?"morning":"plan"};
  const E=tod==="dusk"?{mode:"dusk",dusk:E0.dusk,after:E0.dusk}:E0, NIGHT=E.mode==="night", HR=E.h??0;
  const cap=Math.max(1,c.capacity), stored=E.mode==="plan"?null:(E.mode==="dusk"?E.dusk:E.after);
  const windNow=NIGHT?(P.wind[HR]||0):0;
  const solarOn=E.mode==="plan"&&P.sun>0;

  // ---- decoration shapes ----
  const tree=(gx,gy,k=1)=>{ const x=X(gx,gy), y=Y(gx,gy); let t;
    if(SNOW){ const g1=shade("#2f6b45",1), g2=shade("#3c7d52",1), sn=shade(SNOWC,1);
      t=`<ellipse cx="${x}" cy="${y}" rx="${9*k}" ry="${4*k}" fill="#000" opacity=".12"/><rect x="${x-1.8*k}" y="${y-8*k}" width="${3.6*k}" height="${8*k}" fill="${shade("#7a5030",1)}"/>`+
        [[6,12,14],[14,10,13],[22,7,12]].map(([b,w,h],i)=>{ const yb=y-b*k, ya=y-(b+h)*k;
          return `<polygon points="${x-w*k},${yb} ${x+w*k},${yb} ${x},${ya}" fill="${i%2?g2:g1}"/><polygon points="${x-w*.5*k},${ya+h*.5*k} ${x+w*.5*k},${ya+h*.5*k} ${x},${ya}" fill="${sn}"/>`; }).join(""); }
    else { const a=shade(AUT?"#e8913a":"#6cc04a",1), b=shade(AUT?"#c8642c":"#4e9f36",1), hi=shade(AUT?"#f2c14e":"#9be06b",1);
      t=`<ellipse cx="${x}" cy="${y}" rx="${10*k}" ry="${4.5*k}" fill="#000" opacity=".18"/><rect x="${x-2*k}" y="${y-11*k}" width="${4*k}" height="${11*k}" rx="${1.5*k}" fill="${shade("#8a5a33",1)}"/>`+
        `<circle cx="${x-6*k}" cy="${y-15*k}" r="${8*k}" fill="${b}"/><circle cx="${x+6*k}" cy="${y-15*k}" r="${8*k}" fill="${b}"/><circle cx="${x}" cy="${y-22*k}" r="${10*k}" fill="${a}"/><circle cx="${x-3*k}" cy="${y-25*k}" r="${4*k}" fill="${hi}" opacity=".8"/>`; }
    return STORM?`<g class="sway" style="transform-origin:${x}px ${y}px;${sync(2.2,gx*.37+gy*.21)}">${t}</g>`:t; };
  const TREE_S=[[0,0],[0,-8],[0,-22],[-12,-15],[12,-15],[0,-32],[-8,-26],[8,-26]];
  const flowers=(gx,gy)=>{ const x=X(gx,gy), y=Y(gx,gy), cols=["#ff8fb3","#ffd34d","#ff6f61","#c79bff"];
    return `<ellipse cx="${x}" cy="${y}" rx="9" ry="4" fill="${shade("#4e9f36",1)}"/>`+[[-4,-2],[0,-4],[4,-2],[-1,0],[3,1]].map(([dx,dy],i)=>`<circle cx="${x+dx}" cy="${y+dy-2}" r="1.8" fill="${shade(cols[(i+Math.round(gx*3))%4],1)}"/>`).join(""); };

  // ---- pond with a dock, in the park at the bottom (frozen in winter) ----
  const PX=7.9, PY=9.1, px=X(PX,PY), py=Y(PX,PY);
  s+=`<ellipse cx="${px}" cy="${py}" rx="52" ry="20" fill="${shade(SNOW?"#e8eef3":"#b9ad97",1)}"/><ellipse cx="${px}" cy="${py-1}" rx="47" ry="17" fill="${SNOW?mixc("#cfe5f1","#3d5579",DARK):STORM?mixc("#3f5d78","#0f2340",DARK):mixc(WARM?"#7fb6d8":"#4fb3ea","#123160",DARK)}"/>`;
  if(SNOW) s+=`<polyline points="${px-30},${py-4} ${px-12},${py+2} ${px+4},${py-3} ${px+22},${py+5}" fill="none" stroke="#ffffff" stroke-width="1" opacity=".75"/><polyline points="${px-4},${py-3} ${px+2},${py-11}" fill="none" stroke="#ffffff" stroke-width="1" opacity=".75"/><ellipse cx="${px+10}" cy="${py+3}" rx="18" ry="5" fill="none" stroke="#ffffff" stroke-width=".8" opacity=".6"/>`;
  else { s+=`<ellipse cx="${px-7}" cy="${py-3}" rx="20" ry="5" fill="${STORM?"#2a4f86":mixc(WARM?"#ffd2a8":"#9fdcff","#2a4f86",DARK)}" opacity="${STORM?.35:.7}"/>`;
    if(STORM) [[-26,-2],[-4,5],[16,-5],[24,4]].forEach(([dx,dy])=>s+=`<path d="M${px+dx-6} ${py+dy} q3 -3 6 0 t6 0" fill="none" stroke="#dfe8f2" stroke-width="1" opacity=".7"/>`);
    else [[7.4,9.4],[8.3,8.8],[8.6,9.3]].forEach(([gx,gy])=>s+=`<ellipse cx="${X(gx,gy)}" cy="${Y(gx,gy)}" rx="4" ry="2" fill="${shade("#5fbf5a",1)}"/>`); }
  s+=poly([pt(6.95,8.65,3),pt(7.45,8.65,3),pt(7.45,8.85,3),pt(6.95,8.85,3)],shade(SNOW?SNOWC:"#a26b3c",1));
  const inPond=(gx,gy,r)=>{ const dx=(X(gx,gy)-px)/(54+r*30), dy=(Y(gx,gy)-py)/(21+r*15); return dx*dx+dy*dy<1; };
  if(SNOW){ const x=X(6.7,9.5), y=Y(6.7,9.5), w=shade("#ffffff",1);
    addAt(6.6,9.4,.2,.2,29,`<ellipse cx="${x}" cy="${y}" rx="8" ry="3" fill="#000" opacity=".12"/><circle cx="${x}" cy="${y-6}" r="6.5" fill="${w}"/><circle cx="${x}" cy="${y-15}" r="4.6" fill="${w}"/><circle cx="${x}" cy="${y-22}" r="3.4" fill="${w}"/><path d="M${x+1} ${y-22}l5 1.2l-5 1z" fill="#f07a32"/><rect x="${x-3.4}" y="${y-29}" width="6.8" height="4.6" fill="#2b2f36"/><rect x="${x-5}" y="${y-25}" width="10" height="1.6" fill="#2b2f36"/><rect x="${x-4.2}" y="${y-19}" width="8.4" height="2" fill="#e36742"/>`,{name:"snowman"}); }

  // ---- the barn and its field: there from the first night to the last ----
  { const gx=8.62, gy=1.55, w=.85, d=.75, h=16, R=SNOW?SNOWC:"#6b4a3a";
    let g=box(gx,gy,w,d,h,"#b8432f","#c94d36","#a63c2a");
    g+=poly([pt(gx-.04,gy-.04,h),pt(gx+w+.04,gy-.04,h),pt(gx+w+.04,gy+d/2,h+11),pt(gx-.04,gy+d/2,h+11)],shade(R,.85));
    g+=poly([pt(gx+w,gy,h),pt(gx+w,gy+d,h),pt(gx+w,gy+d/2,h+11)],shade("#b8432f",1));
    g+=poly([pt(gx-.04,gy+d+.04,h),pt(gx+w+.04,gy+d+.04,h),pt(gx+w+.04,gy+d/2,h+11),pt(gx-.04,gy+d/2,h+11)],shade(SNOW?SNOWC:"#7d5643",1));
    g+=poly([pt(gx+.28,gy+d,11),pt(gx+.58,gy+d,11),pt(gx+.58,gy+d,0),pt(gx+.28,gy+d,0)],shade("#f3ead8",1))+poly([pt(gx+.31,gy+d,9.5),pt(gx+.55,gy+d,9.5),pt(gx+.55,gy+d,0),pt(gx+.31,gy+d,0)],shade("#8f3324",1));
    add(gx-.04,gy-.04,gx+w+.04,gy+d+.04,h+11,g,{name:"barn"}); }
  zone(8.55,2.6,9.6,3.7);                                  // the barn's field
  if(VIL){ zone(6.35,.45,8.4,2.45);                        // the village farm, where the hospital will stand
    let f=""; for(let gx=6.35;gx<=8.41;gx+=.26) f+=`<line x1="${X(gx,2.5)}" y1="${Y(gx,2.5)}" x2="${X(gx,2.5)}" y2="${Y(gx,2.5)-6}" stroke="${shade("#8a5a33",1)}" stroke-width="1.4"/>`;
    f+=`<line x1="${X(6.35,2.5)}" y1="${Y(6.35,2.5)-4.5}" x2="${X(8.41,2.5)}" y2="${Y(8.41,2.5)-4.5}" stroke="${shade("#a8774a",1)}" stroke-width="1.2"/>`;
    add(6.35,2.47,8.41,2.53,6,f,{name:"fence"});
    [[6.75,1.95],[7.95,.85]].forEach(([gx,gy])=>{ const x=X(gx,gy), y=Y(gx,gy);
      add(gx-.22,gy-.22,gx+.22,gy+.22,16,`<ellipse cx="${x}" cy="${y}" rx="11" ry="4.5" fill="#000" opacity=".15"/><path d="M${x-10} ${y}Q${x-10} ${y-15} ${x} ${y-16}Q${x+10} ${y-15} ${x+10} ${y}Z" fill="${shade("#e8c35a",1)}"/><path d="M${x-6} ${y-6}Q${x} ${y-9} ${x+6} ${y-6}" fill="none" stroke="${shade("#c99a3a",1)}" stroke-width="1"/>`,{name:"hay"}); });
    const gx=7.3, gy=1.35;
    addAt(gx,gy,.45,.3,17,box(gx,gy,.45,.3,9,"#3f9a4a","#4aa857","#357f3e")+box(gx+.05,gy+.04,.22,.22,17,"#d8e9f2","#bcd6e4","#a9c6d6",9)+`<circle cx="${X(gx+.1,gy+.3)}" cy="${Y(gx+.1,gy+.3)-4}" r="5.5" fill="${shade("#2b2f36",1)}"/><circle cx="${X(gx+.42,gy+.3)}" cy="${Y(gx+.42,gy+.3)-3}" r="3.5" fill="${shade("#2b2f36",1)}"/>`,{name:"tractor"}); }

  // ---- houses: windows follow houses_lit from aityx; a house that just lost power flickers out once ----
  const slots=[[0.25,0.15],[1.85,0.15],[3.45,0.15],[0.25,1.45],[1.85,1.45],[3.45,1.45],[0.25,2.75],[1.85,2.75],[3.45,2.75],[8.55,0.15],[8.55,1.45],[8.55,2.75]];
  const roofs=["#d9573f","#f2a33a","#3f74c9","#9a5bd6","#e0703a","#5b8ee0"];
  const lit=LIT?(state.lit??P.houses):P.houses, prevLit=NIGHT?(E.prevLit??lit):lit;
  slots.slice(0,P.homes).forEach(([gx,gy],i)=>{ const on=LIT&&i<lit, w=1, d=.9, h=22, r=roofs[i%roofs.length];
    let g=poly(quad([gx-.12,gy-.08],[gx+w+.12,gy+d+.12]),shade(SNOW?"#e3eaf1":VIL?"#a6dd78":"#9fdc72",1),VIL?`stroke="${shade("#efe3c4",1)}" stroke-width="1.8" stroke-dasharray="2.5 2"`:`stroke="${shade(SNOW?"#c9d4df":"#3f8a2c",1)}" stroke-width="2.4"`);
    g+=poly([pt(gx+.05,gy+.05,13+h),pt(gx+.95,gy+.05,13+h),pt(gx+.95,gy+d/2,h+16),pt(gx+.05,gy+d/2,h+16)],shade(SNOW?SNOWC:r,.75));
    g+=box(gx,gy,w,d,h,"#f3ead8","#f6eedf","#dfd2bb");
    g+=poly([pt(gx+w,gy,h),pt(gx+w,gy+d,h),pt(gx+w,gy+d/2,h+16)],shade("#e8dcc5",1));
    g+=box(gx+.68,gy+.18,.14,.14,h+20,"#b7b0a6","#9d958b","#8a837a",h+6);
    g+=poly([pt(gx-.08,gy+d+.1,h-1),pt(gx+w+.06,gy+d+.1,h-1),pt(gx+w+.06,gy+d/2,h+16),pt(gx-.08,gy+d/2,h+16)],shade(r,1));
    if(SNOW){ const e=gy+d+.1-.3*(d/2+.1), z=h-1+.3*17;
      g+=poly([pt(gx-.08,e,z),pt(gx+w+.06,e,z),pt(gx+w+.06,gy+d/2,h+16),pt(gx-.08,gy+d/2,h+16)],shade(SNOWC,1));
      for(let k=0;k<7;k++){ const [x,y]=pt(gx-.02+k*.16,gy+d+.1,h-1).split(",").map(Number); g+=`<path d="M${x-1.6} ${y}L${x+1.6} ${y}L${x} ${y+4+(k%3)*1.5}Z" fill="${shade("#e8f3ff",1)}"/>`; }
      if(on) for(let k=0;k<8;k++){ const [x,y]=pt(gx-.02+k*.15,gy+d+.1,h-3).split(",").map(Number); g+=`<circle cx="${x}" cy="${y}" r="1.4" fill="${["#ff5a5a","#ffd35a","#5ad1ff","#7dff8a"][k%4]}"/>`; } }
    g+=poly([pt(gx+.44,gy+d,13),pt(gx+.6,gy+d,13),pt(gx+.6,gy+d,0),pt(gx+.44,gy+d,0)],shade("#a8683a",1));
    g+=winF(gx+.12,gy+d,h-6,on)+winF(gx+.72,gy+d,h-6,on)+winS(gx+w,gy+.35,h-6,on,.2);
    if(NIGHT){ const [mx,my]=pt(gx+.68,gy+d,6).split(",").map(Number), mc=on?"#6fe0ff":"#ef6b6b";   // service point beside the door: this house's connection to the grid
      g+=(on?`<circle cx="${mx}" cy="${my}" r="4.2" fill="${mc}" opacity=".28"/>`:"")+`<rect x="${mx-1.8}" y="${my-2.2}" width="3.6" height="4.4" rx="1" fill="${on?mc:"#5a2a30"}" stroke="${on?"#e8fdff":"#ef6b6b"}" stroke-width=".6"/>`; }
    if(on) g+=glow(gx+.5,gy+d+.35,26,.2);
    if(NIGHT&&!on&&i<prevLit) g+=`<g class="flick">${poly([pt(gx+.12,gy+d,h-6),pt(gx+.28,gy+d,h-6),pt(gx+.28,gy+d,h-14),pt(gx+.12,gy+d,h-14)],WARMW)+poly([pt(gx+.72,gy+d,h-6),pt(gx+.88,gy+d,h-6),pt(gx+.88,gy+d,h-14),pt(gx+.72,gy+d,h-14)],WARMW)}</g>`;
    if(SNOW&&(!LIT||on)) g+=smoke(X(gx+.75,gy+.25),Y(gx+.75,gy+.25)-h-26,.8);
    add(gx-.12,gy-.08,gx+w+.12,gy+d+.12,h+20,rise(g,gx,gy,w,d,PREVH!=null&&i>=PREVH?ph:-9,.05+(i-(PREVH||0))*.14),{name:"house"+i,parts:[[gx-.08,gy,gx+w+.06,gy+d+.1,38],[gx+.68,gy+.18,gx+.82,gy+.32,42]]}); });
  // the next house: survey stakes in the village, a timber frame and a tower crane (in the gap beside it) in the town and the industrial city
  if(ph<=2&&slots[P.homes]){ const [gx,gy]=slots[P.homes], w=1, d=.9, wood=shade("#c08a4e",1);
    let g=poly(quad([gx-.05,gy-.05],[gx+w+.05,gy+d+.05]),shade("#b48a5c",1));
    const ln=(a,b,za,zb,col=wood,sw=1.6)=>`<line x1="${X(...a)}" y1="${Y(...a)-za}" x2="${X(...b)}" y2="${Y(...b)-zb}" stroke="${col}" stroke-width="${sw}"/>`;
    const C=[[gx,gy],[gx+w,gy],[gx+w,gy+d],[gx,gy+d]]; let x0=gx-.05;
    if(VIL){ C.forEach(p=>g+=ln(p,p,0,7,shade("#8a5a33",1),1.4)); C.forEach((p,i)=>g+=ln(p,C[(i+1)%4],5,5,shade("#ffffff",1),.7)); }
    else { g+=box(gx,gy,w,d,3,"#c9c5bd","#b8b3aa","#a8a399");
      [C[0],C[1],C[3]].forEach(p=>g+=ln(p,p,3,22)); C.forEach((p,i)=>g+=ln(p,C[(i+1)%4],22,22));
      g+=ln([gx,gy+d/2],[gx+w,gy+d/2],34,34)+ln([gx+w,gy],[gx+w,gy+d/2],22,34)+ln([gx+w,gy+d],[gx+w,gy+d/2],22,34);
      g+=ln(C[2],C[2],3,22)+ln([gx+.5,gy+d],[gx+.5,gy+d],3,22);
      const mx=X(gx+.5,gy-.18), my=Y(gx+.5,gy-.18), yc=shade("#f2c14e",1), MH=88;
      g=`<path d="M${mx-2} ${my}V${my-MH}M${mx+2} ${my}V${my-MH}" stroke="${yc}" stroke-width="1.4"/>`+g;
      for(let k=0;k<8;k++) g+=`<path d="M${mx-2} ${my-k*11}L${mx+2} ${my-k*11-11}" stroke="${yc}" stroke-width=".8"/>`;
      g+=`<path d="M${mx-22} ${my-MH}H${mx+58}M${mx} ${my-MH}L${mx+20} ${my-MH-10}L${mx+58} ${my-MH}M${mx} ${my-MH-10}V${my-MH}" stroke="${yc}" stroke-width="1.4" fill="none"/><rect x="${mx-24}" y="${my-MH-1}" width="9" height="7" fill="${shade("#6f747c",1)}"/><line x1="${mx+40}" y1="${my-MH}" x2="${mx+40}" y2="${my-MH+40}" stroke="${shade("#3a4048",1)}" stroke-width=".7"/><rect x="${mx+36}" y="${my-MH+40}" width="8" height="5" fill="${shade("#c08a4e",1)}"/>`; }
    add(x0,VIL?gy-.05:gy-.24,gx+w+.05,gy+d+.05,VIL?8:36,rise(g,gx,gy,w,d,ph,.7),{name:"site",parts:VIL?[[gx,gy,gx+w,gy+d,8]]:[[gx,gy,gx+w,gy+d,36],[gx+.46,gy-.22,gx+.54,gy-.14,98]]}); }

  // ---- shops on the main road (closed at night: not on the grid), clock tower on the middle one ----
  if(TOWN){ const fac=["#f2d7b6","#d4e6ea","#f1cccc"], sid=["#dcc2a2","#bdd0d4","#dbb6b6"], aw=["#e36742","#3f74c9","#5aa53d"];
    for(let i=0;i<3;i++){ const gx=6.3+i*.69, gy=3.1, w=.64, d=.62, h=21;
      let g=box(gx,gy,w,d,h,"#d9d3c7",fac[i],sid[i]);
      g+=poly([pt(gx+.07,gy+d,12),pt(gx+w-.07,gy+d,12),pt(gx+w-.07,gy+d,2),pt(gx+.07,gy+d,2)],LIT?OFF:DAYWIN,`stroke="${shade("#ffffff",.9)}" stroke-width=".6"`);
      g+=poly([pt(gx+.02,gy+d,17),pt(gx+w-.02,gy+d,17),pt(gx+w-.02,gy+d+.2,12.5),pt(gx+.02,gy+d+.2,12.5)],shade(aw[i],1));
      for(let k=0;k<3;k++){ const a=gx+.1+k*.18; g+=poly([pt(a,gy+d,17),pt(a+.07,gy+d,17),pt(a+.07,gy+d+.2,12.5),pt(a,gy+d+.2,12.5)],shade("#ffffff",.95)); }
      let top=h+8;
      if(i===1){ const tx=gx+.17, ty=gy+.16, tw=.3, th=h+24; top=th+13;
        g+=box(tx,ty,tw,tw,th,"#e9dcc6","#f1e6d2","#d8c9b0",h);
        const cx=X(tx+tw/2,ty+tw), cy=Y(tx+tw/2,ty+tw)-th+8, ap=pt(tx+tw/2,ty+tw/2,th+13);
        g+=`<circle cx="${cx}" cy="${cy}" r="4" fill="${shade("#ffffff",1)}" stroke="${shade("#6b5a44",1)}" stroke-width="1"/><path d="M${cx} ${cy}v-2.8M${cx} ${cy}h2.2" stroke="${shade("#2b2f36",1)}" stroke-width=".9"/>`;
        g+=poly([pt(tx,ty+tw,th),pt(tx+tw,ty+tw,th),ap],shade(SNOW?SNOWC:"#3f74c9",1))+poly([pt(tx+tw,ty,th),pt(tx+tw,ty+tw,th),ap],shade(SNOW?SNOWC:"#2f5ea8",1)); }
      else g+=box(gx+.12,gy+.14,.4,.08,h+8,"#ffffff",aw[i],aw[i],h);
      add(gx,gy,gx+w,gy+d+.2,top,rise(g,gx,gy,w,d,1,.3+i*.12),{name:"shop"+i,parts:[[gx,gy,gx+w,gy+d+.2,h],i===1?[gx+.17,gy+.16,gx+.47,gy+.46,h+37]:[gx+.12,gy+.14,gx+.52,gy+.22,h+8]]}); } }
  // ---- town landmarks: the water tower (stays all game) and a bandstand in the park (paved over by industry) ----
  if(TOWN){ const gx=4.5, gy=9.6, x=X(gx,gy), y=Y(gx,gy), lg=shade("#8b939c",1);
    const g=`<ellipse cx="${x}" cy="${y}" rx="16" ry="6" fill="#000" opacity=".15"/>`+[[-11,4],[11,4],[-6,-3],[6,-3]].map(([dx,dy])=>`<line x1="${x+dx}" y1="${y+dy}" x2="${x+dx*.45}" y2="${y-40}" stroke="${lg}" stroke-width="2"/>`).join("")+
      `<line x1="${x-9}" y1="${y-14}" x2="${x+9}" y2="${y-26}" stroke="${lg}" stroke-width="1"/><line x1="${x+9}" y1="${y-14}" x2="${x-9}" y2="${y-26}" stroke="${lg}" stroke-width="1"/>`+
      `<ellipse cx="${x}" cy="${y-40}" rx="14" ry="5" fill="${shade("#79aad0",1)}"/><rect x="${x-14}" y="${y-62}" width="28" height="22" fill="${shade("#8fc0e3",1)}"/><rect x="${x}" y="${y-62}" width="14" height="22" fill="#000" opacity=".12"/><rect x="${x-14}" y="${y-55}" width="28" height="3" fill="${shade("#ffffff",1)}" opacity=".8"/><ellipse cx="${x}" cy="${y-62}" rx="15" ry="5" fill="${shade(SNOW?SNOWC:"#cf5a38",1)}"/><path d="M${x-15} ${y-62}L${x} ${y-75}L${x+15} ${y-62}Z" fill="${shade(SNOW?SNOWC:"#e36742",1)}"/>`;
    add(gx-.22,gy-.22,gx+.22,gy+.22,75,rise(g,gx-.2,gy-.2,.4,.4,1,.5),{name:"watertower"}); }
  if(TOWN&&!IND){ const gx=7.3, gy=6.6, w=.5, d=.5, h=13, post=shade("#f3ead8",1), R=SNOW?SNOWC:"#d9573f";
    let g=poly(quad([gx-.08,gy-.08],[gx+w+.08,gy+d+.08],1.5),shade("#d8cfc0",1));
    [[gx,gy],[gx+w,gy],[gx,gy+d],[gx+w,gy+d]].forEach(([a,b])=>g+=`<line x1="${X(a,b)}" y1="${Y(a,b)}" x2="${X(a,b)}" y2="${Y(a,b)-h}" stroke="${post}" stroke-width="1.6"/>`);
    const ap=pt(gx+w/2,gy+d/2,h+11);
    g+=poly([pt(gx-.1,gy+d+.1,h),pt(gx+w+.1,gy+d+.1,h),ap],shade(R,1))+poly([pt(gx+w+.1,gy-.1,h),pt(gx+w+.1,gy+d+.1,h),ap],shade(R,.8));
    add(gx-.1,gy-.1,gx+w+.1,gy+d+.1,h+11,rise(g,gx,gy,w,d,1,.6),{name:"bandstand"});
    [[6.5,7.0],[8.0,7.45]].forEach(([a,b],i)=>add(a,b,a+.3,b+.08,4,rise(poly(quad([a,b],[a+.3,b+.08],3),shade("#a26b3c",1)),a,b,.3,.08,1,.65+i*.05),{name:"bench"+i})); }

  // ---- hospital: the one building that must never go dark ----
  if(P.has_hospital){ const on=!LIT||state.hosp, gx=6.25, gy=.5, w=2.1, d=1.9, h=52;
    let g=box(gx,gy,w,d,h,"#e9edf1","#ffffff","#dfe5ec");
    g+=box(gx+.2,gy+.2,.45,.3,h+7,"#c9d1da","#b6c0cb","#a6b1bd",h)+box(gx+1.5,gy+.2,.4,.3,h+4,"#7fb8e8","#5e9fd6","#4f8cc2",h);
    const cross=on?(NIGHTISH?"#ff4d4f":"#e5383b"):"#4a2a2e";
    g+=poly([pt(gx+.9,gy+.7,h),pt(gx+1.2,gy+.7,h),pt(gx+1.2,gy+1.5,h),pt(gx+.9,gy+1.5,h)],cross)+poly([pt(gx+.65,gy+.95,h),pt(gx+1.45,gy+.95,h),pt(gx+1.45,gy+1.25,h),pt(gx+.65,gy+1.25,h)],cross);
    if(LIT&&on) g+=glow(gx+1.05,gy+1.1,40,.3,"#ff4d4f");
    for(let f=0;f<3;f++){ for(let i=0;i<5;i++) g+=winF(gx+.12+i*.4,gy+d,h-8-f*15,LIT&&on,.2,9); for(let i=0;i<4;i++) g+=winS(gx+w,gy+.15+i*.42,h-8-f*15,LIT&&on,.22,9); }
    g+=poly([pt(gx+.75,gy+d,14),pt(gx+1.35,gy+d,14),pt(gx+1.35,gy+d+.35,12),pt(gx+.75,gy+d+.35,12)],shade("#7fc4ee",1))+poly([pt(gx+.85,gy+d,12),pt(gx+1.25,gy+d,12),pt(gx+1.25,gy+d,0),pt(gx+.85,gy+d,0)],LIT&&on?WARMW:shade("#9fd3ef",1));
    if(NIGHT){ const [mx,my]=pt(gx+w,gy+1.55,7).split(",").map(Number), mc=state.hosp?"#6fe0ff":"#ef6b6b";   // service point where the hospital's line arrives
      g+=(state.hosp?`<circle cx="${mx}" cy="${my}" r="5" fill="${mc}" opacity=".3"/>`:"")+`<rect x="${mx-2.2}" y="${my-2.6}" width="4.4" height="5.2" rx="1" fill="${state.hosp?mc:"#5a2a30"}" stroke="${state.hosp?"#e8fdff":"#ef6b6b"}" stroke-width=".6"/>`; }
    if(!on){ const x=X(gx+1.05,gy+.95), y=Y(gx+1.05,gy+.95)-h/2; g+=glow(gx+1,gy+1,60,.22,"#ff4d4f")+`<ellipse class="alarm" cx="${x}" cy="${y}" rx="62" ry="40" fill="none" stroke="#ef6b6b" stroke-width="2.5" style="transform-origin:${x}px ${y}px"/>`; }
    add(gx,gy,gx+w,gy+d,h+7,rise(g,gx,gy,w,d,1,.1),{name:"hospital",parts:[[gx,gy,gx+w,gy+d,h],[gx+.2,gy+.2,gx+.65,gy+.5,h+7],[gx+1.5,gy+.2,gx+1.9,gy+.5,h+4]]});
    zone(6.95,2.4,7.65,2.8);   // entrance canopy
    add(7.68,2.45,8.23,2.75,14,rise(box(7.68,2.45,.55,.3,11,"#ffffff","#f5f5f5","#e2e2e2")+poly([pt(7.83,2.75,9),pt(8.03,2.75,9),pt(8.03,2.75,5),pt(7.83,2.75,5)],shade("#e5383b",1))+box(7.91,2.55,.1,.1,14,"#e5383b","#c92f32","#b0282b",11),7.68,2.45,.55,.3,1,.65),{name:"ambulance"}); }

  // ---- factory: windows and smoke follow factory_on; dark if the rules wanted it on and power ran short ----
  if(P.has_factory){ const on=!LIT||state.fac, gx=6.25, gy=6.1, w=2.3, d=1.5, h=26;
    let g=box(gx,gy,w,d,h,"#8b8f96","#a5a9b0","#8e9299");
    for(let i=0;i<3;i++){ const a=gx+i*.75; g+=poly([pt(a,gy,h),pt(a,gy+d,h),pt(a+.75,gy+d,h+12),pt(a+.75,gy,h+12)],shade(SNOW?SNOWC:"#6f747c",1))+poly([pt(a+.75,gy,h+12),pt(a+.75,gy+d,h+12),pt(a+.75,gy+d,h),pt(a+.75,gy,h)],shade("#bfe3f5",1-DARK*.4)); }
    for(let k=0;k<2;k++){ const cx=gx+1.5+k*.45, cy=gy+.2; for(let b=0;b<4;b++) g+=box(cx,cy,.24,.24,h+12+(b+1)*9,b%2?"#ffffff":"#e8662f",b%2?"#f2f2f2":"#d9582a",b%2?"#dcdcdc":"#bf4c24",h+12+b*9); }
    for(let i=0;i<5;i++) g+=winF(gx+.12+i*.43,gy+d,h-8,LIT&&on,.24,9);
    if(on) g+=`<g class="smoke${STORM?" wind":""}">${[0,1].map(k=>{ const x=X(gx+1.62+k*.45,gy+.32), y=Y(gx+1.62+k*.45,gy+.32)-h-56; return `<circle cx="${x}" cy="${y}" r="8" fill="#ffffff" opacity=".75"/><circle cx="${x+9}" cy="${y-10}" r="10" fill="#f1f1f1" opacity=".55"/>`; }).join("")}</g>`;
    if(NIGHT&&E.facWanted&&!state.fac){ const x=X(gx+w/2,gy+d/2), y=Y(gx+w/2,gy+d/2)-h/2; g+=`<ellipse class="alarm" cx="${x}" cy="${y}" rx="70" ry="40" fill="none" stroke="#ef6b6b" stroke-width="2" style="transform-origin:${x}px ${y}px"/>`; }
    add(gx,gy,gx+w,gy+d,h+48,rise(g,gx,gy,w,d,2,.05),{name:"factory",parts:[[gx,gy,gx+w,gy+d,h+12],[gx+1.5,gy+.2,gx+1.74,gy+.44,h+48],[gx+1.95,gy+.2,gx+2.19,gy+.44,h+48]]});
    add(7.62,7.75,8.34,8.05,13,rise(box(7.62,7.75,.5,.3,13,"#f4f4f4","#ffffff","#dedede")+box(8.12,7.75,.22,.3,10,"#e8662f","#d9582a","#bf4c24"),7.62,7.75,.72,.3,2,.4),{name:"delivery truck"}); }
  // ---- industrial district: warehouse, tanks, containers, smokestack, freight cars, power line ----
  if(IND){ zone(6.2,5.2,9.05,8.42);
    const wx=6.35, wy=7.85, ww=1.15, wd=.45, wh=15;
    let g=box(wx,wy,ww,wd,wh,"#c7b28c","#d6c29c","#b8a37f");
    for(let i=0;i<3;i++) g+=poly([pt(wx+.1+i*.36,wy+wd,10),pt(wx+.36+i*.36,wy+wd,10),pt(wx+.36+i*.36,wy+wd,0),pt(wx+.1+i*.36,wy+wd,0)],shade("#7d7466",1));
    g+=poly([pt(wx,wy+wd,wh),pt(wx+ww,wy+wd,wh),pt(wx+ww,wy+wd,wh-2),pt(wx,wy+wd,wh-2)],shade("#e36742",1));
    addAt(wx,wy,ww,wd,wh,rise(g,wx,wy,ww,wd,2,.35),{name:"warehouse"});
    [[8.8,7.7],[8.8,8.2]].forEach(([gx,gy],i)=>{ const x=X(gx,gy), y=Y(gx,gy), r=11, h=28;
      add(gx-.22,gy-.22,gx+.22,gy+.22,h+6,rise(`<ellipse cx="${x}" cy="${y}" rx="${r}" ry="${r/2}" fill="${shade("#9aa2ab",1)}"/><rect x="${x-r}" y="${y-h}" width="${2*r}" height="${h}" fill="${shade("#d5dbe1",1)}"/><rect x="${x}" y="${y-h}" width="${r}" height="${h}" fill="#000" opacity=".12"/><rect x="${x-r}" y="${y-h+9}" width="${2*r}" height="4" fill="${shade("#e36742",1)}"/><ellipse cx="${x}" cy="${y-h}" rx="${r}" ry="${r/2}" fill="${shade(SNOW?SNOWC:"#eef1f4",1)}"/>`,gx-.2,gy-.2,.4,.4,2,.5),{name:"tank"+i}); });
    [6.2,7.0,7.8].forEach((gy,i)=>addAt(9.72,gy,.24,.7,11,rise(box(9.72,gy,.24,.7,11,"#a8503a","#b85a42","#94432f"),9.72,gy,.24,.7,2,.6+i*.08),{name:"freight"+i}));
    // containers: one item per stack, so stacked boxes share a footprint instead of colliding
    [[8.62,5.3,["#e36742","#2f8f9a"]],[8.86,5.3,["#3f74c9"]],[8.62,5.66,["#5aa53d"]],[8.86,5.66,["#d9a23a","#c0392b"]]].forEach(([gx,gy,cols],i)=>{
      const g=cols.map((col,l)=>box(gx,gy,.22,.34,l*8+8,col,dk(col,.85),dk(col,.7),l*8)).join("");
      addAt(gx,gy,.22,.34,cols.length*8,rise(g,gx,gy,.22,.34,2,.4+i*.06),{name:"containers"+i}); });
    { const gx=8.66, gy=6.75, w=.2, d=.2, h=78; let g="";
      for(let b=0;b<6;b++) g+=box(gx,gy,w,d,(b+1)*13,b%2?"#f2f2f2":"#a8503a",b%2?"#e8e8e8":"#b85a42",b%2?"#d6d6d6":"#94432f",b*13);
      if(P.has_factory&&(!LIT||state.fac)) g+=smoke(X(gx+.1,gy+.1),Y(gx+.1,gy+.1)-h-8,1.4,"smoke"+(STORM?" wind":""));
      addAt(gx,gy,w,d,h+20,rise(g,gx,gy,w,d,2,.2),{name:"smokestack"}); }
    const pyl=[[9.4,5.5],[9.4,6.95],[9.4,8.4]], PH=50, st=shade("#7d8792",1);
    pyl.forEach(([gx,gy],i)=>{ const x=X(gx,gy), y=Y(gx,gy);
      add(gx-.15,gy-.1,gx+.15,gy+.1,PH,rise(`<path d="M${x-7} ${y}L${x-1.5} ${y-PH}M${x+7} ${y}L${x+1.5} ${y-PH}M${x-5.6} ${y-12}L${x+4.4} ${y-24}M${x+5.6} ${y-12}L${x-4.4} ${y-24}M${x-4} ${y-26}L${x+3} ${y-38}M${x+4} ${y-26}L${x-3} ${y-38}M${x-12} ${y-PH+4}H${x+12}M${x-9} ${y-PH+12}H${x+9}" stroke="${st}" stroke-width="1.3" fill="none"/>`,gx-.1,gy-.1,.2,.2,2,.3+i*.1),{name:"pylon"+i}); });
    let wires=""; for(let i=0;i<2;i++){ const a=pyl[i], b=pyl[i+1]; for(const [dy,dx] of [[PH-4,-12],[PH-4,12],[PH-12,-9],[PH-12,9]]){ const x1=X(...a)+dx, y1=Y(...a)-dy, x2=X(...b)+dx, y2=Y(...b)-dy; wires+=`<path d="M${x1} ${y1}Q${(x1+x2)/2} ${(y1+y2)/2+8} ${x2} ${y2}" stroke="${shade("#3a4048",1)}" stroke-width=".7" fill="none"/>`; } }
    late+=GROW===2?`<g class="fadein" style="animation-delay:.85s">${wires}</g>`:wires; }

  // ---- public buildings on the south strip, one more each night from night 6 (each counts as one house on the grid) ----
  const CIVIC={market:{gx:.45,gy:10.35,w:1.25,d:.8,h:17,at:5},school:{gx:2.0,gy:10.3,w:1.5,d:.85,h:22,at:6},pharmacy:{gx:6.45,gy:10.4,w:.8,d:.7,h:17,at:7},fire:{gx:7.55,gy:10.3,w:1.25,d:.85,h:20,at:8},library:{gx:3.85,gy:10.35,w:.95,d:.8,h:20,at:9}};
  const civOn=k=>LIT&&P.homes+k<lit, civWin=(on)=>LIT?(on?WARMW:OFF):DAYWIN;
  const frontQ=(B,x0,x1,z0,z1)=>[pt(B.gx+x0,B.gy+B.d,z1),pt(B.gx+x1,B.gy+B.d,z1),pt(B.gx+x1,B.gy+B.d,z0),pt(B.gx+x0,B.gy+B.d,z0)];
  P.civic.forEach((id,k)=>{ const B=CIVIC[id], {gx,gy,w,d,h}=B, on=civOn(k); let g="";
    if(id==="market"){ g+=box(gx,gy,w,d,h,"#e9ece4","#f4f5ef","#dcdfd4");
      g+=poly(frontQ(B,.06,w-.06,2,10),civWin(on),`stroke="${shade("#ffffff",.9)}" stroke-width=".6"`);
      g+=poly(frontQ(B,0,w,h-5,h),shade("#2e9a55",1))+poly(frontQ(B,.08,w-.08,11,13),shade("#e36742",1));
      g+=box(gx+.35,gy+.32,.55,.08,h+9,"#2e9a55","#2e9a55","#24804a",h);
      const [tx,ty]=pt(gx+.63,gy+.4,h+5.5).split(",").map(Number); g+=`<rect x="${tx-9}" y="${ty-1.4}" width="18" height="2.4" rx="1" fill="${shade("#ffffff",1)}"/>`;
      for(let i=0;i<4;i++){ const a=gx+.15+i*.28; g+=`<line x1="${X(a,gy+d+.08)}" y1="${Y(a,gy+d+.08)}" x2="${X(a,gy+d+.32)}" y2="${Y(a,gy+d+.32)}" stroke="${shade("#ffffff",1)}" stroke-width=".8" opacity=".7"/>`; } }
    if(id==="school"){ g+=box(gx,gy,w,d,h,"#c8644a","#d4705a","#b0563f");
      g+=poly(frontQ(B,0,w,10.5,12),shade("#f3ead8",1));
      for(let r=0;r<2;r++) for(let i=0;i<5;i++) if(!(r===0&&i===2)) g+=winF(gx+.1+i*.28,gy+d,8+r*10,on,.16,6);
      for(let r=0;r<2;r++) for(let i=0;i<2;i++) g+=winS(gx+w,gy+.15+i*.35,8+r*10,on,.18,6);
      g+=poly(frontQ(B,.66,.84,0,8),shade("#7a4a2c",1));
      g+=box(gx+.6,gy+.25,.3,.3,h+10,"#f3ead8","#f6eedf","#dfd2bb",h);
      const ap=pt(gx+.75,gy+.4,h+19); g+=poly([pt(gx+.58,gy+.57,h+10),pt(gx+.92,gy+.57,h+10),ap],shade(SNOW?SNOWC:"#3f74c9",1))+poly([pt(gx+.92,gy+.23,h+10),pt(gx+.92,gy+.57,h+10),ap],shade(SNOW?SNOWC:"#2f5ea8",1));
      const [fx,fy]=pt(gx+w-.08,gy+d-.08,h).split(",").map(Number); g+=`<line x1="${fx}" y1="${fy}" x2="${fx}" y2="${fy-18}" stroke="${shade("#b7bcc3",1)}" stroke-width="1"/><path d="M${fx} ${fy-18}h8v5h-8z" fill="${shade("#e5383b",1)}"/><path d="M${fx} ${fy-15.5}h8" stroke="${shade("#ffffff",1)}" stroke-width="1"/>`; }
    if(id==="pharmacy"){ g+=box(gx,gy,w,d,h,"#eef3f4","#f7fafa","#dfe7e9");
      g+=poly(frontQ(B,.06,w-.06,2,10.5),civWin(on),`stroke="${shade("#ffffff",.9)}" stroke-width=".6"`)+poly(frontQ(B,0,w,h-3.5,h),shade("#2fae5f",1));
      const [cx,cy]=pt(gx+w-.02,gy+d+.04,h-7).split(",").map(Number), cc=on||!LIT?"#2fae5f":"#1f4a32";
      g+=(on?`<circle cx="${cx}" cy="${cy}" r="9" fill="#2fae5f" opacity="${(.3*GL).toFixed(2)}"/>`:"")+`<rect x="${cx-5}" y="${cy-5}" width="10" height="10" rx="1.5" fill="${shade("#ffffff",1)}"/><path d="M${cx-1.4} ${cy-3.6}h2.8v2.2h2.2v2.8h-2.2v2.2h-2.8v-2.2h-2.2v-2.8h2.2z" fill="${cc}"/>`; }
    if(id==="fire"){ g+=box(gx,gy,w,d,h,"#c8392f","#d6463a","#a92f27");
      for(let i=0;i<2;i++){ const a=.1+i*.56; g+=poly(frontQ(B,a,a+.46,0,12),shade(on||!LIT?"#f2f2f2":"#8a8f96",1)); for(let r=1;r<4;r++){ const [x1,y1]=pt(gx+a,gy+d,r*3).split(","), [x2,y2]=pt(gx+a+.46,gy+d,r*3).split(","); g+=`<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="${shade("#b8bcc2",1)}" stroke-width=".6"/>`; } }
      for(let i=0;i<4;i++) g+=winF(gx+.12+i*.27,gy+d,h-3,on,.15,4);
      g+=box(gx+.1,gy+.08,.28,.28,h+15,"#c8392f","#d6463a","#a92f27",h);
      const [sx,sy]=pt(gx+.24,gy+.22,h+17).split(",").map(Number); g+=`<circle cx="${sx}" cy="${sy}" r="2" fill="${on?"#ff5a5a":shade("#8a2a24",1)}"/>`; }
    if(id==="library"){ g+=box(gx,gy,w,d,h,"#e6d8b8","#efe5cc","#d8caa8");
      g+=poly(frontQ(B,0,w,0,2.5),shade("#d8cfc0",1));
      for(let i=0;i<4;i++){ const a=.1+i*.25; g+=poly(frontQ(B,a,a+.07,2.5,h-3),shade("#ffffff",1)); if(i<3) g+=poly(frontQ(B,a+.1,a+.22,6,h-6),civWin(on)); }
      g+=poly([pt(gx-.03,gy+d+.02,h),pt(gx+w+.03,gy+d+.02,h),pt(gx+w/2,gy+d+.02,h+9)],shade(SNOW?SNOWC:"#f3ead8",1),`stroke="${shade("#cfc3a3",1)}" stroke-width=".6"`); }
    if(NIGHT){ const [mx,my]=pt(gx+w*.85,gy+d,6).split(",").map(Number), mc=on?"#6fe0ff":"#ef6b6b";      // service point: its connection to the grid
      g+=(on?`<circle cx="${mx}" cy="${my}" r="4.2" fill="${mc}" opacity=".28"/>`:"")+`<rect x="${mx-1.8}" y="${my-2.2}" width="3.6" height="4.4" rx="1" fill="${on?mc:"#5a2a30"}" stroke="${on?"#e8fdff":"#ef6b6b"}" stroke-width=".6"/>`; }
    if(on) g+=glow(gx+w/2,gy+d+.3,30,.2);
    add(gx,gy,gx+w,gy+d,h+19,rise(g,gx,gy,w,d,B.at,.15),{name:id}); });

  // ---- generation: solar panels (they only make energy by day, in the model) ----
  const nPan=Math.min(c.panels+(state.ghost==="panel"?1:0),15);
  zone(.6,5.25,4.45,(nPan>10?8.1:nPan>5?7.05:6.0)+.8);   // panel rows plus a clear strip in front, so nothing hides them
  const PAN=mixc(WARM?"#4a6fc0":"#2f6fd1","#14284c",DARK), PANL=mixc("#d8ecff","#2c4478",DARK), FRAME=shade("#c7ccd3",1);
  for(let i=0;i<nPan;i++){ const gx=.7+(i%5)*.75, gy=5.35+Math.floor(i/5)*1.05, x=X(gx+.31,gy+.3), y=Y(gx+.31,gy+.3);
    const A=[gx,gy,8], B=[gx+.62,gy,8], Cc=[gx+.62,gy+.6,16], D=[gx,gy+.6,16], L=(p,q,t)=>p.map((v,k)=>v+(q[k]-v)*t), P2=p=>pt(...p);
    let g=`<line x1="${x}" y1="${y}" x2="${x}" y2="${y-10}" stroke="${shade("#8d96a1",1)}" stroke-width="1.8"/><line x1="${X(gx+.1,gy+.55)}" y1="${Y(gx+.1,gy+.55)}" x2="${X(gx+.1,gy+.55)}" y2="${Y(gx+.1,gy+.55)-15}" stroke="${shade("#8d96a1",1)}" stroke-width="1.2"/>`;
    g+=poly([P2(A),P2(B),P2(Cc),P2(D)],PAN,`stroke="${FRAME}" stroke-width="1.2"`);
    for(const t of [1/3,2/3]) g+=`<line x1="${X(...L(A,B,t))}" y1="${Y(...L(A,B,t))-L(A,B,t)[2]}" x2="${X(...L(D,Cc,t))}" y2="${Y(...L(D,Cc,t))-L(D,Cc,t)[2]}" stroke="${PANL}" stroke-width=".6"/>`;
    const m1=L(A,D,.5), m2=L(B,Cc,.5); g+=`<line x1="${X(...m1)}" y1="${Y(...m1)-m1[2]}" x2="${X(...m2)}" y2="${Y(...m2)-m2[2]}" stroke="${PANL}" stroke-width=".6"/>`;
    if(solarOn){ const a=L(A,B,.15), b=L(A,B,.35), cc=L(D,Cc,.55), dd=L(D,Cc,.35); g+=`<polygon class="glint" points="${[a,b,cc,dd].map(P2).join(" ")}" fill="#ffffff" style="--gl:${(.25+P.sun/14).toFixed(2)};${sync(3.4,i*.45)}"/>`; }
    addAt(gx,gy,.62,.6,16,i>=c.panels?`<g class="ghost">${g}</g>`:g,{name:"panel"+i}); }

  // ---- storage: battery containers with a charge gauge (stored energy vs capacity, from aityx) ----
  const cells=Math.min(5,Math.max(1,Math.round(cap/35))), cellCap=cap/cells;
  zone(.3,8.5,.65+cells*.85,9.95);                                 // battery yard and the ground in front of it
  for(let i=0;i<cells;i++){ const gx=.65+i*.85, gy=8.55, w=.7, d=.6, h=22;
    const f=stored==null?0:Math.max(0,Math.min(1,(stored-i*cellCap)/cellCap));
    const lvl=stored==null?"#5f6b78":stored/cap>.5?"#5fd38a":stored/cap>.2?"#f2c14e":"#ef6b6b";
    let g=box(gx,gy,w,d,h,"#5f9a6a","#4f8a5b","#3f7a4c");
    g+=box(gx+.28,gy+.22,.14,.16,h+3,"#c9ced6","#b6bcc5","#a3aab3",h);                         // terminal: reads as a battery
    const g0=gx+.14, g1=gx+.56, z0=3, z1=h-4;                                                  // gauge window on the front face
    g+=poly([pt(g0,gy+d,z1),pt(g1,gy+d,z1),pt(g1,gy+d,z0),pt(g0,gy+d,z0)],NIGHTISH?"#0d151c":"#20302a",`stroke="${shade("#cfe9d8",1)}" stroke-width=".6"`);
    if(f>0){ const zt=z0+(z1-z0)*f; g+=poly([pt(g0+.03,gy+d,zt),pt(g1-.03,gy+d,zt),pt(g1-.03,gy+d,z0+1),pt(g0+.03,gy+d,z0+1)],lvl,LIT?`opacity=".95"`:""); }
    addAt(gx,gy,w,d,h+3,g,{name:"battery"+i}); }
  if(state.ghost==="battery"){ const cG=Math.min(5,Math.max(1,Math.round((cap+30)/35)));
    if(cG>cells){ const gx=.65+cells*.85, gy=8.55; zone(gx-.05,8.5,gx+.75,9.95); addAt(gx,gy,.7,.6,25,`<g class="ghost">${box(gx,gy,.7,.6,22,"#5f9a6a","#4f8a5b","#3f7a4c")+box(gx+.28,gy+.22,.14,.16,25,"#c9ced6","#b6bcc5","#a3aab3",22)}</g>`,{name:"battery-new"}); }
    else { const bx=X(.65+cells*.85/2,8.55)-6, by=Y(.65+cells*.85/2,8.55)-58; late+=`<g class="ghost"><rect x="${bx-26}" y="${by-10}" width="52" height="15" rx="7.5" fill="rgba(10,14,20,.78)" stroke="#7dff9a"/><text x="${bx}" y="${by+1}" text-anchor="middle" font-family="Red Hat Mono,monospace" font-size="10" font-weight="600" fill="#7dff9a">+30 CAP</text></g>`; } }
  { // the yard tag: stored / capacity, and whether it is charging or discharging this hour
    const bx=X(.65+cells*.85/2,8.55)-6, by=Y(.65+cells*.85/2,8.55)-40;
    const empty=stored===0, dir=NIGHT?(E.after<E.before?-1:E.after>E.before?1:0):0;
    const txt=E.mode==="plan"?`CAPACITY ${Math.round(cap)}`:`${Math.round(stored)} / ${Math.round(cap)}`+(E.mode==="dusk"?" AT DUSK":E.mode==="morning"?" LEFT":"");
    const col=empty?"#ef6b6b":dir<0?"#f2c14e":dir>0?"#7dff9a":"#cfd6df", wdt=(empty?("EMPTY · 0 / "+Math.round(cap)).length:txt.length)*6.15+(dir?24:14);
    late+=`<g${empty?' class="pulse2"':""}><rect x="${(bx-wdt/2).toFixed(1)}" y="${by-11}" width="${wdt.toFixed(1)}" height="16" rx="8" fill="rgba(10,14,20,.78)" stroke="${col}" stroke-width="1"/>`+
      `<text x="${(bx-wdt/2+8).toFixed(1)}" y="${by+1}" font-family="Red Hat Mono,monospace" font-size="10" font-weight="600" fill="${col}">${empty?"EMPTY · 0 / "+Math.round(cap):txt}</text>`+
      (dir?`<g class="chev${dir>0?" up":""}" style="${sync(1.6)}"><path d="M${(bx+wdt/2-15).toFixed(1)} ${dir>0?by-1:by-6}l3.5 ${dir>0?-4:4}l3.5 ${dir>0?4:-4}" fill="none" stroke="${col}" stroke-width="1.6"/></g>`:"")+`</g>`; }

  // ---- generation: wind turbines, in the energy park with the panels and batteries; they spin only while the night's wind feeds them ----
  const nTurb=Math.min(c.turbines+(state.ghost==="turbine"?1:0),7);
  for(let i=0;i<nTurb;i++){ const gx=.24, gy=5.45+i*.7, ghost=state.ghost==="turbine"&&i===c.turbines, x=X(gx,gy), y=Y(gx,gy), spin=windNow>0;
    addAt(gx-.06,gy-.06,.12,.12,97,(ghost?'<g class="ghost">':'')+`<ellipse cx="${x}" cy="${y}" rx="7" ry="3" fill="#000" opacity=".15"/><path d="M${x-2.4} ${y}L${x-1} ${y-70}L${x+1} ${y-70}L${x+2.4} ${y}Z" fill="${shade("#ffffff",1)}"/><g transform="translate(${x} ${y-70})"><g${spin?` class="spin" style="animation-duration:${(3.4/windNow).toFixed(2)}s"`:` transform="rotate(${i*23})"`}>${[0,120,240].map(a=>`<g transform="rotate(${a})"><path d="M0 0L-2 -24L0 -27L2 -24Z" fill="${shade("#ffffff",1)}"/><path d="M-1.6 -19L0 -27L1.6 -19Z" fill="${shade("#e8662f",1)}"/></g>`).join("")}</g></g><circle cx="${x}" cy="${y-70}" r="2.6" fill="${shade(spin?"#7dff9a":"#c9ced6",1)}"/>`+(ghost?'</g>':''),{name:"turbine"+i}); }

  // ================= placement helpers =================
  const onRoad=(gx,gy,r)=>(gy+r>4&&gy-r<5)||(gx+r>5&&gx-r<6);
  const inZone=(gx,gy,r)=>zones.some(z=>gx+r>z[0]&&gx-r<z[2]&&gy+r>z[1]&&gy-r<z[3]);
  const behind=(a,b)=>{ if(b.x0>=a.x1-1e-6) return true; if(a.x0>=b.x1-1e-6) return false; if(b.y0>=a.y1-1e-6) return true; if(a.y0>=b.y1-1e-6) return false; return a.x0+a.x1+a.y0+a.y1<=b.x0+b.x1+b.y0+b.y1; };
  const gapTo=(p,b)=>Math.hypot(Math.max(b.x0-p.gx,0,p.gx-b.x1),Math.max(b.y0-p.gy,0,p.gy-b.y1))-p.r;
  const taken=[];
  const fits=p=>{ if(onRoad(p.gx,p.gy,p.r)||inZone(p.gx,p.gy,p.r)||inPond(p.gx,p.gy,p.r)) return false;
    if(p.gx-p.r<.05||p.gy-p.r<.05||p.gx+p.r>NX-.05||p.gy+p.r>NY-.05||(IND&&p.gx+p.r>9.66)) return false;
    const x=X(p.gx,p.gy), y=Y(p.gx,p.gy), me={x0:p.gx-p.r,y0:p.gy-p.r,x1:p.gx+p.r,y1:p.gy+p.r}, hit=(b,list)=>list.some(([dx,dy])=>b.hull.some(H=>inHull(H,x+dx,y+dy)));
    for(const b of solids){ const g=gapTo(p,b); if(g<(p.kind==="pole"?.18:.04)) return false;   // never on a building's ground
      if(b.h<=26) continue;                                                                    // low things never hide a prop
      if(behind(b,me)){ if(g<.5&&hit(b,p.samples)) return false; }                             // in front: only with open ground between
      else if(hit(b,p.samples.slice(0,3))) return false; }                                    // behind a tall one: its base and pole stay in view
    for(const q of taken) if(Math.hypot(q.gx-p.gx,q.gy-p.gy)<q.r+p.r) return false;
    return true; };
  const place=p=>{ if(!fits(p)) return false; taken.push(p); add(p.gx-p.r,p.gy-p.r,p.gx+p.r,p.gy+p.r,p.h,p.svg(),{solid:false,name:p.kind}); return true; };

  // ================= power distribution network (illustrative) =================
  // The model counts energy for the whole city per hour; it does not route wires. This network only shows the idea:
  // sun and wind -> battery yard -> main line along the south kerb -> branches to the houses, the hospital and the factory.
  // Every colour comes from aityx's answers for this hour. Poles are the streetlights; they sit only on kerbs that stay clear in every chapter.
  {   // all distribution lines run on the ground; streetlights are plain lamps beside them
    const dischg=NIGHT&&E.after<E.before, chg=NIGHT&&E.after>E.before, windOn=NIGHT&&c.turbines>0&&windNow>0, supply=dischg||windOn||chg;
    const hSt=NIGHT?(state.lit>=P.houses?"flow":state.lit>0?"weak":"dead"):"idle";
    const hoSt=NIGHT&&P.has_hospital?(state.hosp?"flow":"dead"):"idle";
    const fSt=NIGHT&&P.has_factory&&E.facWanted?(state.fac?"flow":"dead"):"idle";
    const lSt=NIGHT&&P.has_lights&&E.lightsWanted?(state.lights?"flow":"dead"):"idle";
    const COL={flow:"#6fe0ff",charge:"#7dff9a",weak:"#f2c14e",dead:"#ef6b6b"};
    // -- streetlights: plain lamps on fixed sidewalk spots (south kerb of the main road, east kerb of the side road), each checked against every building --
    const LAMPS={W:[.6,5.07,[0,-1]],A:[1.98,5.07,[0,-1]],B:[4.62,5.07,[0,-1]],C:[6.38,5.07,[0,-1]],D:[7.6,5.07,[0,-1]],E:[9.5,5.07,[0,-1]],F:[6.065,7.9,[-1,0]],G:[6.065,9.35,[-1,0]]};
    const LH=32, PS=[[0,0],[0,-10],[0,-20],[0,-32],[-5,-30],[5,-30]], up={};
    for(const [k,[gx,gy]] of Object.entries(LAMPS)) up[k]=fits({kind:"pole",gx,gy,r:.06,samples:PS});
    const lampOn=LIT&&state.lights;
    const lampSvg=(gx,gy,arm)=>{ const x=X(gx,gy), y=Y(gx,gy), pc=shade(VIL?"#7a5430":"#4a535e",1), ac=shade(VIL?"#5a3d22":"#3a424c",1);
      const ae=[gx+arm[0]*.22,gy+arm[1]*.22], lx=X(...ae), ly=Y(...ae)-LH+3;
      let g=`<ellipse cx="${x}" cy="${y}" rx="4" ry="1.8" fill="#000" opacity=".2"/><rect x="${(x-1.2).toFixed(1)}" y="${(y-LH).toFixed(1)}" width="2.4" height="${LH}" rx="1" fill="${pc}"/>`;
      g+=`<path d="M${x} ${(y-LH+1).toFixed(1)}Q${((x+lx)/2).toFixed(1)} ${(y-LH-3).toFixed(1)} ${lx.toFixed(1)} ${ly.toFixed(1)}" fill="none" stroke="${ac}" stroke-width="1.5" stroke-linecap="round"/>`;
      g+=`<rect x="${(lx-3.4).toFixed(1)}" y="${(ly-1.6).toFixed(1)}" width="6.8" height="3.2" rx="1.4" fill="${shade(SNOW?SNOWC:VIL?"#4a3424":"#2f353d",1)}"/><rect x="${(lx-2.5).toFixed(1)}" y="${(ly+1.2).toFixed(1)}" width="5" height="1.7" rx=".8" fill="${lampOn?"#ffe28a":LIT?"#2a2f38":shade("#fff3c4",1)}"/>`;
      if(lampOn) s+=`<ellipse cx="${X(...ae).toFixed(1)}" cy="${(Y(...ae)+2).toFixed(1)}" rx="28" ry="12" fill="url(#${LG})" opacity="${GL.toFixed(2)}"/>`;  // light pool on the road
      return g; };
    Object.entries(LAMPS).forEach(([k,[gx,gy,arm]])=>{ if(up[k]) add(gx-.06,gy-.06,gx+.06,gy+.06,LH,lampSvg(gx,gy,arm),{name:"pole"}); });
    // -- cables --
    const ugPts=[];      // underground runs, kept clear of trees
    const pulse=(d,k,dash="1.6 11")=>`<path class="flow" d="${d}" fill="none" stroke="${COL[k]}" stroke-width="2" stroke-linecap="round" stroke-dasharray="${dash}" style="${sync(1.4)}"/>`;
    const ug=(pts,k)=>{ // buried cable: a faint kerbside line with marker dashes; pulses run in the order of the points
      ugPts.push(pts); const d="M"+pts.map(([a,b])=>`${X(a,b).toFixed(1)},${Y(a,b).toFixed(1)}`).join(" L");
      let o=`<path d="${d}" fill="none" stroke="${NIGHTISH?"#0a0f15":"#3a4452"}" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" opacity="${NIGHTISH?.8:.45}"/>`;
      if(k==="idle") o+=`<path d="${d}" fill="none" stroke="${NIGHTISH?"#56606c":"#aab3bd"}" stroke-width=".9" stroke-dasharray="3 4" opacity="${NIGHTISH?.5:.7}"/>`;
      else if(k==="dead") o+=`<path d="${d}" fill="none" stroke="${COL.dead}" stroke-width="1.4" stroke-dasharray="2 5" opacity=".9"/>`;
      else o+=glowLine(d,k)+chevrons(pts,k);
      s+=o; };
    function glowLine(d,k){ return `<path d="${d}" fill="none" stroke="${COL[k]}" stroke-width="8" stroke-linecap="round" stroke-linejoin="round" opacity="${NIGHTISH?.2:.12}"/><path d="${d}" fill="none" stroke="${COL[k]}" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round" opacity="${NIGHTISH?.95:.8}"/><path class="flow" d="${d}" fill="none" stroke="#effdff" stroke-width="2.2" stroke-linecap="round" stroke-dasharray="1.4 13" opacity=".9" style="${sync(1.4)}"/>`; }
    function chevrons(pts,k){ // "›››" on longer runs, lighting up one after another in the direction of flow
      let o=""; for(let i=0;i<pts.length-1;i++){ const x1=X(...pts[i]), y1=Y(...pts[i]), x2=X(...pts[i+1]), y2=Y(...pts[i+1]), L=Math.hypot(x2-x1,y2-y1); if(L<64) continue;
        const ang=Math.atan2(y2-y1,x2-x1)*180/Math.PI, mx=(x1+x2)/2, my=(y1+y2)/2, ux=(x2-x1)/L, uy=(y2-y1)/L;
        for(let j=0;j<3;j++){ const cx=mx+ux*(j-1)*6, cy=my+uy*(j-1)*6;
          o+=`<path class="chv" d="M-2.2,-2.6 L1.4,0 L-2.2,2.6" transform="translate(${cx.toFixed(1)} ${cy.toFixed(1)}) rotate(${ang.toFixed(1)})" fill="none" stroke="${COL[k]}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" style="animation-delay:${(j*.22-((now)%1.2)).toFixed(2)}s"/>`; } }
      return o; }
    const dot=(p,k)=>{ const on=k&&k!=="idle"&&k!=="dead"; s+=(on?`<circle cx="${X(...p).toFixed(1)}" cy="${Y(...p).toFixed(1)}" r="5" fill="${COL[k]}" opacity="${NIGHTISH?.22:.15}"/>`:"")+`<circle cx="${X(...p).toFixed(1)}" cy="${Y(...p).toFixed(1)}" r="2.3" fill="${k&&k!=="idle"?COL[k]:(NIGHTISH?"#3b4450":"#8b95a3")}" stroke="${NIGHTISH?"#05080c":"#2b3340"}" stroke-width=".8"/>`; };
    const TX=2.135, SOLT=[TX,5.98], BATT=[TX,8.5], LY=5.13, KX=6.13;   // TX: the tie runs in the gap between two panel columns   // LY: the main line, on the ground just beside the lamp bases; KX: the side-road kerb line
    // -- generation and storage tie into the main line at A --
    const solK=solarOn?(P.sun>=5?"flow":"weak"):"idle", stK=dischg?"flow":chg?"charge":"idle";
    const out=NIGHT&&(dischg||windOn);   // at night the yard (battery plus wind) feeds the city
    ug(solarOn?[SOLT,BATT]:[BATT,SOLT],solarOn?solK:out?"flow":"idle");       // panels -> battery yard by day; yard -> main line at night
    ug([SOLT,[TX,LY]],out?"flow":"idle");
    dot(SOLT,solarOn?solK:out?"flow":"idle"); dot(BATT,solarOn?solK:out?"flow":"idle");
    // wind collector: each turbine taps into a ground line that runs down the energy park and enters the battery yard from the front
    const nT=Math.min(c.turbines,7);
    if(nT>0){ const wk=windOn?(chg?"charge":"flow"):"idle", WX=.5, WY=9.42;
      ug([[WX,5.45],[WX,WY],[1.0,WY],[1.0,9.2]],wk); dot([1.0,9.2],wk);
      for(let i=0;i<nT;i++){ const ty=5.45+i*.7; ug([[.3,ty],[WX,ty]],wk); dot([WX,ty],wk); } }
    // -- main line: one continuous ground line along the south kerb, west end to east end; it does not depend on which lamps fit --
    const NODES=[.6,TX,4.62,6.38,7.6,9.48], AX=TX;
    // which way energy moves on a stretch (illustrative): out of the battery at A, in from the wind at the east end, toward A when charging
    const trunk=xa=>out?(xa<AX?["flow",true]:["flow",false]):["idle",false];   // energy leaves the yard at A and runs both ways along the main line
    for(let i=0;i<NODES.length-1;i++){ const xa=NODES[i], xb=NODES[i+1], [k,rev]=trunk(xa); ug(rev?[[xb,LY],[xa,LY]]:[[xa,LY],[xb,LY]],k); }
    // each streetlight has a small ground connection point on the line beside its base
    const lineOn=NIGHT&&supply, poleK=lineOn?(lSt==="dead"?"weak":"flow"):"idle";
    Object.entries(LAMPS).forEach(([k,[gx,gy]])=>{ if(up[k]) dot(k==="F"||k==="G"?[KX,gy]:[gx,LY],poleK); });
    // -- houses: from poles A and B, across the road into a service lane beside each column, then a branch to every front door --
    const LANES=[[1.55,"A",[0,3,6]],[3.15,"A",[1,4,7]],[4.72,"B",[2,5,8]]];
    LANES.forEach(([lx,pk,ids])=>{ const hs=ids.filter(i=>i<P.homes); if(!hs.length) return;
      const anyLit=NIGHT&&hs.some(i=>i<state.lit), laneK=NIGHT?(anyLit?(hs.every(i=>i<state.lit)?"flow":"weak"):"dead"):"idle";
      const far=Math.min(...hs.map(i=>slots[i][1]+.97)), px=LAMPS[pk][0];
      ug([[px,LY],[lx,LY],[lx,far]],laneK); dot([lx,LY],laneK);
      hs.forEach(i=>{ const [gx,gy]=slots[i], sy=gy+.97, hk=NIGHT?(i<state.lit?"flow":"dead"):"idle";
        ug([[lx,sy],[gx+.68,sy]],hk); }); });
    // -- hospital: from pole D along the kerb, across the road, up the open strip between the shops and the barn, into its east wall --
    const K0=[6.38,LY];
    if(P.has_hospital){ ug([[7.6,LY],[8.44,LY],[8.44,2.05],[8.37,2.05]],hoSt); dot([8.37,2.05],hoSt);
      if(P.homes>9){ const hk=NIGHT?(9<state.lit?"flow":"dead"):"idle"; ug([[8.44,2.05],[8.44,1.12],[9.05,1.12]],hk); dot([9.05,1.12],hk); } }
    // -- side-road branch: from the main line at the corner, down the east kerb past the two southern streetlights, with a tap into the factory --
    const kerbK=fSt==="flow"||lSt==="flow"?"flow":fSt==="dead"?"dead":supply?"flow":"idle";
    ug([[KX,LY],[KX,9.35]],kerbK); dot([KX,LY],(hoSt==="flow"||kerbK==="flow")?"flow":kerbK);
    if(P.has_factory){ ug([[KX,7.72],[6.9,7.72],[6.9,7.62]],fSt); dot([6.9,7.62],fSt); }
    if(P.civic.length){ const CY=11.62, kOf=ks=>NIGHT?(ks.every(k=>civOn(k))?"flow":ks.some(k=>civOn(k))?"weak":"dead"):"idle";
      const sides=[[P.civic.map((id,k)=>[id,k]).filter(([id])=>CIVIC[id].gx<5),4.87,[4.87,LY]],[P.civic.map((id,k)=>[id,k]).filter(([id])=>CIVIC[id].gx>6),KX,[KX,9.35]]];
      sides.forEach(([list,kx,from])=>{ if(!list.length) return; const lk=kOf(list.map(([,k])=>k)), xs=list.map(([id])=>CIVIC[id].gx+CIVIC[id].w*.85);
        const far=kx<5?Math.min(...xs):Math.max(...xs); ug([from,[kx,CY],[far,CY]],lk); dot([kx,CY],lk);
        list.forEach(([id,k])=>{ const B=CIVIC[id], tx=B.gx+B.w*.85, hk=NIGHT?(civOn(k)?"flow":"dead"):"idle"; ug([[tx,CY],[tx,B.gy+B.d+.02]],hk); }); }); }
    window.__gridCheck={lamps:Object.entries(up).filter(([,v])=>v).map(([k])=>k),overhead:(late.match(/Q/g)||[]).length};
    // keep trees off every buried run
    ugPts.forEach(pts=>{ for(let i=0;i<pts.length-1;i++){ const [a,b]=pts[i], [c2,d]=pts[i+1]; zone(Math.min(a,c2)-.18,Math.min(b,d)-.18,Math.max(a,c2)+.18,Math.max(b,d)+.18); } });
  }

  // ================= props, checked against every building, pole and cable =================
  const tc=[[1.0,10.75],[2.7,10.95],[4.2,11.05],[.35,11.2],[3.3,10.5],[7.1,11.05],[8.4,10.75],[9.25,11.3],[6.6,10.35],[1.8,10.2],[4.6,10.35],[8.0,11.2],[4.55,.4],[4.6,1.8],[4.55,3.25],[6.15,.15],[.2,9.55],[3.5,8.2],[9.0,9.55],[7.0,9.6],[1.1,9.62],[2.9,9.6],[.35,7.6],[4.15,8.0],[6.6,9.75]];
  if(!IND) tc.push([9.8,3.1],[9.62,6.1],[9.62,7.6]);
  if(!IND) tc.push([2.3,9.6],[9.6,9.6],[6.9,8.3],[6.7,6.4],[8.3,7.0]);
  if(VIL) tc.push([7.7,6.2],[7.0,7.35],[8.6,5.6],[6.5,5.5],[8.4,7.9],[6.3,3.3],[7.5,3.4]);
  tc.forEach(([gx,gy])=>place({kind:"tree",gx,gy,r:.26,h:34,samples:TREE_S,svg:()=>tree(gx,gy)}));
  if(!SNOW){ const fl=[[1.6,11.05],[3.6,11.2],[7.6,10.6],[8.9,11.0],[4.3,.9],[4.4,2.6],[3.9,9.2],[1.2,9.3],[4.3,6.2],[2.6,8.3]];
    if(!TOWN) fl.push([6.6,3.7],[8.1,3.6]);
    if(!IND) fl.push([7.2,6.8],[8.0,7.6]);
    if(VIL) fl.push([6.5,7.0],[7.6,5.6],[8.7,6.6]);
    fl.forEach(([gx,gy])=>place({kind:"flowers",gx,gy,r:.12,h:4,samples:[[0,0]],svg:()=>flowers(gx,gy)})); }
  if(LIT) [[6.95,8.5],[8.95,8.65],[8.7,9.85]].forEach(([gx,gy])=>place({kind:"parklamp",gx,gy,r:.05,h:10,samples:[[0,0],[0,-8]],svg:()=>`<circle cx="${X(gx,gy)}" cy="${Y(gx,gy)-8}" r="2.2" fill="${WARMW}"/><ellipse cx="${X(gx,gy)}" cy="${Y(gx,gy)}" rx="14" ry="6" fill="${WARMW}" opacity="${(.2*GL).toFixed(3)}"/>`}));
  if(TOWN&&!LIT){ const ppl=STORM?[[1.2,3.93],[7.2,5.07]]:[[1.2,3.93],[3.0,5.07],[4.93,1.1],[6.07,6.6]].concat(IND&&!SNOW?[[7.4,5.07],[8.6,3.93]]:[]);
    const cols=SNOW?["#c0392b","#2f6fd1","#2e7d4f","#7b3fa0"]:["#3f74c9","#e36742","#5aa53d","#9a5bd6","#f2a33a","#2b2f36"];
    ppl.forEach(([gx,gy],i)=>place({kind:"person",gx,gy,r:.05,h:12,samples:[[0,0],[0,-9]],svg:()=>{ const x=X(gx,gy), y=Y(gx,gy);
      return `<ellipse cx="${x}" cy="${y}" rx="3" ry="1.3" fill="#000" opacity=".2"/><rect x="${x-1.7}" y="${y-7}" width="3.4" height="6.4" rx="1.5" fill="${shade(cols[i%cols.length],1)}"/><circle cx="${x}" cy="${y-8.8}" r="1.8" fill="${shade("#f1c9a5",1)}"/>`+
        (STORM?`<path d="M${x-6} ${y-10.5}Q${x} ${y-17} ${x+6} ${y-10.5}Z" fill="${shade(i?"#3f74c9":"#e36742",1)}"/><line x1="${x}" y1="${y-10.5}" x2="${x}" y2="${y-6}" stroke="#2b2f36" stroke-width=".7"/>`:"")+
        (SNOW?`<rect x="${x-2}" y="${y-7.4}" width="4" height="1.4" fill="${shade("#f2c14e",1)}"/><rect x="${x-1.9}" y="${y-11}" width="3.8" height="1.5" rx=".7" fill="${shade("#ffffff",1)}"/>`:""); }})); }

  // ================= traffic: fixed lanes, one speed, the two roads take turns through the crossing =================
  const vehicle=(kind,col,ax,dir,L)=>{ const Wd=.26, vq=(gx,gy,z)=>`${(X(gx,gy)-X(0,0)).toFixed(1)},${(Y(gx,gy)-z-Y(0,0)).toFixed(1)}`;
    const vb=(a,b,i,z0,z1,top,fr,sd)=>{ const x0=ax==="x"?a:i, y0=ax==="x"?i:a, w=ax==="x"?b-a:Wd-2*i, d=ax==="x"?Wd-2*i:b-a;
      return poly([vq(x0,y0,z1),vq(x0+w,y0,z1),vq(x0+w,y0+d,z1),vq(x0,y0+d,z1)],top)+poly([vq(x0,y0+d,z1),vq(x0+w,y0+d,z1),vq(x0+w,y0+d,z0),vq(x0,y0+d,z0)],fr)+poly([vq(x0+w,y0,z1),vq(x0+w,y0+d,z1),vq(x0+w,y0+d,z0),vq(x0+w,y0,z0)],sd); };
    const sg=(a,b)=>dir>0?[a*L,b*L]:[L-b*L,L-a*L], roof=c=>shade(SNOW?SNOWC:c,1.05), glass=mixc("#bfe6fb","#2b3647",DARK);
    let v=`<ellipse cx="${(X(ax==="x"?L/2:Wd/2,ax==="x"?Wd/2:L/2)-X(0,0)).toFixed(1)}" cy="${(Y(ax==="x"?L/2:Wd/2,ax==="x"?Wd/2:L/2)-Y(0,0)+1).toFixed(1)}" rx="${ax==="x"?16:16}" ry="5" fill="#000" opacity=".16"/>`;
    if(kind==="car"){ v+=vb(0,L,0,0,5.5,roof(col),shade(col,.82),shade(col,.68)); const [a,b]=sg(.2,.7); v+=vb(a,b,.035,5.5,9.5,roof(col),glass,glass); }
    if(kind==="bus"){ v+=vb(0,L,0,0,6,shade(col,1),shade(col,.82),shade(col,.68))+vb(0,L,0,6,9,glass,glass,glass)+vb(0,L,0,9,11,roof(col),shade(col,.82),shade(col,.68)); }
    if(kind==="truck"){ const [a,b]=sg(0,.7), [c1,c2]=sg(.73,1); v+=vb(a,b,0,0,11,roof("#f4f4f4"),shade("#e9ecef",.9),shade("#e9ecef",.75))+vb(c1,c2,.01,0,8,roof("#3f74c9"),shade("#3f74c9",.82),shade("#3f74c9",.68)); }
    if(LIT){ const fx=dir>0?L+.4:-.4, cc=Wd/2, [hx,hy]=ax==="x"?[fx,cc]:[cc,fx]; v+=`<ellipse cx="${(X(hx,hy)-X(0,0)).toFixed(1)}" cy="${(Y(hx,hy)-Y(0,0)).toFixed(1)}" rx="12" ry="5" fill="#fff1b0" opacity="${(.35*GL).toFixed(2)}"/>`; }
    return v; };
  const TC=12, SPD=1.05, LEN={car:.44,bus:.85,truck:.75};
  const fleet=[["x",1,4.12,"car","#e5383b"]];
  if(TOWN) fleet.push(["x",-1,4.62,"car","#5b8ee0"],["y",1,5.12,"car","#f2c14e"],["x",-1,4.62,"bus","#f2c14e"]);
  if(IND) fleet.push(["y",-1,5.62,"car","#7fd6a8"],["x",1,4.12,"truck","#e9ecef"]);
  const WIN={x:[0,TC/2],y:[TC/2,TC]}, nextSlot={}, traffic={x:"",y:""};
  fleet.forEach(([ax,dir,lane,kind,col])=>{ const L=LEN[kind], span=(ax==="x"?NX:NY)-L, D=span/SPD, Z=ax==="x"?[4.9,6.1]:[3.9,5.1];
    // seconds into its run when the body overlaps the crossing box
    const t1=dir>0?(Z[0]-L)/SPD:(span-Z[1])/SPD, t2=dir>0?Z[1]/SPD:(span+L-Z[0])/SPD;
    const key=ax+lane, at=nextSlot[key]??WIN[ax][0]+.3; nextSlot[key]=at+(t2-t1)+.5;
    const o=at-t1, b=(((o%TC)+TC)%TC)-TC, f=D/TC;
    const p0=ax==="x"?(dir>0?[0,lane]:[span,lane]):(dir>0?[lane,0]:[lane,span]), p1=ax==="x"?(dir>0?[span,lane]:[0,lane]):(dir>0?[lane,span]:[lane,0]);
    traffic[ax]+=`<g opacity="0"><g>${vehicle(kind,col,ax,dir,L)}</g><animateMotion dur="${TC}s" begin="${b.toFixed(2)}s" repeatCount="indefinite" calcMode="linear" keyPoints="0;1;1" keyTimes="0;${f.toFixed(4)};1" path="M${X(...p0).toFixed(1)},${Y(...p0).toFixed(1)} L${X(...p1).toFixed(1)},${Y(...p1).toFixed(1)}"/><animate attributeName="opacity" dur="${TC}s" begin="${b.toFixed(2)}s" repeatCount="indefinite" keyTimes="0;${(.4/TC).toFixed(4)};${((D-.4)/TC).toFixed(4)};${f.toFixed(4)};1" values="0;1;1;0;0"/></g>`; });

  // ================= draw: blocks around the two roads, each depth-sorted by footprint, with the traffic between them =================
  const sbox=it=>[X(it.x0,it.y1),Y(it.x0,it.y0)-it.h-2,X(it.x1,it.y0),Y(it.x1,it.y1)];
  const order=list=>{ const bx=list.map(sbox), out=[], st=list.map(()=>0), ov=(p,q)=>p[0]<q[2]&&q[0]<p[2]&&p[1]<q[3]&&q[1]<p[3];
    const idx=list.map((_,i)=>i).sort((i,j)=>(list[i].x0+list[i].y0+list[i].x1+list[i].y1)-(list[j].x0+list[j].y0+list[j].x1+list[j].y1));
    const visit=i=>{ if(st[i]) return; st[i]=1; for(const j of idx) if(j!==i&&!st[j]&&ov(bx[i],bx[j])&&behind(list[j],list[i])) visit(j); st[i]=2; out.push(list[i].svg); };
    idx.forEach(visit); return out.join(""); };
  const blk=it=>{ const n=it.y1<=4.02, so=it.y0>=4.98, w=it.x1<=5.02, e=it.x0>=5.98;
    if(n&&w) return 0; if(n&&e) return 1; if(so&&w) return 2; if(so&&e) return 3;
    const cx=(it.x0+it.x1)/2, cy=(it.y0+it.y1)/2; return cy<4.5?(cx<5.5?0:1):(cx<5.5?2:3); };
  const B=[[],[],[],[]]; items.forEach(it=>B[blk(it)].push(it));
  // north-west block, then the vertical road's traffic, north-east, the horizontal road's traffic, then the two southern blocks
  s+=order(B[0])+traffic.y+order(B[1])+traffic.x+order(B[2])+order(B[3]);
  s+=late;
  // self-check for testing: buildings must never share ground
  const issues=[]; for(let i=0;i<solids.length;i++) for(let j=i+1;j<solids.length;j++){ const a=solids[i], b=solids[j]; if(a.x0<b.x1-.001&&b.x0<a.x1-.001&&a.y0<b.y1-.001&&b.y0<a.y1-.001) issues.push(a.name+" × "+b.name); }
  window.__sceneCheck={ph,tod,issues,props:taken.map(p=>p.kind+"@"+p.gx+","+p.gy),solids:solids.length};

  // ---- weather over everything ----
  const fallLayer=(n,seed,mk,dx,cls,dur)=>{ let l=""; for(let i=0;i<n;i++){ const x=((i*137+seed*53)%1040)-180, y=(i*71+seed*29)%480; l+=mk(x,y)+mk(x-dx,y-480); }
    return `<g class="${cls}" style="animation-duration:${dur}s;${sync(dur)}">${l}</g>`; };
  if(STORM){
    [[60,120,0],[330,250,.9],[520,170,1.7],[150,300,.4],[420,110,1.3],[600,260,2.1]].forEach(([x,y,o])=>s+=`<g transform="translate(${x} ${y})"><path class="windline" d="M0 0q22 -7 44 0t44 0" fill="none" stroke="#e8eef5" stroke-width="1.4" stroke-linecap="round" style="${sync(2.6,o)}"/></g>`);
    [[90,200,.2],[380,150,1.1],[250,320,1.9],[520,230,.7]].forEach(([x,y,o])=>s+=`<g transform="translate(${x} ${y})"><ellipse class="windline" rx="2.6" ry="1.2" fill="#7fa65a" style="${sync(2.6,o)}"/></g>`);
    s+=`<rect x="-80" width="840" height="480" fill="#1b2230" opacity="${(.16*(1-DARK*.6)).toFixed(2)}"/>`;
    s+=fallLayer(140,1,(x,y)=>`<line x1="${x}" y1="${y}" x2="${x-4}" y2="${y+16}"/>`,-110,"rain",.6).replace('<g class="rain"',`<g class="rain" stroke="${NIGHTISH?"#8ea4c2":"#e3ebf5"}" stroke-width="1.1" opacity="${NIGHTISH?.4:.55}"`);
    s+=fallLayer(90,7,(x,y)=>`<line x1="${x}" y1="${y}" x2="${x-2.5}" y2="${y+10}"/>`,-110,"rain",.85).replace('<g class="rain"',`<g class="rain" stroke="${NIGHTISH?"#7b90ad":"#cfd9e6"}" stroke-width=".8" opacity="${NIGHTISH?.3:.4}"`);
    s+=`<polyline class="bolt" points="150,18 136,54 150,54 130,98 146,98 128,140" fill="none" stroke="#fff6c8" stroke-width="2.6" stroke-linejoin="round" style="animation-duration:4.5s;${sync(4.5)}"/><rect class="flash" x="-80" width="840" height="480" fill="#dfe8ff" style="animation-duration:4.5s;${sync(4.5)}"/>`;
    if(GROW===ph) s+=`<rect class="flash1" x="-80" width="840" height="480" fill="#eef3ff"/>`; }
  if(SNOW){
    s+=fallLayer(70,3,(x,y)=>`<circle cx="${x}" cy="${y}" r="${1.3+(x%3)*.4}"/>`,-40,"snowf",9).replace('<g class="snowf"','<g class="snowf" fill="#ffffff" opacity=".9"');
    s+=fallLayer(50,11,(x,y)=>`<circle cx="${x}" cy="${y}" r=".9"/>`,-40,"snowf",14).replace('<g class="snowf"','<g class="snowf" fill="#ffffff" opacity=".6"'); }
  return s;
}
function drawPlan(){
  const P=PHASES[G.phase]; scene(G.phase,{city:G.city,tod:"day",energy:{mode:"plan"},ghost:live()&&G.state==="plan"?G.build:null});
  $("m-hour").textContent="Day"; $("m-bat").textContent=`cap ${G.city.capacity}`; $("m-batbar").style.width="0%"; $("m-app").textContent="100%"; $("m-appbar").style.width="100%"; $("m-appbar").style.background="var(--ok)";
}
function drawNight(ph,a,h){
  const hs=V(a,"hours")||[], hr=hs[h]; if(!hr) return;
  const P=PHASES[ph], cap=(V(a,"city_next")||{}).capacity||1, dusk=V(a,"dusk_battery");
  // energy picture of this hour, straight from aityx: battery before and after the hour, who lost power since the last hour, what the rules wanted on
  const energy={mode:"night",h,dusk,before:h===0?dusk:hs[h-1].battery,after:hr.battery,prevLit:h===0?P.houses:hs[h-1].houses_lit,lightsWanted:!!V(a,`h${h+1}_lights_wanted`),facWanted:!!V(a,"factory_at_night")};
  $("m-bat").textContent=Math.round(hr.battery); $("m-batbar").style.width=Math.max(0,Math.min(100,hr.battery/cap*100))+"%";
  const app=Math.round(hr.approval);
  $("m-app").textContent=app+"%"; $("m-appbar").style.width=app+"%"; $("m-appbar").style.background=app>=90?"var(--ok)":app>=50?"var(--sun)":"var(--bad)";
  scene(ph,{city:V(a,"city_next")||G.city,tod:h,lit:hr.houses_lit,lights:hr.lights_on,hosp:hr.hospital_on,fac:hr.factory_on,battery:hr.battery,energy},t=>{
    // the clock reads "Dusk" during the sunset that leads into 8 PM, then the step's own time
    if(t==="dusk"){ $("m-hour").textContent="Dusk"; setBanner("night","Dusk · night is falling"); return; }
    $("m-hour").textContent=HOURS[h];
    setBanner(P.has_hospital&&!hr.hospital_on?"out":"night",`${HOURS[h]} · ${hr.houses_lit} of ${P.houses} ${P.civic.length?"homes & buildings":"houses"} lit${P.has_hospital?(hr.hospital_on?" · hospital on":" · HOSPITAL DARK"):""}`);
  });
}
function drawMorning(ph,a){
  // after the last night step: daylight returns; meters keep the night's final numbers from aityx
  const hrs=V(a,"hours")||[], hr=hrs[hrs.length-1]; if(!hr) return;
  scene(ph,{city:V(a,"city_next")||G.city,tod:"morning",lit:hr.houses_lit,lights:false,hosp:hr.hospital_on,fac:hr.factory_on,battery:hr.battery,energy:{mode:"morning",after:hr.battery,dusk:V(a,"dusk_battery")}});
  $("m-hour").textContent="Morning";
}
function renderReceipt(a){
  // results first, then the receipts grouped; every value below is read from aityx's answer, nothing is computed here
  const P=PHASES[G.phase], hs=V(a,"hours")||[], last=hs[hs.length-1]||{}, cap=(V(a,"city_next")||{}).capacity;
  const ok=V(a,"passed"), st=V(a,"stars")||0, app=Math.round(V(a,"approval")), dusk=V(a,"dusk_battery");
  const tile=(lab,val,sub,cls="",wide)=>`<div class="tile ${cls}${wide?" wide":""}"><span>${lab}</span><b>${val}</b>${sub?`<small>${sub}</small>`:""}</div>`;
  const yes=v=>v===true||v===1;
  let h=`<div class="whyhead"><b>Night ${G.phase+1} · ${esc(P.name)}</b><span>${live()?"live · aityx":"recorded aityx game"}</span></div><div class="tiles">`;
  h+=tile("Outcome",ok?`<span class="stars" style="font-size:15px">${"★".repeat(st)}${"☆".repeat(3-st)}</span> Passed`:"Lost",ok?"":(yes(V(a,"hospital_failed"))?"The hospital went dark.":"Approval fell below the bar."),ok?"good":"bad");
  h+=tile("Approval at dawn",`${app}%`,"Needs 50% to pass, 90% for three stars",app>=90?"good":app>=50?"warn":"bad");
  h+=tile("Battery",`${Math.round(dusk)} → ${Math.round(last.battery)}`,`At dusk → left at 6 AM, of ${Math.round(cap)} capacity`,last.battery===0?"bad":"");
  h+=tile(P.civic.length?"Homes & buildings lit at 6 AM":"Houses lit at 6 AM",`${last.houses_lit} of ${P.houses}`,`${V(a,"dark_house_hours")} house-hours in the dark`,last.houses_lit>=P.houses?"good":last.houses_lit>0?"warn":"bad");
  if(P.has_hospital) h+=tile("Hospital",yes(V(a,"hospital_failed"))?"Went dark":"On all night","",yes(V(a,"hospital_failed"))?"bad":"good");
  if(P.has_factory) h+=tile("Factory",yes(V(a,"factory_at_night"))?`${V(a,"factory_hours")??0} of 6 hours`:"Off by your rule",yes(V(a,"factory_at_night"))?`+${(V(a,"factory_hours")||0)*5} storage`:"",(V(a,"factory_hours")||0)>0?"good":"");
  else h+=tile("Streetlights",`${V(a,"dark_light_hours")} dark hour${V(a,"dark_light_hours")===1?"":"s"}`,"when they should have been on",V(a,"dark_light_hours")?"warn":"good");
  h+=`</div><div class="rulechips"><div>Off first: <b>${esc(V(a,"off_first")||"")}</b></div><div>Streetlights off after midnight: <b>${yes(V(a,"lights_off_after_midnight"))?"yes":"no"}</b></div>${P.has_factory?`<div>Factory at night: <b>${yes(V(a,"factory_at_night"))?"on":"off"}</b></div>`:""}</div>`;
  const lines=V(a,"lines")||[], fmt=l=>/Hospital/.test(l.label)?(l.value?"on":"dark"):/Approval/.test(l.label)?Math.round(l.value)+"%":/Factory/.test(l.label)?(l.value?"yes":"no"):Math.round(l.value*10)/10;
  const grp=[["Energy",/Battery|Wind/],["The city",/House|Streetlight|Factory|Hospital/],["Result",/Approval/]];
  const used=new Set();
  grp.forEach(([g,re])=>{ const ls=lines.filter((l,i)=>!used.has(i)&&re.test(l.label)&&used.add(i)); if(!ls.length) return;
    h+=`<div class="rgroup"><div class="mono">${g}</div><div class="receipt">${ls.map(l=>`<div class="rline"><span><span class="src">rule</span>${esc(l.label)}</span><span class="v">${fmt(l)}</span><span class="why">${esc(l.why)}</span></div>`).join("")}</div></div>`; });
  const rest=lines.filter((l,i)=>!used.has(i)); if(rest.length) h+=`<div class="rgroup"><div class="mono">More</div><div class="receipt">${rest.map(l=>`<div class="rline"><span><span class="src">rule</span>${esc(l.label)}</span><span class="v">${fmt(l)}</span><span class="why">${esc(l.why)}</span></div>`).join("")}</div></div>`;
  h+=`<details class="hours"><summary>Hour by hour <span class="note">what aityx answered for each step</span></summary><div class="inner" style="overflow-x:auto"><table class="htab"><tr><th>Time</th><th>Battery</th><th>Houses</th><th>Lights</th>${P.has_hospital?"<th>Hospital</th>":""}${P.has_factory?"<th>Factory</th>":""}<th>Approval</th></tr>`+
    hs.map((r,i)=>`<tr><td>${HOURS[i]}</td><td>${Math.round(r.battery)}</td><td class="${r.houses_lit<P.houses?"off":""}">${r.houses_lit}/${P.houses}</td><td class="${r.lights_on?"on":"off"}">${r.lights_on?"on":"off"}</td>${P.has_hospital?`<td class="${r.hospital_on?"on":"off"}">${r.hospital_on?"on":"dark"}</td>`:""}${P.has_factory?`<td>${r.factory_on?"on":"off"}</td>`:""}<td>${Math.round(r.approval)}%</td></tr>`).join("")+`</table></div></details>`;
  $("receipt").innerHTML=h;
}
const JHOT=new Set(["answers","passed","stars","approval","dusk_battery","hours","lines","city_next","hospital_failed","factory_all_night","dark_house_hours","dark_light_hours","decision_error","state","build","panels","capacity","turbines","houses","sun","wind","phase"]);
const JOPEN=new Set(["$","$.answers","$.state"]);
function jv(v,path,key){
  // syntax-coloured, collapsible JSON; small objects stay on one line; highlighted keys are the ones the city is drawn from
  if(v===null) return `<span class="jz">null</span>`;
  if(typeof v==="string") return `<span class="js">"${esc(v)}"</span>`;
  if(typeof v==="number") return `<span class="jn">${v}</span>`;
  if(typeof v==="boolean") return `<span class="jb">${v}</span>`;
  const arr=Array.isArray(v), ent=arr?v.map((x,i)=>[i,x]):Object.entries(v), o=arr?"[":"{", c=arr?"]":"}";
  if(!ent.length) return `<span class="jz">${o}${c}</span>`;
  if(ent.length<=4&&ent.every(([,x])=>x===null||typeof x!=="object")) return `${o} `+ent.map(([k,x])=>(arr?"":`<span class="jk">"${esc(k)}"</span>: `)+jv(x)).join(", ")+` ${c}`;
  const open=JOPEN.has(path), row=([k,x])=>`<div class="jr${!arr&&JHOT.has(k)?" hot":""}">${arr?"":`<span class="jk">"${esc(k)}"</span>: `}${jv(x,path+"."+k,k)}</div>`;
  let body;
  if(path==="$.answers"){ // the answers the city is drawn from first; the input echoes and per-hour steps folded into one group
    const hot=ent.filter(([k])=>JHOT.has(k)), rest=ent.filter(([k])=>!JHOT.has(k));
    body=hot.map(row).join("")+(rest.length?`<details class="jmore"><summary><span class="jz">… ${rest.length} more answers (inputs echoed back and each hour's steps)</span></summary><div>${rest.map(row).join("")}</div></details>`:""); }
  else body=ent.map(row).join("");
  return `<details${open?" open":""}><summary>${o}<span class="jcount"> ${ent.length} ${arr?"items":"keys"} ${c}</span></summary><div class="jvb2">${body}</div>${c}</details>`;
}
const JRAW={};
function showCall(req,res,status){
  JRAW.req=req; JRAW.res=res;
  $("req").innerHTML=`<div class="jc">// POST ${esc(endpoint())}</div><div class="jc">// ${LIVE.conn&&LIVE.conn.source==="dev"?"no Authorization: the index server adds its dev key":"Authorization: Bearer aityx_sk_… (your key is never shown)"}</div>`+jv(req,"$");
  $("res").innerHTML=`<div class="jc">// HTTP ${status}</div>`+(res==null?`<span class="jc">// no JSON body</span>`:jv(res,"$"));
}
document.addEventListener("click",async e=>{ const b=e.target.closest(".jvb"); if(!b) return; const box=$(b.dataset.jv);
  if(b.dataset.act==="open") box.querySelectorAll("details").forEach(d=>d.open=true);
  if(b.dataset.act==="close") box.querySelectorAll("details").forEach((d,i)=>d.open=i===0||(b.dataset.jv==="res"&&d.parentElement&&d.parentElement.closest("details")===box.querySelector("details")&&d.previousElementSibling&&/answers/.test(d.previousElementSibling.textContent)));
  if(b.dataset.act==="copy"&&JRAW[b.dataset.jv]!=null){ try{ await navigator.clipboard.writeText(JSON.stringify(JRAW[b.dataset.jv],null,2)); b.textContent="Copied ✓"; }catch(_){ b.textContent="Copy failed"; } setTimeout(()=>b.textContent="Copy",1600); } });
function note(t,cls){ const n=$("live"); n.className="note"+(cls?" "+cls:""); n.textContent=t; }
function ui(){
  const L=live(), P=PHASES[G.phase], plan=G.state==="plan"&&!G.busy;
  const cs=CONN.state, [short,long]=CONN_TEXT[cs];
  document.body.dataset.conn=cs; $("mode").dataset.conn=cs; $("mode").querySelector("span").textContent=short; $("mode").title=long;
  $("conndot").dataset.conn=cs; $("conndot").setAttribute("aria-label",short);
  $("connstat").dataset.conn=cs; $("connmsg").textContent=CONN.msg||long; $("connretry").hidden=cs==="checking"||cs==="ok";
  const lt=$("aityx-light"), tip={ok:"aityx: ready — the key works"+(LIVE.conn&&LIVE.conn.url?" with "+LIVE.conn.url:""),none:"aityx: no key — set yours on the index page",checking:"aityx: checking the key",invalid:"aityx: key rejected — "+(CONN.msg||long),error:"aityx: not reachable — "+(CONN.msg||long)}[cs];
  lt.dataset.conn=cs; lt.title=tip; lt.setAttribute("aria-label",tip);
  $("setkey").textContent=L?"Change key":"Set your aityx key";
  $("api-where").textContent=!LIVE.conn?"Calls go to aityx once a key is set on the demos page.":LIVE.conn.source==="dev"?`Calls go through the index server's dev proxy (${LIVE.conn.whose}${LIVE.conn.url?", "+LIVE.conn.url:""}).`:`Calls go to ${LIVE.conn.systemone}, with the key set on the demos page.`;
  $("recall").hidden=!(L&&REC_MODE);
  { const n=RUNORDER.filter(k=>!REC[k]||REC[k].rv!==RULES_V).length; $("recall").textContent=n?`Record ${n} new game${n===1?"":"s"}`:"Re-record all games"; }
  document.body.classList.toggle("locked",!L);
  $("liveplay").hidden=!L; $("replayplay").hidden=L;
  const survived=G.stars.filter(x=>x!=null).length, recent=G.stars.map((x,i)=>[x,i]).filter(([x])=>x!=null).slice(-6);
  $("phases").innerHTML=`<div class="ncount"><span>NIGHT</span><b>${G.phase+1}</b></div><div class="ninfo"><b>${esc(P.name)}</b><span>${L?`Survived ${survived} · Best ${Math.max(bestNights,survived)}`:`Survived ${survived} · recorded game`}</span></div><div class="nstars" aria-label="Stars per night">${recent.map(([x,i])=>`<span title="Night ${i+1}">${"★".repeat(x)}${"☆".repeat(3-x)}</span>`).join("")}</div>`;
  $("ph-label").textContent=`Night ${G.phase+1}`; $("ph-title").textContent=P.name; $("ph-text").textContent=P.text;
  $("facts").innerHTML=(P.civic.length?[["Homes",P.homes],["Buildings",P.civic.length]]:[["Houses",P.houses]]).concat([["Sunlight",`${P.sun}/10`],["Wind",P.wind.join(" ")],["Panels",G.city.panels],["Battery",G.city.capacity],["Turbines",G.city.turbines]]).map(([l,v])=>`<div class="fact">${l} <b>${esc(v)}</b></div>`).join("");
  const BICON={panel:'<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 15l4-9h14l-4 9z" fill="#2f6fd1" stroke="#cfe6ff" stroke-width="1.2"/><path d="M10 6l-4 9M15 6l-4 9M5 10.5h14" stroke="#cfe6ff" stroke-width=".9"/><path d="M12 15v5M8 20h8" stroke="#8d96a1" stroke-width="1.6"/></svg>',
    battery:'<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="6" width="14" height="13" rx="2" fill="#4f8a5b"/><rect x="18" y="10" width="2.5" height="5" rx="1" fill="#c9ced6"/><rect x="6.5" y="9" width="9" height="7" rx="1" fill="#5fd38a"/></svg>',
    turbine:'<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M11.4 22l.4-12h.4l.4 12z" fill="#e8eef3"/><g fill="#e8eef3"><path d="M12 10L12.8 2h-1.6z"/><path d="M12 10l7 3.8-.8 1.4z"/><path d="M12 10l-7 3.8.8 1.4z"/></g><circle cx="12" cy="10" r="1.6" fill="#e8662f"/></svg>'};
  $("buildbar").hidden=!(L&&G.state==="plan");
  $("buildbar").innerHTML=`<span class="bblab">Day ${G.phase+1}<br>build one</span>`+Object.entries(BUILDS).map(([k,b])=>`<button class="bbtn" type="button" data-build="${k}" aria-pressed="${G.build===k}" ${plan?"":"disabled"} title="${esc(b.what)}">${BICON[k]}<span><b>${b.name}</b><small>${b.what}</small></span></button>`).join("")+`<button class="button primary bbgo" type="button" data-go ${plan?"":"disabled"}>${G.busy?"aityx is running…":"Start the night ▸"}</button>`;
  $("builds").innerHTML=Object.entries(BUILDS).map(([k,b])=>`<button class="build" type="button" data-build="${k}" aria-pressed="${G.build===k}" ${plan?"":"disabled"}><b>${b.name}</b><span>${b.what}</span></button>`).join("");
  const items=G.rules.order.filter(i=>i!=="factory"||P.has_factory);
  $("order").innerHTML=items.map((it,i)=>`<div class="oi"><span class="n">${i+1}</span><span class="t">${ITEMS[it]}</span><button class="button" type="button" data-up="${it}" aria-label="Move ${ITEMS[it]} up" ${!plan||i===0?"disabled":""}>↑</button><button class="button" type="button" data-down="${it}" aria-label="Move ${ITEMS[it]} down" ${!plan||i===items.length-1?"disabled":""}>↓</button></div>`).join("")+
    (P.has_hospital?`<div class="oi locked"><span class="n">🔒</span><span class="t">Hospital never goes dark (served first)</span></div>`:"");
  $("t-lights").checked=G.rules.lightsMidnight; $("t-lights").disabled=!plan;
  $("t-fac").checked=G.rules.factoryNight; $("t-fac").disabled=!plan; $("t-fac-row").hidden=!P.has_factory;
  $("go").hidden=G.state!=="plan"; $("go").disabled=G.busy; $("go").textContent=G.busy?"aityx is running…":"Start the night";
  $("next").hidden=G.state!=="night"||!G.timer;
  $("cont").hidden=true; $("retry").hidden=true;   // no last night, and a lost night ends the run
  $("restart").classList.toggle("primary",G.state==="lost"); $("restart").classList.toggle("ghost",G.state!=="lost"); $("restart").textContent=G.state==="lost"?"Play again":"Start over";
  $("retry").textContent=G.state==="won"?"↺ Replay this night for more stars":"↺ Try this night again";
  ["s1","s2"].forEach(id=>$(id).classList.toggle("active",plan)); $("s3").classList.toggle("active",G.state!=="plan"||plan);
  const runEnd=r=>{ const ns=r.nights.map(x=>x.res.answers), last=ns[ns.length-1]; return {ns,n:ns.length,last,lived:last&&!V(last,"passed")?ns.length-1:ns.length}; };
  $("runs").innerHTML=RUNORDER.filter(k=>REC[k]).map(k=>{ const {lived}=runEnd(REC[k]);
    return `<button class="runcard" type="button" data-run="${k}" aria-pressed="${RP.run===k}"><b>${esc(RUNTITLE[k]||REC[k].label)}</b><span class="rc-res"><strong>${lived}</strong>night${lived===1?"":"s"}</span></button>`; }).join("")||`<span class="note">No recorded games yet. Set your aityx key on the demos page to play live.</span>`;
  { const r=REC[RP.run]; if(!r){ $("rundetail").innerHTML=""; } else {
    const {ns,n,last}=runEnd(r), ev=[], nights=f=>ns.map((a,i)=>f(a,i)?i+1:0).filter(Boolean);
    const s3=ns.findIndex(a=>V(a,"stars")!==3), streak=s3<0?n:s3; if(streak>=2) ev.push(`★★★ on nights 1 to ${streak}`);
    const fh=nights(a=>V(a,"factory_hours")>0); if(fh.length) ev.push(`The factory adds battery storage on night${fh.length>1?"s":""} ${fh.length>1?fh.slice(0,-1).join(", ")+" and "+fh[fh.length-1]:fh[0]}`);
    const ld=nights(a=>V(a,"dark_light_hours")>0); if(ld.length) ev.push(`Streetlights go dark on night ${ld[0]}`);
    if(last&&!V(last,"passed")) ev.push(V(last,"hospital_failed")?`Night ${n}: the hospital goes dark`:`Night ${n}: the hospital holds, but homes go dark (approval ${Math.round(V(last,"approval"))}%)`);
    else ev.push(`Still standing after ${n} nights`);
    $("rundetail").innerHTML=`${esc(RUNINFO[RP.run]||"")}<ul>${ev.map(e=>`<li>${esc(e)}</li>`).join("")}</ul>`; } }
  $("play").disabled=!RP.run; $("rnext").disabled=!RP.run; $("play").textContent=RP.timer?"Ⅱ Pause":"▶ Play";
}

function gameOver(n,endOfRecording){
  const d=$("win"); if(d.open) return;
  const rec=live()&&!endOfRecording&&n>bestNights; if(rec){ bestNights=n; try{localStorage.setItem("outpost.nights.survived",bestNights);}catch(_){} }
  $("win-kicker").textContent=endOfRecording?"END OF THE RECORDING":"THE CITY WENT DARK";
  $("win-title").textContent=endOfRecording?`Still standing after ${n} night${n===1?"":"s"}.`:`The city survived ${n} night${n===1?"":"s"}.`;
  $("win-score").textContent=n;
  $("win-stars").textContent=G.stars.filter(x=>x!=null).map(x=>"★".repeat(x)+"☆".repeat(3-x)).join(" ");
  $("win-per").hidden=true; $("win-rec").hidden=!rec;
  $("win-text").textContent=!live()?(endOfRecording?"This recorded aityx game stops here. Set your aityx key and see how far your own city gets.":"That was a real game recorded on aityx. Set your aityx key and see if your city lasts longer."):`Every night ran on aityx with your rules. ${rec?"A new record.":`Your best: ${bestNights} night${bestNights===1?"":"s"}.`} Build differently and try again.`;
  $("win-again").textContent=!live()?"Set your aityx key to play":"Play again";
  $("win-share").hidden=!live();
  const c=$("confetti"); c.innerHTML=rec||n>=10?Array.from({length:40},(_,i)=>`<i style="left:${(i*37)%100}%;background:${["#f2c14e","#e36742","#a6d6b7","#9ab3eb"][i%4]};animation-delay:${(i%10)*.12}s"></i>`).join(""):"";
  $("win").querySelector(".lamp").textContent=endOfRecording||rec?"💡":"🌙";
  d.showModal();
}
$("win-again").onclick=()=>{ $("win").close(); if(!live()){ openKey(); return; } clearInterval(G.timer); newGame(); drawPlan(); setBanner("",""); $("result").textContent=""; note("New city. How many nights can it last?"); ui(); showTab("play"); };
$("win-share").onclick=async()=>{ const n=G.stars.filter(x=>x!=null).length, t=`My city kept its lights on for ${n} night${n===1?"":"s"} on OUTPOST, an aityx demo.`;
  try{ await navigator.clipboard.writeText(t); $("win-share").textContent="Copied ✓"; }catch(_){ $("win-share").textContent=t; } };
$("win-close").onclick=()=>{ $("win").close(); showTab("why"); };

/* ---------- events ---------- */
$("setkey").onclick=e=>{ e.preventDefault(); openKey(); };
$("keybtn").onclick=openKey;   // the header button (and the "Set your aityx key to play" buttons, through it)
$("aityx-light").onclick=openKey;
$("connretry").onclick=()=>checkKey();
// the demos page (another tab) saved or forgot the key: check again at once
addEventListener("storage",e=>{ if(e.key===null||e.key==="aityx.key"||e.key==="aityx.url") checkKey(); });
// back to this tab: check again, at most once every 30 s (each check spends a request of the user's quota)
addEventListener("focus",()=>{ if(Date.now()-lastCheck>30000) checkKey(); });
$("recall").onclick=recordAll;
$("go").onclick=()=>{ G.start={...G.city}; startNight(); };
$("next").onclick=()=>{ clearInterval(G.timer); tick(); if(G.state==="night") G.timer=setInterval(tick,2000); };
function nextDay(){ if(G.state!=="won") return; clearTimeout(nextDay.t); G.phase++; ensurePhase(G.phase); G.state="plan"; G.a=null; G.build="panel"; setBanner("",""); drawPlan(); note(`Day ${G.phase+1}. Build one thing and check your night rules, then press Start the night.`); ui(); }
$("cont").onclick=nextDay;
$("retry").onclick=()=>{ G.city={...G.start}; G.state="plan"; G.a=null; $("result").textContent=""; setBanner("",""); drawPlan(); note("Same night again. Change your build or your rules."); ui(); };
$("restart").onclick=()=>{ clearInterval(G.timer); newGame(); drawPlan(); setBanner("",""); $("result").textContent=""; note("New city. How many nights can it last?"); ui(); };
$("t-lights").onchange=e=>{ G.rules.lightsMidnight=e.target.checked; };
$("t-fac").onchange=e=>{ G.rules.factoryNight=e.target.checked; };
$("play").onclick=()=>{ if(RP.timer){ stopReplay(); return; } const run=REC[RP.run]; if(!run) return; if(RP.phase>=run.nights.length||(RP.phase===run.nights.length-1&&G.state!=="night"&&G.state!=="plan")) resetReplay(RP.run);
  if(rTick()) RP.timer=setInterval(()=>{ if(!rTick()) stopReplay(); },2800); ui(); };   // slower than live (2 s) so a visitor can follow the night
$("rnext").onclick=()=>{ stopReplay(); RP.hold=0; RP.picked=true; rTick(); };
document.addEventListener("click",e=>{ const b=e.target.closest("button"); if(!b||b.disabled) return;
  if(b.dataset.go!==undefined&&b.closest("#buildbar")){ $("go").click(); return; }
  if(b.dataset.build){ G.build=b.dataset.build; ui(); if(G.state==="plan"&&live()) drawPlan(); }
  if(b.dataset.up||b.dataset.down){ const o=G.rules.order, it=b.dataset.up||b.dataset.down, P=PHASES[G.phase];
    const vis=o.filter(i=>i!=="factory"||P.has_factory), i=vis.indexOf(it), j=b.dataset.up?i-1:i+1; if(j<0||j>=vis.length) return;
    [vis[i],vis[j]]=[vis[j],vis[i]]; G.rules.order=P.has_factory?vis:[...vis.slice(0,0),...vis,"factory"].filter((x,k,arr)=>arr.indexOf(x)===k); ui(); }
  if(b.dataset.run) resetReplay(b.dataset.run); });

drawPlan(); ui();
if(!live()) note(Object.keys(REC).length?"Pick a recorded game and press Play. Every night you see is a real aityx call.":"No recorded games yet. Set your aityx key on the demos page to play live.");
checkKey();
})();

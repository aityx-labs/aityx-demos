/* App shell only: tabs, how-to overlay, receipt dot. No game logic here. */
(()=>{
const q=s=>document.querySelector(s), qa=s=>[...document.querySelectorAll(s)];
const tabs=qa(".tab");
window.showTab=name=>{
  tabs.forEach(t=>{ const on=t.dataset.tab===name; t.setAttribute("aria-selected",on); t.tabIndex=on?0:-1; if(on) t.classList.remove("dot"); });
  qa(".pane").forEach(p=>p.hidden=p.id!=="pane-"+name);
};
document.addEventListener("click",e=>{ const b=e.target.closest("[data-tab]"); if(b) showTab(b.dataset.tab); });
q(".tabs").addEventListener("keydown",e=>{
  const i=tabs.indexOf(document.activeElement); if(i<0) return;
  const j=e.key==="ArrowRight"?(i+1)%tabs.length:e.key==="ArrowLeft"?(i+tabs.length-1)%tabs.length:e.key==="Home"?0:e.key==="End"?tabs.length-1:-1;
  if(j<0) return; e.preventDefault(); tabs[j].focus(); showTab(tabs[j].dataset.tab);
});
// a new receipt lands while another tab is open: mark the Why tab
new MutationObserver(()=>{ const t=q("#tab-why"); if(t.getAttribute("aria-selected")!=="true") t.classList.add("dot"); }).observe(q("#receipt"),{childList:true});
// how to play
const how=q("#howto");
const closeHow=()=>{ how.hidden=true; try{ localStorage.setItem("outpost.howto.seen","1"); }catch(_){} };
q("#howto-open").onclick=()=>{ how.hidden=false; q("#howto-go").focus(); };
q("#howto-go").onclick=closeHow;
how.addEventListener("click",e=>{ if(e.target===how) closeHow(); });
document.addEventListener("keydown",e=>{ if(e.key==="Escape"&&!how.hidden) closeHow(); });
how.hidden=false; q("#howto-go").focus();   // always the first thing a visitor sees
// header "Set your key" and [data-keycta]: outpost.js puts the cursor in the key form (no key yet) or opens the demos page's key section
q("#mapkey").onclick=()=>{ const p=q("#mapkeypop"), b=q("#mapkey"); p.hidden=!p.hidden; b.setAttribute("aria-expanded",!p.hidden); };
document.addEventListener("click",e=>{ if(e.target.closest("[data-keycta]")) q("#keybtn").onclick(); });
// zoom and pan the city (the view only; nothing in the game changes)
(()=>{ const sv=q("#scene"), V0=[-80,0,840,480]; let z=1, cx=V0[0]+V0[2]/2, cy=V0[1]+V0[3]/2, drag=null;
  const apply=()=>{ const w=V0[2]/z, h=V0[3]/z; cx=Math.min(Math.max(cx,V0[0]+w/2),V0[0]+V0[2]-w/2); cy=Math.min(Math.max(cy,V0[1]+h/2),V0[1]+V0[3]-h/2);
    sv.setAttribute("viewBox",`${(cx-w/2).toFixed(1)} ${(cy-h/2).toFixed(1)} ${w.toFixed(1)} ${h.toFixed(1)}`); sv.classList.toggle("zoomed",z>1.01);
    q("#zin").disabled=z>=3.99; q("#zout").disabled=z<=1.01; q("#zfit").disabled=z<=1.01; };
  const toSvg=(e)=>{ const r=sv.getBoundingClientRect(), w=V0[2]/z, h=V0[3]/z, k=Math.min(r.width/w,r.height/h), ox=r.left+(r.width-w*k)/2, oy=r.top+(r.height-h*k)/2; return [cx-w/2+(e.clientX-ox)/k, cy-h/2+(e.clientY-oy)/k, k]; };
  const zoomAt=(f,px,py)=>{ const nz=Math.min(4,Math.max(1,z*f)); if(px!=null){ cx=px-(px-cx)*z/nz; cy=py-(py-cy)*z/nz; } z=nz; apply(); };
  q("#zin").onclick=()=>zoomAt(1.4); q("#zout").onclick=()=>zoomAt(1/1.4); q("#zfit").onclick=()=>{ z=1; apply(); };
  sv.addEventListener("wheel",e=>{ e.preventDefault(); const [px,py]=toSvg(e); zoomAt(e.deltaY<0?1.15:1/1.15,px,py); },{passive:false});
  sv.addEventListener("pointerdown",e=>{ if(z<=1.01) return; const [,,k]=toSvg(e); drag={x:e.clientX,y:e.clientY,cx,cy,k}; sv.setPointerCapture(e.pointerId); sv.classList.add("dragging"); });
  sv.addEventListener("pointermove",e=>{ if(!drag) return; cx=drag.cx-(e.clientX-drag.x)/drag.k; cy=drag.cy-(e.clientY-drag.y)/drag.k; apply(); });
  const end=()=>{ drag=null; sv.classList.remove("dragging"); }; sv.addEventListener("pointerup",end); sv.addEventListener("pointercancel",end);
  apply(); })();
})();

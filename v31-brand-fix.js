/* V35 public shell/branding fix — prevents legacy V31/V29/V26 labels from surviving in the root app shell */
(()=>{'use strict';
function fix(){
 document.title='HOS 150 Driver Companion V35';
 const m=document.querySelector('meta[name="app-version"]');if(m)m.content='35.0';
 const b=document.querySelector('meta[name="build-id"]');if(b)b.content='2026-09-10-v35.0';
 const s=document.querySelector('header small');if(s)s.textContent='V35 • TRUCK NAVIGATION • HOS • 150 AIR-MILE • GPS • ROUTE INTEL';
 const h=document.querySelector('header b');if(h)h.textContent='🚛 HOS 150 DRIVER COMPANION';
 const walk=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT);const nodes=[];while(walk.nextNode())nodes.push(walk.currentNode);
 nodes.forEach(n=>{if(!n.nodeValue)return;n.nodeValue=n.nodeValue.replace(/V31(?:\.2)?/g,'V35').replace(/V29/g,'V35').replace(/V26/g,'V35').replace(/v31(?:\.2)?/gi,'v35').replace(/v29/gi,'v35').replace(/v26/gi,'v35')});
 const old=document.querySelector('script[src*="v31-brand-fix"]');if(old)old.setAttribute('data-loaded','1');
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',fix,{once:true});else fix();
setTimeout(fix,300);setTimeout(fix,1200);
})();

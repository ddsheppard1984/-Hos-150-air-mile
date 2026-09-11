(()=>{'use strict';
const KEY='hos150v13', $=id=>document.getElementById(id);
const startOfToday=()=>{const d=new Date();d.setHours(0,0,0,0);return d.getTime()};
const load=()=>{try{return JSON.parse(localStorage.getItem(KEY)||'{}')}catch{return{}}};
const save=s=>localStorage.setItem(KEY,JSON.stringify(s));
function resetToday(){
 const s=load(), now=Date.now(), midnight=startOfToday();
 const driveBefore=(s.segments||[]).filter(x=>x.status==='DRIVING'&&x.end>midnight&&x.start<now).reduce((n,x)=>n+Math.max(0,Math.min(x.end,now)-Math.max(x.start,midnight)),0)+(s.status==='DRIVING'&&s.currentStart>=midnight?now-s.currentStart:0);
 const oldStatus=s.status||'OFF DUTY';
 const oldStart=s.currentStart||midnight;
 const kept=[];
 for(const x of (s.segments||[])){
   if(x.end<=midnight) kept.push(x);
   else if(x.start<midnight) kept.push({...x,end:midnight});
 }
 s.segments=kept;
 s.status='OFF DUTY';
 s.currentStart=midnight;
 s.shiftStart=null;
 s._stopPrompted=false;
 s.events=s.events||[];
 s.events.unshift({time:new Date(now).toISOString(),status:'OFF DUTY',source:'DRIVER EDIT',note:`RESET TODAY — driver correction. Previous status: ${oldStatus}. Previous current period began ${new Date(oldStart).toLocaleString()}. Driving time removed from today's prototype clocks: ${Math.floor(driveBefore/3600000)}h ${Math.floor(driveBefore/60000)%60}m. Verify and correct records as required.`,loc:s.pos?`${s.pos.lat.toFixed(5)},${s.pos.lon.toFixed(5)}`:'GPS unavailable'});
 s.events=s.events.slice(0,1000);
 save(s);
 window.dispatchEvent(new Event('hos150:state-updated'));
 if(typeof window.render==='function')window.render();
 alert('Today\'s prototype HOS timers have been reset. The reset was recorded in the Event Audit Trail as DRIVER EDIT. Verify your actual duty status/ELD record before relying on the clocks.');
}
function add(){
 if($('resetTodayV35'))return;
 const host=$('log')?.querySelector('.card')||$('settings');
 if(!host)return;
 const c=document.createElement('div');c.id='resetTodayV35';c.className='card';c.style.cssText='margin-top:12px;border:2px solid #b45309';
 c.innerHTML='<h3>🔄 Reset Today\'s HOS Timers</h3><p class="muted">Use only when today\'s prototype timers are wrong, such as a shift accidentally being left running. This resets today to <b>OFF DUTY from midnight</b>, restores the available prototype clocks, and writes a DRIVER EDIT entry to the audit trail.</p><button id="resetTodayBtnV35" class="secondary">RESET TODAY — CORRECT ACCIDENTAL TIMER</button><div class="status warn" style="margin-top:8px">⚠️ This changes the prototype log. It does not alter a certified ELD or erase a legally required record.</div>';
 host.appendChild(c);
 $('resetTodayBtnV35').onclick=()=>{
   const s=load();
   const ok=confirm('WARNING: This will replace ALL prototype HOS duty periods recorded for TODAY with OFF DUTY from midnight. The action will be permanently logged as a DRIVER EDIT. Continue?');
   if(!ok)return;
   const ok2=confirm('FINAL CONFIRMATION: Reset today\'s timers and record the correction in the audit trail?');
   if(ok2)resetToday();
 };
}
function init(){add();setTimeout(add,500);setTimeout(add,1500)}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();
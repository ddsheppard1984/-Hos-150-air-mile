(()=>{'use strict';
const API='/api/state';
let version=null,dirty=false,timer=null,busy=false;
const snapshot=()=>{const o={};for(let i=0;i<localStorage.length;i++){const k=localStorage.key(i);if(k!==null&&!k.startsWith('hos150_local_recovery_'))o[k]=localStorage.getItem(k)}return o};
const apply=o=>{if(!o||typeof o!=='object')return;for(const [k,v] of Object.entries(o)){if(typeof v==='string')localStorage.setItem(k,v)}window.dispatchEvent(new Event('hos150:state-updated'))};
async function loadServer(){const r=await fetch(API,{cache:'no-store',credentials:'same-origin'});if(!r.ok)throw Error('state fetch failed');const j=await r.json();if(j.exists){apply(j.state);version=j.updated_at}return j}
async function push(){if(busy){dirty=true;return}busy=true;try{
 const r=await fetch(API,{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify({state:snapshot(),base_updated_at:version}),cache:'no-store',credentials:'same-origin',keepalive:true});
 if(r.status===409){const j=await r.json();try{const k='hos150_local_recovery_'+Date.now();const v=localStorage.getItem('hos150v13');if(v&&v.length<250000)origSet.call(localStorage,k,v);window.dispatchEvent(new CustomEvent('hos150:sync-conflict',{detail:{recoveryKey:k}}));}catch(e){}apply(j.state);version=j.updated_at;dirty=false;return}
 if(!r.ok)throw Error('state save failed');
 const j=await r.json();version=j.updated_at;dirty=false;
}catch(e){}finally{busy=false;if(dirty)schedule()}}
function schedule(){clearTimeout(timer);timer=setTimeout(push,700)}
try{
 const x=new XMLHttpRequest();x.open('GET',API,false);x.setRequestHeader('Cache-Control','no-store');x.send(null);
 if(x.status===200){const r=JSON.parse(x.responseText||'{}');version=r.updated_at||null;if(r.exists)apply(r.state);else if(localStorage.length){const y=new XMLHttpRequest();y.open('PUT',API,false);y.setRequestHeader('Content-Type','application/json');y.send(JSON.stringify({state:snapshot(),base_updated_at:null}));if(y.status===200){const z=JSON.parse(y.responseText||'{}');version=z.updated_at||null}}}
}catch(e){}
const p=Storage.prototype,origSet=p.setItem,origRemove=p.removeItem,origClear=p.clear;
p.setItem=function(k,v){const r=origSet.call(this,k,v);if(this===localStorage){dirty=true;schedule()}return r};
p.removeItem=function(k){const r=origRemove.call(this,k);if(this===localStorage){dirty=true;schedule()}return r};
p.clear=function(){const r=origClear.call(this);if(this===localStorage){dirty=true;schedule()}return r};
window.addEventListener('online',async()=>{if(dirty){schedule();return}try{await loadServer()}catch(e){}});
document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='hidden'&&dirty)push()});
setInterval(async()=>{if(!navigator.onLine||busy)return;try{const r=await fetch(API,{cache:'no-store',credentials:'same-origin'});if(!r.ok)return;const j=await r.json();if(j.updated_at&&version&&j.updated_at!==version){if(dirty){schedule();return}apply(j.state);version=j.updated_at;dirty=false}else if(dirty)push()}catch(e){}},15000);
window.HOS150ServerSync={saveNow:push,snapshot,loadServer};
})();
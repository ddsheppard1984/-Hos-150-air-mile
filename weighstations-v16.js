(()=>{
'use strict';
const WSKEY='hos150-weigh-v16';
let stations=[],lastAlert=0,lastFetch=0;
const $=id=>document.getElementById(id);
const miles=(a,b)=>{const R=3958.761,p=Math.PI/180,dLat=(b.lat-a.lat)*p,dLon=(b.lon-a.lon)*p,q=Math.sin(dLat/2)**2+Math.cos(a.lat*p)*Math.cos(b.lat*p)*Math.sin(dLon/2)**2;return R*2*Math.atan2(Math.sqrt(q),Math.sqrt(1-q));};
function esc(s){return String(s||'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
function card(){
 if($('weighAhead'))return;
 const trip=document.querySelector('#trip'); if(!trip)return;
 const c=document.createElement('div'); c.className='card'; c.id='weighAhead';
 c.innerHTML='<h2>⚖️ Weigh Stations Ahead</h2><div id="weighStatus" class="status neutral">Checking route for weigh/inspection stations…</div><div id="weighList"></div><p class="muted">Open/closed is shown only when a live DOT/511 feed reports it. Unknown never means closed.</p>';
 trip.appendChild(c);
}
function settings(){
 const s=document.querySelector('#settings'); if(!s||$('weighSettings'))return;
 const c=document.createElement('div'); c.className='card'; c.id='weighSettings';
 c.innerHTML='<h2>⚖️ Weigh Station Alerts</h2><div class="grid g2"><label>Live Road511 API key<input id="road511Key" type="password" placeholder="Optional — keep private"></label><label>Alert distance<select id="weighAlertMiles"><option value="10">10 miles</option><option value="5">5 miles</option><option value="1">1 mile</option></select></label></div><div class="row"><button id="saveWeighSettings">SAVE WEIGH SETTINGS</button><button id="testWeigh" class="secondary">CHECK NOW</button></div><div id="weighSettingsMsg" class="status neutral">Without an API key, the app can show nearby mapped stations but their status will be UNKNOWN.</div><p class="muted">Road511 requires an API key for live data. For a production App Store version, put the key behind a small server/proxy instead of shipping it in the app.</p>';
 s.appendChild(c);
 const x=JSON.parse(localStorage.getItem(WSKEY)||'{}'); $('road511Key').value=x.key||''; $('weighAlertMiles').value=x.alert||10;
 $('saveWeighSettings').onclick=()=>{localStorage.setItem(WSKEY,JSON.stringify({key:$('road511Key').value.trim(),alert:+$('weighAlertMiles').value}));$('weighSettingsMsg').textContent='Saved. Checking weigh stations…';check(true)};
 $('testWeigh').onclick=()=>check(true);
}
async function road511(pos,key){
 const u=`https://api.road511.com/api/v1/features?type=weigh_stations&lat=${pos.lat}&lng=${pos.lon}&radius_km=160`;
 const r=await fetch(u,{headers:{'X-API-Key':key}}); if(!r.ok)throw Error('Road511 '+r.status); const j=await r.json();
 return (j.data||[]).map(x=>({id:x.id,name:x.name||x.properties?.name||'Weigh station',lat:+x.latitude||+x.geometry?.coordinates?.[1],lon:+x.longitude||+x.geometry?.coordinates?.[0],status:x.properties?.status||x.status||'unknown',asof:x.properties?.as_of||x.as_of||x.last_updated||null,source:'Road511'})).filter(x=>Number.isFinite(x.lat)&&Number.isFinite(x.lon));
}
async function overpass(pos){
 const q=`[out:json][timeout:12];(node[amenity=weigh_station](around:160000,${pos.lat},${pos.lon});way[amenity=weigh_station](around:160000,${pos.lat},${pos.lon}););out center tags;`;
 const r=await fetch('https://overpass-api.de/api/interpreter',{method:'POST',body:q}); if(!r.ok)throw Error('map data unavailable'); const j=await r.json();
 return (j.elements||[]).map(x=>({id:'osm-'+x.id,name:x.tags?.name||'Weigh station',lat:x.lat??x.center?.lat,lon:x.lon??x.center?.lon,status:'unknown',asof:null,source:'OpenStreetMap'})).filter(x=>Number.isFinite(x.lat)&&Number.isFinite(x.lon));
}
function render(pos){
 card();
 if(!stations.length){$('weighStatus').className='status neutral';$('weighStatus').textContent='No weigh/inspection stations found in the next search area.';$('weighList').innerHTML='';return;}
 const list=stations.map(s=>({...s,d:miles(pos,s)})).sort((a,b)=>a.d-b.d).slice(0,8);
 const ahead=list.filter(x=>x.d<=160);
 $('weighStatus').className='status '+(ahead.length?'warn':'neutral');$('weighStatus').textContent=ahead.length?`⚖️ ${ahead.length} station${ahead.length>1?'s':''} within 160 miles`:'No station within 160 miles.';
 $('weighList').innerHTML=list.map(x=>{const st=String(x.status||'unknown').toLowerCase();const icon=st==='open'?'🟢':st==='closed'?'🔴':'🟡';const age=x.asof?new Date(x.asof).toLocaleString():'';return `<div class="status ${st==='open'?'good':st==='closed'?'bad':'neutral'}" style="margin:8px 0"><b>${icon} ${esc(x.name)}</b> • ${x.d.toFixed(1)} mi<br><small>${st.toUpperCase()}${age?' • updated '+esc(age):''} • ${esc(x.source)}</small></div>`}).join('');
 const alert=+((JSON.parse(localStorage.getItem(WSKEY)||'{}').alert)||10);const nearest=list[0];if(nearest&&nearest.d<=alert&&Date.now()-lastAlert>300000){lastAlert=Date.now();const st=String(nearest.status).toLowerCase();const msg=`Weigh station ahead in ${nearest.d.toFixed(1)} miles. Status ${st}.`;if('speechSynthesis'in window){speechSynthesis.cancel();speechSynthesis.speak(new SpeechSynthesisUtterance(msg));}if(navigator.vibrate)navigator.vibrate([150,100,150]);}}
async function check(force=false){
 const pos=window.S?.pos; if(!pos){if($('weighStatus')){$('weighStatus').textContent='Enable GPS to detect the next weigh station.';$('weighStatus').className='status neutral';}return;}
 if(!force&&Date.now()-lastFetch<60000)return;lastFetch=Date.now();
 const cfg=JSON.parse(localStorage.getItem(WSKEY)||'{}');
 try{stations=cfg.key?await road511(pos,cfg.key):await overpass(pos);render(pos);}catch(e){$('weighStatus')&&($('weighStatus').className='status warn',$('weighStatus').textContent='Weigh-station data unavailable right now. Try CHECK NOW again.');}
}
function init(){card();settings();setTimeout(()=>check(true),1500);setInterval(()=>check(false),60000);}
window.addEventListener('load',init);
window.addEventListener('hos150:position',()=>check(false));
// Hook the existing app's POI scale button without changing its core code.
document.addEventListener('click',e=>{const b=e.target.closest('[data-poi="scale"]');if(b){setTimeout(()=>check(true),300);}});
})();

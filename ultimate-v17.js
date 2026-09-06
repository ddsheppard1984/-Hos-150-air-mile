(()=>{
'use strict';
const KEY='hos150v13';
const $=id=>document.getElementById(id);
const load=()=>JSON.parse(localStorage.getItem(KEY)||'{}');
const save=s=>localStorage.setItem(KEY,JSON.stringify(s));
let liveTimer=null,routeMap=null,routeMarker=null,routeLine=null,routeSteps=[];
const getUnit=()=>load().settings?.tempUnit||'F';
function patchWeatherUnits(){
  const unit=getUnit();
  const oldFetch=window.fetch;
  if(window.__v17FetchPatched)return;
  window.__v17FetchPatched=true;
  window.fetch=async function(input,init){
    let url=typeof input==='string'?input:input?.url||'';
    if(url.includes('api.open-meteo.com')){
      const u=new URL(url);
      u.searchParams.set('temperature_unit',unit==='F'?'fahrenheit':'celsius');
      u.searchParams.set('wind_speed_unit',unit==='F'?'mph':'kmh');
      input=u.toString();
    }
    return oldFetch.call(this,input,init);
  };
}
function convertWeatherLabels(){
  const unit=getUnit(),label=unit==='F'?'°F':'°C';
  ['weatherNow','forecast','routeWeather'].forEach(id=>{
    const el=$(id); if(!el)return;
    el.innerHTML=el.innerHTML.replace(/°[CF]/g,label).replace(/\b(-?\d+(?:\.\d+)?)\s*°?C\b/g,`$1 ${label}`);
  });
}
function injectSettings(){
  const s=document.querySelector('#settings'); if(!s||$('v17Settings'))return;
  const c=document.createElement('div'); c.className='card'; c.id='v17Settings';
  c.innerHTML=`<h2>⚙️ Driver Experience</h2><div class="grid g2">
  <label>Temperature units<select id="tempUnit"><option value="F">Fahrenheit (°F)</option><option value="C">Celsius (°C)</option></select></label>
  <label>Distance units<select id="distanceUnit"><option value="mi">Miles</option><option value="km">Kilometers</option></select></label>
  <label>AI mode<select id="aiMode"><option value="balanced">Balanced</option><option value="safety">Safety first</option><option value="fuel">Fuel economy</option><option value="delivery">On-time delivery</option><option value="quiet">On request only</option></select></label>
  <label>Live route alerts<select id="liveAlerts"><option value="on">ON</option><option value="off">OFF</option></select></label>
  <label>Weigh station warning<select id="scaleWarn"><option value="10">10 miles</option><option value="5">5 miles</option><option value="1">1 mile</option></select></label>
  <label>Traffic refresh<select id="refreshRate"><option value="5">5 minutes</option><option value="10">10 minutes</option><option value="15">15 minutes</option></select></label>
  </div><hr><h3>🤖 Live AI Route Intelligence</h3><p class="muted">The app can combine live traffic/construction/closure data with your route. An AI provider key is optional and should be moved to a secure backend before public release.</p>
  <div class="grid g2"><input id="road511Key" type="password" placeholder="Road511 API key (live traffic/events)"><input id="openaiKey" type="password" placeholder="Optional AI API key (prototype only)"></div>
  <button id="saveV17Settings">SAVE DRIVER EXPERIENCE SETTINGS</button><div id="v17SettingsMsg" class="status neutral">Not saved.</div>`;
  s.appendChild(c);
  const x=load(),cfg=x.settings||{};
  $('tempUnit').value=cfg.tempUnit||'F';$('distanceUnit').value=cfg.distanceUnit||'mi';$('aiMode').value=cfg.aiMode||'balanced';$('liveAlerts').value=cfg.liveAlerts||'on';$('scaleWarn').value=cfg.scaleWarn||'10';$('refreshRate').value=cfg.refreshRate||'5';$('road511Key').value=cfg.road511Key||'';$('openaiKey').value=cfg.openaiKey||'';
  $('saveV17Settings').onclick=()=>{const st=load();st.settings={tempUnit:$('tempUnit').value,distanceUnit:$('distanceUnit').value,aiMode:$('aiMode').value,liveAlerts:$('liveAlerts').value,scaleWarn:$('scaleWarn').value,refreshRate:$('refreshRate').value,road511Key:$('road511Key').value.trim(),openaiKey:$('openaiKey').value.trim()};save(st);$('v17SettingsMsg').textContent='Saved. Weather will use '+(st.settings.tempUnit==='F'?'Fahrenheit':'Celsius')+'.';convertWeatherLabels();startLiveRouteIntel();};
}
function injectRoutePage(){
  if(document.querySelector('nav [data-tab="route"]'))return;
  const nav=document.querySelector('nav'); if(!nav)return;
  const b=document.createElement('button');b.dataset.tab='route';b.textContent='🧭 Live Route';nav.insertBefore(b,nav.children[1]);b.onclick=()=>showRoute();
  const main=document.querySelector('main');
  const sec=document.createElement('section');sec.id='route';sec.className='screen';
  sec.innerHTML=`<div class="card"><h2>🧭 LIVE TRUCK ROUTE</h2><div class="grid g3"><div><label>Destination</label><strong id="rDest">--</strong></div><div><label>Route distance</label><strong id="rMiles">--</strong></div><div><label>ETA</label><strong id="rEta">--</strong></div></div><div class="row"><button id="routeUseGps">📍 CENTER ON GPS</button><button id="routeRecalc">🔄 RECALCULATE ROUTE</button><button id="routeNavVoice">🔊 VOICE</button></div><div id="routeStatus" class="status neutral">Plan a trip first, or enter a destination below.</div></div><div class="card"><div id="routeMap" style="height:58vh;min-height:360px;border-radius:14px;overflow:hidden"></div></div><div class="grid g2"><div class="card"><h2>➡️ Upcoming Turns</h2><div id="routeTurns" class="scroll"></div></div><div class="card"><h2>⚠️ What's Ahead</h2><div id="aheadFeed"><div class="status neutral">Live route intelligence waiting for a route.</div></div></div></div>`;
  main.appendChild(sec);
  $('routeUseGps').onclick=()=>centerRoute();$('routeRecalc').onclick=()=>recalcRoute();$('routeNavVoice').onclick=()=>speakNextTurn();
}
function showRoute(){document.querySelectorAll('.screen').forEach(x=>x.classList.remove('active'));$('route')?.classList.add('active');document.querySelectorAll('nav button').forEach(x=>x.classList.remove('sel'));document.querySelector('nav [data-tab="route"]')?.classList.add('sel');setTimeout(()=>{initRouteMap();updateRouteView();},100)}
function initRouteMap(){if(routeMap||!window.L||!$('routeMap'))return;const s=load(),p=s.pos;routeMap=L.map('routeMap').setView(p?[p.lat,p.lon]:[39,-96],5);L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',{attribution:'© OpenStreetMap contributors'}).addTo(routeMap);if(p)routeMarker=L.marker([p.lat,p.lon]).addTo(routeMap);routeMap.invalidateSize()}
function updateRouteView(){const s=load();if(!routeMap)return;if(s.pos){if(!routeMarker)routeMarker=L.marker([s.pos.lat,s.pos.lon]).addTo(routeMap);else routeMarker.setLatLng([s.pos.lat,s.pos.lon]);}if(s.route&&s.route.length){if(routeLine)routeLine.remove();routeLine=L.geoJSON({type:'LineString',coordinates:s.route}).addTo(routeMap);try{routeMap.fitBounds(routeLine.getBounds(),{padding:[30,30]})}catch{}}$('rDest').textContent=s.routeEnd||'--';$('rMiles').textContent=s.routeMiles?Math.round(s.routeMiles)+' mi':'--';$('rEta').textContent=s.routeMiles?estimateEta(s):'--';if(s.routeSteps?.length){routeSteps=s.routeSteps;renderTurns()}else if($('routeTurns'))$('routeTurns').innerHTML='<div class="status neutral">Turn-by-turn steps will appear after recalculating the route.</div>';}
function estimateEta(s){let mins=+s.routeMinutes||0;const drivingRemaining=Math.max(0,11*3600000-activeDrive(s));if(mins*60000>drivingRemaining)mins+=30;return new Date(Date.now()+mins*60000).toLocaleTimeString([],{hour:'numeric',minute:'2-digit'});}
function activeDrive(s){return (s.segments||[]).reduce((n,x)=>n+(x.status==='DRIVING'?Math.max(0,x.end-x.start):0),0)+(s.status==='DRIVING'?Date.now()-s.currentStart:0)}
async function recalcRoute(){const s=load(),dest=s.routeEnd||$('destination')?.value?.trim();if(!dest){alert('Enter a destination on the Trip page first.');return}try{let start=s.pos?[s.pos.lon,s.pos.lat]:null;if(!start){const q=await geocode(s.routeStart||'Portland, ME');start=[q.lon,q.lat]}const e=await geocode(dest);const u=`https://router.project-osrm.org/route/v1/driving/${start[0]},${start[1]};${e.lon},${e.lat}?overview=full&geometries=geojson&steps=true`;const j=await (await fetch(u)).json();if(!j.routes?.length)throw Error('No route');const r=j.routes[0];s.route=r.geometry.coordinates;s.routeMiles=r.distance/1609.344;s.routeMinutes=r.duration/60;s.routeEnd=dest;s.routeSteps=(r.legs||[]).flatMap(l=>l.steps||[]).map(x=>({name:x.name||'Unnamed road',type:x.maneuver?.type||'',modifier:x.maneuver?.modifier||'',distance:x.distance||0,location:x.maneuver?.location}));save(s);showRoute();$('routeStatus').className='status good';$('routeStatus').textContent='Live route loaded. GPS position will update on this page.';await refreshLiveRoute();}catch(e){$('routeStatus').className='status bad';$('routeStatus').textContent='Route could not be calculated: '+e.message}}
async function geocode(q){const r=await fetch('https://nominatim.openstreetmap.org/search?format=json&limit=1&q='+encodeURIComponent(q));const a=await r.json();if(!a.length)throw Error('Destination not found');return {lon:+a[0].lon,lat:+a[0].lat,name:a[0].display_name}}
function renderTurns(){const el=$('routeTurns');if(!el)return;el.innerHTML=routeSteps.slice(0,20).map((x,i)=>`<div class="status neutral"><b>${i+1}. ${x.modifier||x.type||'Continue'}</b> • ${x.name||'road'}<br>${(x.distance/1609.344).toFixed(1)} mi</div>`).join('')}
function centerRoute(){const s=load();if(!routeMap||!s.pos)return;routeMap.setView([s.pos.lat,s.pos.lon],15);if(routeMarker)routeMarker.setLatLng([s.pos.lat,s.pos.lon])}
function speakNextTurn(){const x=routeSteps[0];if(!x||!('speechSynthesis' in window))return; speechSynthesis.cancel();speechSynthesis.speak(new SpeechSynthesisUtterance(`${x.modifier||'Continue'} on ${x.name||'the route'} for ${(x.distance/1609.344).toFixed(1)} miles.`));}
async function refreshLiveRoute(){const s=load(),cfg=s.settings||{},key=cfg.road511Key;if(!key||!s.pos){renderAhead([]);return}try{const p=new URLSearchParams({lat:s.pos.lat,lng:s.pos.lon,radius_km:'80',status:'active',limit:'100'});const r=await fetch('https://api.road511.com/api/v1/events?'+p,{headers:{'X-API-Key':key}});if(!r.ok)throw Error('Road511 '+r.status);const j=await r.json();let data=j.data||[];if(s.routeEnd&&s.routeMiles){data=data.filter(e=>e.latitude!=null&&e.longitude!=null)}renderAhead(data);if(cfg.openaiKey&&cfg.aiMode!=='quiet')aiSummarize(data,s);}catch(e){renderAhead([],'Live traffic feed unavailable: '+e.message)}}
function renderAhead(data,msg){const el=$('aheadFeed');if(!el)return;if(msg){el.innerHTML=`<div class="status warn">${msg}</div>`;return}if(!data.length){el.innerHTML='<div class="status good">🟢 No active Road511 events returned near your current GPS position.</div>';return}el.innerHTML=data.slice(0,12).map(e=>`<div class="status ${e.severity==='critical'||e.severity==='major'?'bad':e.type==='construction'?'warn':'neutral'}"><b>${iconType(e.type)} ${escapeHtml(e.title||e.type||'Route event')}</b><br>${escapeHtml(e.description||'')}<br><small>${escapeHtml((e.affected_roads||[]).join(', '))} • ${e.severity||'unknown'} • ${e.last_updated?new Date(e.last_updated).toLocaleTimeString():''}</small></div>`).join('')}
function iconType(t){return t==='construction'?'🚧':t==='closure'?'⛔':t==='weather'?'🌦️':t==='incident'?'🚨':'⚠️'}
function escapeHtml(x){return String(x).replace(/[&<>\"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',"'":'&#39;'}[c]))}
async function aiSummarize(events,s){const key=s.settings?.openaiKey;if(!key||!events.length)return;try{const route=s.routeEnd||'current route';const prompt=`You are a truck-driver route copilot. Summarize these live road events for a driver headed toward ${route}. Prioritize closures, major/critical incidents, construction and weather. Do not invent facts. Give 3-6 concise bullets and clearly say when data is unavailable. Events: ${JSON.stringify(events.slice(0,15))}`;const r=await fetch('https://api.openai.com/v1/responses',{method:'POST',headers:{'Content-Type':'application/json','Authorization':'Bearer '+key},body:JSON.stringify({model:'gpt-5-mini',input:prompt})});if(!r.ok)return;const j=await r.json();const text=j.output_text||j.output?.flatMap(x=>x.content||[]).map(x=>x.text||'').join('')||'';if(text&&$('aheadFeed'))$('aheadFeed').insertAdjacentHTML('afterbegin',`<div class="status blue"><b>🤖 AI ROUTE BRIEF</b><br>${escapeHtml(text).replace(/\n/g,'<br>')}</div>`)}catch{}}
function startLiveRouteIntel(){clearInterval(liveTimer);const s=load(),mins=+(s.settings?.refreshRate||5);liveTimer=setInterval(()=>{const active=document.querySelector('#route.active');if(active)refreshLiveRoute()},mins*60000);if(document.querySelector('#route.active'))refreshLiveRoute()}
function bind(){patchWeatherUnits();injectSettings();injectRoutePage();convertWeatherLabels();const obs=new MutationObserver(()=>{convertWeatherLabels();});['forecast','weatherNow','routeWeather'].forEach(id=>$(id)&&obs.observe($(id),{childList:true,subtree:true,characterData:true}));startLiveRouteIntel();setInterval(()=>{if(document.querySelector('#route.active')){const s=load();if(routeMarker&&s.pos)routeMarker.setLatLng([s.pos.lat,s.pos.lon]);}},2000)}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',bind);else bind();
})();
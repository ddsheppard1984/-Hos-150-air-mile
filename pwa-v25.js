/* HOS 150 Driver Companion V34 — stable PWA shell + GPS weather + Mapbox traffic */
(()=>{'use strict';
const APP='HOS 150 Driver Companion V34';
function brand(){document.title=APP;const d=document.querySelector('meta[name="description"]');if(d)d.content='HOS, truck navigation, GPS, trip planning, live traffic, incidents, weather, driver tools, customer address book and 150-air-mile companion for professional drivers.';document.querySelectorAll('meta[name="app-version"],meta[name="build-id"]').forEach(x=>x.setAttribute('content',x.name==='app-version'?'34.0':'2026-09-10-v34.0'));let m=document.querySelector('link[rel="manifest"]');if(m)m.href='manifest.webmanifest?v=34.0'}
function theme(){if(document.getElementById('futureThemeV1'))return;const l=document.createElement('link');l.id='futureThemeV1';l.rel='stylesheet';l.href='theme-future-v1.css?v=32.0';document.head.appendChild(l)}
function load(src,id){if(document.querySelector('script[data-'+id+']'))return;const s=document.createElement('script');s.src=src;s.dataset[id]='1';document.body.appendChild(s)}
function visual(){if(document.getElementById('v31navvisual'))return;const s=document.createElement('style');s.id='v31navvisual';s.textContent='.n28actions{display:grid!important;grid-template-columns:repeat(2,minmax(0,1fr));gap:9px!important;margin-top:10px!important}.n28actions .n28btn{min-height:48px!important}';document.head.appendChild(s)}
function installButton(){if(window.matchMedia('(display-mode: standalone)').matches||window.navigator.standalone||document.getElementById('pwaInstall'))return;const b=document.createElement('button');b.id='pwaInstall';b.textContent='📲 INSTALL APP';b.className='secondary';b.style.cssText='position:fixed;right:10px;top:10px;z-index:99999;font-weight:800';b.onclick=()=>alert('On iPhone: tap Share in Safari, then Add to Home Screen. On Android: use the browser menu and choose Install app.');document.body.appendChild(b)}
function sw(){if('serviceWorker'in navigator)navigator.serviceWorker.register('./sw.js?v=34.0').catch(()=>{})}
function boot(){brand();theme();visual();installButton();sw();load('customer-routing-v31.js?v=34.0','customer-routing-v31');load('gps-weather-fix-v33.js?v=34.0','gps-weather-fix-v33');load('mapbox-traffic-v1.js?v=34.0','mapbox-traffic-v1')}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot);else boot();
})();

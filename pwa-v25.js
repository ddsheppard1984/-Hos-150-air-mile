/* HOS 150 Driver Companion V31 — installable app shell */
(()=>{'use strict';
const APP='HOS 150 Driver Companion V31';
function brand(){
  document.title=APP;
  const d=document.querySelector('meta[name="description"]');
  if(d)d.content='HOS, truck navigation, GPS, trip planning, weather, driver tools, customer address book, contact import and 150-air-mile companion for professional drivers.';
  document.querySelectorAll('meta[name="app-version"],meta[name="build-id"]').forEach(x=>x.setAttribute('content',x.name==='app-version'?'31.0':'2026-09-10-v31.0'));
  const walk=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT);const nodes=[];while(walk.nextNode())nodes.push(walk.currentNode);nodes.forEach(n=>{if(n.nodeValue&&/TruckWaze/i.test(n.nodeValue))n.nodeValue=n.nodeValue.replace(/TruckWaze/gi,'Truck Navigation')});
  let m=document.querySelector('link[rel="manifest"]');if(m)m.href='manifest.webmanifest?v=31.0';
  if(!document.querySelector('meta[name="apple-mobile-web-app-capable"]')){let a=document.createElement('meta');a.name='apple-mobile-web-app-capable';a.content='yes';document.head.appendChild(a)}
  if(!document.querySelector('meta[name="apple-mobile-web-app-status-bar-style"]')){let a=document.createElement('meta');a.name='apple-mobile-web-app-status-bar-style';a.content='black-translucent';document.head.appendChild(a)}
  if(!document.querySelector('meta[name="apple-mobile-web-app-title"]')){let a=document.createElement('meta');a.name='apple-mobile-web-app-title';a.content=APP;document.head.appendChild(a)}
  if(!document.querySelector('link[rel="apple-touch-icon"]')){let a=document.createElement('link');a.rel='apple-touch-icon';a.href='app-icon.svg';document.head.appendChild(a)}
  installButton();
}
function loadCustomerEnhancements(){if(document.querySelector('script[data-customer-v30]'))return;const s=document.createElement('script');s.src='customer-place-enhancements-v30.js?v=30.0';s.dataset.customerV30='1';document.body.appendChild(s)}
function loadTools(){if(document.querySelector('script[data-customer-tools-v31]'))return;const s=document.createElement('script');s.src='customer-tools-v31.js?v=31.0';s.dataset.customerToolsV31='1';document.body.appendChild(s)}
function installButton(){if(window.matchMedia('(display-mode: standalone)').matches||window.navigator.standalone)return;if(document.getElementById('pwaInstall'))return;const b=document.createElement('button');b.id='pwaInstall';b.textContent='📲 INSTALL APP';b.className='secondary';b.style.cssText='position:fixed;right:10px;top:10px;z-index:99999;font-weight:800;box-shadow:0 3px 12px rgba(0,0,0,.25)';let deferred=null;window.addEventListener('beforeinstallprompt',e=>{e.preventDefault();deferred=e});b.onclick=async()=>{if(deferred){deferred.prompt();try{await deferred.userChoice}catch{}deferred=null;return}alert('On iPhone: tap the Share button in Safari, then choose “Add to Home Screen”. On Android: use the browser menu and choose “Install app” or “Add to Home screen”.')};document.body.appendChild(b)}
function sw(){if('serviceWorker'in navigator)navigator.serviceWorker.register('./sw.js?v=31.0').catch(()=>{})}
function boot(){brand();sw();loadCustomerEnhancements();loadTools()}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot);else boot();
})();

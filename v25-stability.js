/* HOS 150 V25 stability layer */
(()=>{'use strict';
function boot(){
  const fix=()=>{
    const truck=document.getElementById('tw25truck');
    if(truck){truck.onclick=()=>window.TW25?.truck();}
    const stops=document.getElementById('tw25stops');
    if(stops){stops.onclick=()=>window.TW25?.stops('parking');}
    const route=document.getElementById('route');
    if(route){route.querySelectorAll('*').forEach(el=>{if(el.childNodes.length===1&&el.firstChild.nodeType===3&&/TruckWaze/i.test(el.textContent))el.firstChild.nodeValue=el.textContent.replace(/TruckWaze/gi,'Truck Navigation')});}
  };
  fix();
  setTimeout(fix,600);setTimeout(fix,1800);setTimeout(fix,3500);
  document.addEventListener('click',e=>{if(e.target.closest('[data-tab="route"]')){setTimeout(()=>window.dispatchEvent(new Event('resize')),80);setTimeout(()=>window.dispatchEvent(new Event('resize')),500);setTimeout(fix,100)}});
  window.addEventListener('orientationchange',()=>setTimeout(()=>window.dispatchEvent(new Event('resize')),300));
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>setTimeout(boot,2200));else setTimeout(boot,2200);
})();

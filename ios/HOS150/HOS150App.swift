import SwiftUI
import WebKit
import CoreLocation
import LocalAuthentication
import UserNotifications

private let primaryURL = "https://hos150.houseofsqueak.com/"
private let accessLoginHost = "weathered-leaf-b8c1.cloudflareaccess.com"

@main
struct HOS150NativeApp: App {
    var body: some Scene {
        WindowGroup { HOS150Home() }
    }
}

final class HOSLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var status = "GPS off"
    private let manager = CLLocationManager()
    weak var webView: WKWebView?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
    }
    func start() {
        guard CLLocationManager.locationServicesEnabled() else {
            status = "Enable iPhone Location Services"
            return
        }
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        status = "GPS requested"
    }
    func stop() {
        manager.stopUpdatingLocation()
        status = "GPS off"
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            status = "Location permission denied"
        case .notDetermined:
            status = "GPS permission pending"
        @unknown default:
            status = "GPS unavailable"
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "GPS: \(error.localizedDescription)"
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let pos = locations.last,
              pos.horizontalAccuracy >= 0,
              pos.timestamp.timeIntervalSinceNow > -60 else { return }
        status = String(format: "GPS ±%.0f m", pos.horizontalAccuracy)
        // Transparent native telemetry. Does not override the website's Geolocation API
        // or silently modify the driver's recorded duty status.
        let payload: [String: Any] = [
            "latitude": pos.coordinate.latitude,
            "longitude": pos.coordinate.longitude,
            "accuracyM": pos.horizontalAccuracy,
            "speedMps": max(0, pos.speed),
            "timestamp": ISO8601DateFormatter().string(from: pos.timestamp),
            "source": "iOS CoreLocation when-in-use"
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let json = String(data: data, encoding: .utf8) {
            webView?.evaluateJavaScript(
                "window.dispatchEvent(new CustomEvent('hos150:native-location',{detail:\(json)}))",
                completionHandler: nil)
        }
    }
}

struct HOS150Home: View {
    @AppStorage("hos150PrivateServerURL") private var address = primaryURL
    @StateObject private var location = HOSLocation()
    @State private var webID = UUID()
    @State private var busy = true
    @State private var failure: String? = nil
    @State private var editSettings = false
    @State private var draft = ""
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hos150BiometricLock") private var biometricLock = false
    @AppStorage("hos150Reminders") private var reminders = false
    @State private var unlocked = false
    @State private var lockError = ""

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(red: 0.035, green: 0.055, blue: 0.085).ignoresSafeArea()
            HOS150Browser(address: address, location: location) { message, failed in
                failure = failed ? message : nil
                busy = message != nil && !failed
            }
            .id(webID)
            .padding(.top, 86) // Keep web content below the native four-button toolbar.
            .ignoresSafeArea(edges: .bottom)

            if busy || failure != nil {
                VStack(spacing: 14) {
                    Image(systemName: failure == nil ? "truck.box.fill" : "wifi.exclamationmark")
                        .font(.system(size: 43)).foregroundStyle(.mint)
                    Text(failure == nil ? "Connecting to HOS 150" : "Connection Problem")
                        .font(.headline).foregroundStyle(.white)
                    Text(failure ?? "Opening your secure driver dashboard…")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                    if busy { ProgressView().tint(.mint) }
                    if failure != nil {
                        Button("Retry") { reload() }
                            .buttonStyle(.borderedProminent).tint(.mint)
                        Button("Open in Safari") {
                            if let url = URL(string: address) { UIApplication.shared.open(url) }
                        }.buttonStyle(.bordered)
                        Text("Cloudflare Access may request a one-time email code. No Tailscale is required on this phone.")
                            .font(.caption).foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }
                    Button("Server Settings") {
                        draft = address
                        editSettings = true
                    }.foregroundStyle(.mint)
                }
                .padding(22)
                .frame(maxWidth: 340)
                .background(Color(red: 0.08, green: 0.12, blue: 0.18), in: RoundedRectangle(cornerRadius: 18))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 10) {
                Button {
                    location.webView?.evaluateJavaScript("document.querySelector('nav [data-tab=\"log\"]')?.click(); void(0)", completionHandler: nil)
                } label: {
                    Image(systemName: "text.book.closed.fill")
                }
                .accessibilityLabel("Open HOS log corrections")
                Button {
                    // A WebKit view refresh preserves the app's persistent local storage.
                    reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh HOS driver dashboard")
                Button {
                    if location.status == "GPS off" {
                        location.start()
                    } else {
                        location.stop()
                    }
                } label: {
                    Image(systemName: "location.circle.fill")
                }
                .accessibilityLabel("Toggle native GPS")
                .accessibilityHint(location.status)
                Button {
                    draft = address
                    editSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .accessibilityLabel("HOS server settings")
            }
            .font(.title3)
            .foregroundStyle(.primary)
            .padding(10)
            .background(.regularMaterial, in: Capsule())
            .padding(10)
        }
        .onAppear { if biometricLock { unlock() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && biometricLock { unlocked = false }
            if phase == .active && biometricLock && !unlocked { unlock() }
        }
        .overlay {
            if biometricLock && !unlocked {
                ZStack {
                    Color(red: 0.035, green: 0.055, blue: 0.085).ignoresSafeArea()
                    VStack(spacing: 18) {
                        Image(systemName: "lock.shield.fill").font(.system(size: 48)).foregroundStyle(.mint)
                        Text("HOS 150 is locked").font(.title2).bold().foregroundStyle(.white)
                        Text(lockError.isEmpty ? "Unlock with Face ID or your device passcode." : lockError)
                            .foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                        Button("Unlock HOS 150") { unlock() }.buttonStyle(.borderedProminent)
                        Button("Open secure website in Safari") {
                            if let url = URL(string: address) { UIApplication.shared.open(url) }
                        }.foregroundStyle(.mint)
                    }.padding(30)
                }
            }
        }
        .sheet(isPresented: $editSettings) {
            NavigationStack {
                Form {
                    Section("Secure HOS 150 URL") {
                        TextField("https://...", text: $draft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        Button("Save & Connect") {
                            guard approvedURL(draft) else { return }
                            address = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                            editSettings = false
                            reload()
                        }.disabled(!approvedURL(draft))
                    }
                    Section("HOS 150 V38 Driver Workspace") {
                        Text("Native app version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")")
                        Text("The live driver screens, Start Fresh log corrections, and offline data remain on your secured Squeak Server.")
                        Button("Refresh Driver Workspace") {
                            editSettings = false
                            reload()
                        }
                    }
                    Section("Privacy and Alerts") {
                        Toggle("Lock with Face ID or device passcode", isOn: $biometricLock)
                            .onChange(of: biometricLock) { _, enabled in
                                if enabled { unlocked = false; unlock() }
                                else { unlocked = true; lockError = "" }
                            }
                        Toggle("Enable HOS warning notifications", isOn: $reminders)
                            .onChange(of: reminders) { _, enabled in
                                if enabled {
                                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
                                }
                            }
                        Text("Notifications are advisory and never replace certified ELD alerts.")
                    }
                    Section("Native Location") {
                        Text(location.status)
                        Text("Native GPS is only shared with this HOS 150 web view while the app is in use. It does not automatically edit driving logs.")
                    }
                    Section("Safety") {
                        Text("HOS 150 is a prototype. It is not a certified ELD. Do not use the app or phone while driving.")
                    }
                }
                .navigationTitle("HOS 150")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { editSettings = false }
                    }
                }
            }
        }
    }

    private func unlock() {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            lockError = "Device authentication is unavailable. Use Safari to access your saved HOS records."
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock HOS 150 driver records") { success, err in
            DispatchQueue.main.async {
                unlocked = success
                lockError = success ? "" : (err?.localizedDescription ?? "Authentication unsuccessful")
            }
        }
    }

    private func approvedURL(_ text: String) -> Bool {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.user == nil, url.password == nil else { return false }
        return ["hos150.houseofsqueak.com", "squeak-server.tail7517d1.ts.net"].contains(url.host ?? "")
    }
    private func reload() {
        busy = true
        failure = nil
        webID = UUID()
    }
}

struct HOS150Browser: UIViewRepresentable {
    let address: String
    let location: HOSLocation
    let onStatus: (String?, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.allowsInlineMediaPlayback = true
        config.userContentController.add(context.coordinator, name: "hosAlert")
        // Protect WebView users even if an older service-worker shell is still cached.
        // This script changes only navigation and safe ELD entry-point UI, never log data.
        let hosMobileRepair = #"""
/* HOS150 V38.1 mobile repair: one Driver Hub and a visible, non-destructive ELD shortcut. */
(()=>{'use strict';
  function repairNav(){
    const nav=document.querySelector('body>nav');
    if(!nav)return;
    const buttons=Array.from(nav.querySelectorAll('button[data-tab="hub"]'));
    if(buttons.length<=1)return;
    // Keep the last listener-bearing button from any legacy dynamic Hub script.
    const keep=buttons[buttons.length-1];
    const wasSelected=buttons.some(button=>button.classList.contains('sel'));
    buttons.slice(0,-1).forEach(button=>button.remove());
    if(wasSelected)keep.classList.add('sel');
  }
  function showFreshForm(){
    const reset=document.getElementById('v38reset');
    const info=document.getElementById('hosFreshShortcutStatus');
    if(!reset){
      if(info)info.textContent='ELD log corrections are unavailable. Use Refresh and reconnect; your original log has not been changed.';
      return;
    }
    reset.click();
    if(info)info.textContent='Enter an accurate reason to archive and start a new prototype session. Original driving logs remain protected.';
  }
  function addFreshShortcut(){
    const log=document.getElementById('log');
    if(!log||document.getElementById('hosFreshShortcut'))return;
    const card=document.createElement('div');
    card.className='card';
    card.id='hosFreshShortcut';
    card.innerHTML='<h2>ELD Timer &amp; Session</h2>'+
      '<p class="muted">Start a new prototype session without erasing original driving records, corrections, or HOS history.</p>'+
      '<div class="row"><button id="hosFreshShortcutButton" type="button">START FRESH — KEEP HISTORY</button>'+
      '<button id="hosFreshRefreshButton" type="button" class="secondary">REFRESH ELD LOGS</button></div>'+
      '<p id="hosFreshShortcutStatus" class="muted">This is not a certified ELD or a legal hours-of-service reset.</p>';
    log.insertBefore(card,log.firstChild);
    document.getElementById('hosFreshShortcutButton').onclick=showFreshForm;
    document.getElementById('hosFreshRefreshButton').onclick=()=>{
      const refresh=document.getElementById('v38refresh');
      if(refresh)refresh.click();
      else document.getElementById('hosFreshShortcutStatus').textContent='Log refresh is unavailable. Saved duty records have not been changed.';
    };
  }
  function boot(){
    repairNav();addFreshShortcut();
    const nav=document.querySelector('body>nav');
    if(nav&&typeof MutationObserver!=='undefined'){
      const observer=new MutationObserver(repairNav);
      observer.observe(nav,{childList:true});
    }
    // A later legacy script may replace the controls during startup.
    setTimeout(()=>{repairNav();addFreshShortcut()},1000);
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});
  else boot();
})();

"""#
        config.userContentController.addUserScript(WKUserScript(source: hosMobileRepair, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        // Native fallback: never overwrite conflicting driver data; show an export-only recovery tool.
        let hosRecoveryAndHeader = #"""
document.documentElement.setAttribute('data-hos-native','true');
(()=>{if(!document.getElementById('hosNativeHeaderFix')){const st=document.createElement('style');st.id='hosNativeHeaderFix';st.textContent="/* HOS150 mobile header: separate app title, network state and GPS so they cannot overlap. */\nbody>header{display:grid!important;grid-template-columns:minmax(0,1fr) minmax(0,max-content)!important;align-items:start!important;gap:8px 10px!important;min-width:0!important}\nbody>header>div:first-child{grid-column:1/-1!important;min-width:0!important;max-width:100%!important}\nbody>header b{display:block!important;overflow-wrap:break-word!important;line-height:1.22!important}\nbody>header small{display:block!important;white-space:normal!important;line-height:1.45!important}\nbody>header>span{max-width:100%!important;min-width:0!important;overflow-wrap:break-word!important}\nbody>header #net{grid-column:1!important;grid-row:2!important;justify-self:start!important}\nbody>header #v37net{grid-column:2!important;grid-row:2!important;justify-self:end!important;text-align:right!important}\nbody>header #v37gps{grid-column:1/-1!important;grid-row:3!important;justify-self:end!important;text-align:right!important}\n@media(max-width:680px){\n body>header{padding:12px 13px!important}\n body>header b{font-size:clamp(16px,4.3vw,20px)!important;letter-spacing:.04em!important}\n body>header small{font-size:10px!important;letter-spacing:.035em!important}\n body>header #v37net{font-size:11px!important}\n html[data-hos-native=\"true\"] body>header{padding-top:66px!important}\n .hos-sync-recovery .row button{width:100%!important;white-space:normal!important;min-height:48px}\n}\n\n.hos-sync-recovery[hidden]{display:none!important}\n";document.head.appendChild(st)}})();
/* HOS150 V38.2: show sync conflicts without overwriting either record set. */
(()=>{'use strict';
if(window.__hos150SyncRecoveryUI)return;
window.__hos150SyncRecoveryUI=true;
const $=id=>document.getElementById(id);
let busy=false;
function summary(storage){
  try{
    const state=JSON.parse(storage?.hos150v13||'{}');
    return {dutyStatus:state.status||'Unknown',
      completedPeriods:Array.isArray(state.segments)?state.segments.length:0,
      events:Array.isArray(state.events)?state.events.length:0,
      corrections:Array.isArray(state.corrections)?state.corrections.length:0,
      archivedSessions:Array.isArray(state.sessionArchives)?state.sessionArchives.length:0};
  }catch{return {error:'Stored log cannot be parsed; raw backup is still included'}}
}
function message(s){
  for(const id of ['hosSyncRecoveryMessageLog','hosSyncRecoveryMessageSettings']){
    const el=$(id);if(el)el.textContent=s;
  }
}
function status(){
  const sync=window.HOS150ServerSync;
  try{return sync?.status?.()||{conflict:false,dirty:false}}catch{return {conflict:false,dirty:false}}
}
function refresh(){
  const s=status();
  for(const id of ['hosSyncRecoveryLog','hosSyncRecoverySettings']){
    const card=$(id);if(!card)continue;
    card.hidden=!s.conflict;
    const st=card.querySelector('.hos-sync-status');
    if(st)st.textContent=s.conflict?
      'Sync conflict: both copies are being preserved. Export them before making further log corrections.':
      'Local edits are waiting to sync. They have not been discarded.';
  }
}
async function exportBoth(){
  if(busy)return;busy=true;
  message('Preparing local and server backup without changing either...');
  try{
    const sync=window.HOS150ServerSync;
    if(!sync?.snapshot)throw Error('The local recovery snapshot is not available.');
    const local=sync.snapshot(),s=status();
    let server=null,serverError=null;
    try{
      const response=await fetch('/api/state',{cache:'no-store',credentials:'same-origin'});
      if(!response.ok)throw Error('Server returned HTTP '+response.status);
      const data=await response.json();
      server={exists:!!data.exists,updatedAt:data.updated_at,state:data.state||{}};
    }catch(e){serverError=String(e?.message||e)}
    const data={
      schema:'hos150-sync-recovery-v1',
      exportedAt:new Date().toISOString(),
      note:'PRIVATE DRIVER DATA. Archive both copies; do not overwrite one with the other without reviewing conflicting duty records.',
      syncStatus:s,
      phoneSummary:summary(local),
      serverSummary:server?summary(server.state):null,
      phoneSnapshot:local,
      serverSnapshot:server,
      serverError
    };
    const blob=new Blob([JSON.stringify(data,null,2)],{type:'application/json'});
    const url=URL.createObjectURL(blob),a=document.createElement('a');
    a.href=url;a.download='hos150-phone-and-server-recovery-'+new Date().toISOString().slice(0,10)+'.json';
    document.body.appendChild(a);a.click();a.remove();
    setTimeout(()=>URL.revokeObjectURL(url),30000);
    message(server?
      'Exported both versions. No log was changed. Review the backup before deciding how to reconcile.':
      'Exported the phone copy. Server could not be reached: '+serverError+'. Try again online.');
  }catch(e){message('Recovery export could not be created: '+String(e?.message||e)+'. Your records were not changed.')}
  finally{busy=false}
}
function card(id,msgId){
  const el=document.createElement('div');
  el.id=id;el.className='card hos-sync-recovery';el.hidden=true;
  el.innerHTML='<h2>Sync recovery — preserve both copies</h2>'+
    '<p class="hos-sync-status" role="status"></p>'+
    '<div class="status warn">Your phone and server may contain different driving records. The app will not automatically replace either copy.</div>'+
    '<div class="row"><button class="hos-export-copies" type="button">EXPORT PHONE + SERVER BACKUP</button></div>'+
    '<p class="muted" id="'+msgId+'">Only the export button runs here. No log or server state is modified.</p>';
  el.querySelector('.hos-export-copies').onclick=exportBoth;
  return el
}
function boot(){
  const log=$('log'),settings=$('settings');
  if(log&&!$('hosSyncRecoveryLog'))log.insertBefore(card('hosSyncRecoveryLog','hosSyncRecoveryMessageLog'),log.firstChild);
  if(settings&&!$('hosSyncRecoverySettings'))settings.insertBefore(card('hosSyncRecoverySettings','hosSyncRecoveryMessageSettings'),settings.firstChild);
  refresh();
  window.addEventListener('hos150:sync-conflict',refresh);
  window.addEventListener('hos150:sync-status',refresh);
  window.addEventListener('online',refresh);
  setInterval(refresh,5000);
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();

"""#
        config.userContentController.addUserScript(WKUserScript(source: hosRecoveryAndHeader, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        // iOS-only fallback: prevent fixed navigation from painting over recovery controls.
        let hosNativeFlow = #"""
(()=>{if(!document.getElementById('hosNativeFlow')){const st=document.createElement('style');st.id='hosNativeFlow';st.textContent="@media(max-width:760px){body>header,body>nav{position:relative!important;top:auto!important}body>header{z-index:1!important}body>nav{z-index:2!important;overflow-x:auto!important}html[data-hos-native=\"true\"] body>header:not(#unused){padding-top:12px!important}}";document.head.appendChild(st)}})();
"""#
        config.userContentController.addUserScript(WKUserScript(source: hosNativeFlow, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let hosSafeReconcileCore = #"""
/* HOS150 conservative same-history OFF DUTY reconciliation.
   No automatic driving edits, no duplicate segments, no deletion of audit history. */
(function(root,factory){
 const api=factory(); if(typeof module!=='undefined'&&module.exports)module.exports=api;
 if(root)root.HOS150SafeReconcile=api;
})(typeof window!=='undefined'?window:null,function(){
 'use strict';
 const eq=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
 const valid=x=>x&&typeof x==='object'&&!Array.isArray(x);
 const canonical=x=>JSON.stringify(x,Object.keys(x||{}).sort()); // entries may contain nested data
 function contains(longer,shorter){
   const available=longer.map(x=>JSON.stringify(x));
   for(const item of shorter){const i=available.indexOf(JSON.stringify(item));if(i<0)return false;available.splice(i,1);}
   return true;
 }
 function reconcile(phoneStorage,serverStorage,now=Date.now()){
   if(!valid(phoneStorage)||!valid(serverStorage))throw Error('Missing phone or server copy.');
   const phone=JSON.parse(phoneStorage.hos150v13||'{}'),server=JSON.parse(serverStorage.hos150v13||'{}');
   if(!valid(phone)||!valid(server))throw Error('Invalid saved driver record.');
   if(phone.status!=='OFF DUTY'||server.status!=='OFF DUTY')throw Error('One copy is not OFF DUTY. Preserve both records for review.');
   const keys=[new Set(Object.keys(phoneStorage)),new Set(Object.keys(serverStorage))];
   if(keys[0].size!==keys[1].size||[...keys[0]].some(k=>!keys[1].has(k)))throw Error('Other saved app records differ; both copies must be reviewed.');
   const merged={...serverStorage};
   for(const key of keys[0]){
     if(key==='hos150v13')continue;
     if(!eq(phoneStorage[key],serverStorage[key]))throw Error('Saved app records differ in '+key+'; both copies were preserved.');
   }
   const history=['segments','events','corrections','sessionArchives'];
   const state={...phone};
   for(const field of history){
     const a=phone[field]||[],b=server[field]||[];
     if(!Array.isArray(a)||!Array.isArray(b))throw Error('Invalid '+field+' records.');
     if(contains(a,b))state[field]=a;
     else if(contains(b,a))state[field]=b;
     else throw Error('Conflicting '+field+' history. No records were modified.');
   }
   const ignored=new Set([...history,'currentStart','pos','status']);
   const fields=new Set([...Object.keys(phone),...Object.keys(server)]);
   for(const field of fields)if(!ignored.has(field)){
     if(!eq(phone[field],server[field]))throw Error('Duty data differs in '+field+'. Preserving both copies for review.');
   }
   const starts=[phone.currentStart,server.currentStart].map(Number);
   if(starts.some(n=>!Number.isSafeInteger(n)||n<=0||n>now+60000))throw Error('Invalid OFF DUTY start time; review is needed.');
   // Choose the later OFF DUTY start to avoid overstating consecutive rest.
   state.currentStart=Math.max(...starts);
   state.status='OFF DUTY';
   state.pos=phone.pos||server.pos;
   merged.hos150v13=JSON.stringify(state);
   if(JSON.stringify(merged).length>=6500000)throw Error('Merged state exceeds safe storage budget.');
   return {state:merged,summary:{status:'OFF DUTY',start:state.currentStart,segments:state.segments.length,events:state.events.length,corrections:state.corrections.length,archives:state.sessionArchives.length}};
 }
 return {reconcile};
});

"""#
        config.userContentController.addUserScript(WKUserScript(source: hosSafeReconcileCore, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let hosSafeReconcileClient = #"""
/* HOS150: reconcile compatible OFF DUTY copies only, with separate backups. */
(()=>{'use strict';
if(window.__hos150ReconcilingLoaded)return;window.__hos150ReconcilingLoaded=true;
const $=id=>document.getElementById(id);
const MSG='hos150AutoReconcileStatus';
function note(msg,ok=false){
 let el=$(MSG);
 if(!el){const target=$('hosSyncRecoveryLog')||$('log');if(!target)return;el=document.createElement('p');el.id=MSG;el.className='status neutral';target.prepend(el);}
 el.textContent=msg;el.className='status '+(ok?'good':'warn');
}
let attempted=false;
async function run(){
 if(attempted)return;
 const sync=window.HOS150ServerSync,core=window.HOS150SafeReconcile;
 if(!sync?.status||!core?.reconcile)return;
 if(!sync.status().conflict)return;
 if(!navigator.onLine){note('Offline: both records are preserved. Reconciliation will retry when connected.');return;}
 attempted=true;
 note('Comparing your OFF DUTY records safely. Neither copy will be discarded.');
 try{
   const local=sync.snapshot();
   const response=await fetch('/api/state',{cache:'no-store',credentials:'same-origin'});
   if(!response.ok)throw Error('Server unavailable. No changes made.');
   const remote=await response.json();
   if(!remote.exists||!remote.state||remote.updated_at==null)throw Error('Server records unavailable. Use the recovery export.');
   const plan=core.reconcile(local,remote.state);
   const stamp=Date.now(),suffix=String(stamp);
   // These private recovery keys are excluded from outgoing synchronization.
   localStorage.setItem('hos150_local_recovery_'+suffix,JSON.stringify(local));
   localStorage.setItem('hos150_server_recovery_'+suffix,JSON.stringify(remote.state));
   if(JSON.stringify(sync.snapshot())!==JSON.stringify(local))throw Error('Phone records changed during comparison. Re-open recovery to review.');
   const put=await fetch('/api/state',{
      method:'PUT',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({state:plan.state,base_updated_at:remote.updated_at}),
      credentials:'same-origin',cache:'no-store'
   });
   if(put.status===409)throw Error('Server records changed during reconciliation. Both original copies were preserved.');
   if(!put.ok)throw Error('Reconciliation rejected (HTTP '+put.status+'). Original records preserved.');
   const saved=await put.json();
   const verifyRes=await fetch('/api/state',{cache:'no-store',credentials:'same-origin'});
   if(!verifyRes.ok)throw Error('Saved, but server verification unavailable; review status before retrying.');
   const verify=await verifyRes.json();
   if(verify.updated_at!==saved.updated_at||JSON.stringify(verify.state)!==JSON.stringify(plan.state))
      throw Error('Server verification mismatch. Recovery backups preserved.');
   if(JSON.stringify(sync.snapshot())!==JSON.stringify(local))throw Error('Phone records changed while saving; current phone records remain untouched, backups preserved.');
   for(const [key,value] of Object.entries(plan.state))localStorage.setItem(key,value);
   localStorage.setItem('hos150_last_server_version_v38',String(saved.updated_at));
   localStorage.removeItem('hos150_sync_pending_v38');
   localStorage.removeItem('hos150_sync_conflict_v38');
   sessionStorage.setItem('hos150_reconcile_completed','OFF DUTY records synchronized; earlier driving history preserved.');
   note('Phone and server now match. Original driving history preserved.',true);
   setTimeout(()=>location.reload(),650);
 }catch(e){
   note(String(e?.message||e)+' No records were intentionally overwritten. Use EXPORT PHONE + SERVER BACKUP for review.');
 }
}
window.HOS150ReconcileRun=run;
function boot(){
 const completed=sessionStorage.getItem('hos150_reconcile_completed');
 if(completed){sessionStorage.removeItem('hos150_reconcile_completed');note(completed,true);}
 setTimeout(()=>window.dispatchEvent(new Event('hos150:reconcile-ui-ready')),900);
 window.addEventListener('hos150:sync-conflict',()=>window.dispatchEvent(new Event('hos150:reconcile-ui-ready')));
 
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});
else boot();
})();

"""#
        config.userContentController.addUserScript(WKUserScript(source: hosSafeReconcileClient, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let hosSafeReconcileButton = #"""
/* User-triggered, guarded HOS150 conflict reconciliation. */
(()=>{'use strict';
if(window.__hos150ReconcileButtonInstalled)return;
window.__hos150ReconcileButtonInstalled=true;
function render(){
 const sync=window.HOS150ServerSync;
 if(!sync?.status?.().conflict)return;
 for(const id of ['hosSyncRecoveryLog','hosSyncRecoverySettings']){
  const card=document.getElementById(id);
  if(!card||card.querySelector('.hos-reconcile-button'))continue;
  const row=card.querySelector('.row');if(!row)continue;
  const button=document.createElement('button');
  button.type='button';button.className='hos-reconcile-button';
  button.textContent='RECONCILE OFF DUTY COPIES';
  button.onclick=()=>window.HOS150ReconcileRun?.();
  row.appendChild(button);
 }
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',render,{once:true});
else render();
window.addEventListener('hos150:reconcile-ui-ready',render);
window.addEventListener('hos150:sync-conflict',render);
})();

"""#
        config.userContentController.addUserScript(WKUserScript(source: hosSafeReconcileButton, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let hosNativeLiveCore = #"""
/* HOS150 V38 live ELD visualization: read-only, not a certified ELD. */
(function(root,factory){
 const api=factory();
 if(typeof module!=='undefined'&&module.exports)module.exports=api;
 if(root)root.HOS150LiveLogCore=api;
})(typeof window!=='undefined'?window:null,function(){
 'use strict';
 const TYPES=['OFF DUTY','SLEEPER','DRIVING','ON DUTY'];
 function safeTime(x){const n=Number(x);return Number.isFinite(n)&&n>0&&n<9e15?n:null}
 function dayWindow(value,now=Date.now()){
  if(value&&!(typeof value==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(value)))throw Error('Invalid log date');
  const date=(typeof value==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(value))?
    new Date(Number(value.slice(0,4)),Number(value.slice(5,7))-1,Number(value.slice(8,10))):new Date(now);
  if(!Number.isFinite(date.getTime()))throw Error('Invalid log date');
  date.setHours(0,0,0,0);
  const next=new Date(date);next.setDate(next.getDate()+1);
  return {start:date.getTime(),end:next.getTime(),date:date.toLocaleDateString()};
 }
 function derive(storage,date,now=Date.now()){
  const s=storage&&typeof storage==='object'?storage:{};
  const window=dayWindow(date,now),start=window.start,end=window.end;
  const status=TYPES.includes(s.status)?s.status:'UNKNOWN';
  const all=Array.isArray(s.segments)?s.segments:[];
  const segments=[];
  const add=(x,live=false)=>{
   if(!x||!TYPES.includes(x.status))return;
   const a=safeTime(x.start),b=safeTime(x.end);
   if(a===null||b===null||b<=a||a>=end||b<=start)return;
   segments.push({status:x.status,start:Math.max(a,start),end:Math.min(b,end),live});
  };
  all.forEach(x=>add(x,false));
  const current=safeTime(s.currentStart);
  if(current!==null&&now>current&&TYPES.includes(status))add({status,start:current,end:now},true);
  segments.sort((a,b)=>a.start-b.start);
  const events=(Array.isArray(s.events)?s.events:[])
    .filter(x=>x&&safeTime(Date.parse(x.time))!==null)
    .sort((a,b)=>Date.parse(b.time)-Date.parse(a.time)).slice(0,15)
    .map(x=>({time:Date.parse(x.time),status:TYPES.includes(x.status)?x.status:'EVENT',
      source:String(x.source||'Recorded').slice(0,80),note:String(x.note||'').slice(0,280)}));
  return {status,start:current,now,window,segments,events,
    duration:current!==null&&current<=now?now-current:null,
    totals:Object.fromEntries(TYPES.map(t=>[t,segments.filter(x=>x.status===t).reduce((n,x)=>n+x.end-x.start,0)]))};
 }
 return {TYPES,dayWindow,derive};
});

"""#
        config.userContentController.addUserScript(WKUserScript(source: hosNativeLiveCore, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let hosNativeLiveUI = #"""
/* HOS150 read-only live chart and latest duty-event panel. */
(()=>{'use strict';
if(window.__hos150LiveLogInstalled)return;
window.__hos150LiveLogInstalled=true;
const $=id=>document.getElementById(id);
const fmtTime=t=>new Date(t).toLocaleTimeString([],{hour:'numeric',minute:'2-digit'});
const fmtDuration=ms=>{
 if(ms===null||!Number.isFinite(ms))return 'Not started';
 const minutes=Math.floor(Math.max(0,ms)/60000);
 return Math.floor(minutes/60)+'h '+String(minutes%60).padStart(2,'0')+'m';
};
function el(tag,cls,text){
 const e=document.createElement(tag);
 if(cls)e.className=cls;
 if(text!==undefined)e.textContent=text;
 return e;
}
function getState(){try{return JSON.parse(localStorage.getItem('hos150v13')||'{}')}catch{return{}}}
function build(){
 const log=$('log'),old=$('logGrid');
 if(!log||!old||!window.HOS150LiveLogCore)return false;
 const graphCard=old.closest('.card');
 if(!graphCard)return false;
 let heading=$('hosLiveReadout');
 if(!heading){
   heading=el('div','hos-live-readout');heading.id='hosLiveReadout';
   graphCard.insertBefore(heading,old);
 }
 let graph=$('hosLiveGraph');
 if(!graph){
   graph=el('div','hos-live-graph');graph.id='hosLiveGraph';
   graphCard.insertBefore(graph,old);
 }
 let recent=$('hosLiveRecent');
 if(!recent){
   recent=el('div','card hos-live-recent');recent.id='hosLiveRecent';
   const h=el('h2','', 'Live Duty Log');
   const desc=el('p','muted','Most recent recorded duty events. Updates automatically while this screen is open.');
   const items=el('div','hos-live-event-list');items.id='hosLiveEvents';
   recent.append(h,desc,items);
 }
 if(log.firstElementChild!==graphCard)log.insertBefore(graphCard,log.firstElementChild);
 if(graphCard.nextElementSibling!==recent)log.insertBefore(recent,graphCard.nextElementSibling);
 // The legacy display continues receiving events, but the reliable chart is the
 // visible one. Never remove the original log, original event table or its data.
 old.style.display='none';
 return true;
}
function render(){
 if(!build())return;
 const core=window.HOS150LiveLogCore;
 const date=$('logDate')?.value||'',data=core.derive(getState(),date,Date.now());
 const heading=$('hosLiveReadout'),graph=$('hosLiveGraph'),events=$('hosLiveEvents');
 if(!heading||!graph||!events)return;
 heading.replaceChildren();
 const status=el('div','hos-live-status',data.status);
 const timer=el('div','hos-live-timer',data.start?'Since '+fmtTime(data.start)+' • '+fmtDuration(data.duration):'No running timer');
 const sync=window.HOS150ServerSync?.status?.();
 const hint=el('div','hos-live-hint',(sync?.conflict?'Sync conflict — local record shown':sync?.dirty?'Changes waiting to sync':'Local saved duty record')+' • '+data.window.date);
 heading.append(status,timer,hint);
 graph.replaceChildren();
 const hours=el('div','hos-live-hours');
 const left=el('span','hos-axis-empty','');
 hours.appendChild(left);
 for(let h=0;h<=24;h+=3)hours.appendChild(el('span','',String(h).padStart(2,'0')));
 graph.appendChild(hours);
 const length=data.window.end-data.window.start;
 for(const name of core.TYPES){
   const row=el('div','hos-live-lane');
   const tag=el('span','hos-live-lane-title',name==='OFF DUTY'?'OFF':name==='SLEEPER'?'SB':name==='DRIVING'?'D':'ON');
   const track=el('div','hos-live-track');
   for(const seg of data.segments.filter(x=>x.status===name)){
      const bar=el('div','hos-live-bar '+name.replace(' ','-').toLowerCase());
      bar.style.left=((seg.start-data.window.start)/length*100)+'%';
      bar.style.width=(Math.max(0.1,(seg.end-seg.start)/length*100))+'%';
      bar.title=name+' • '+fmtTime(seg.start)+' to '+fmtTime(seg.end)+(seg.live?' (current)':'');
      track.appendChild(bar);
   }
   row.append(tag,track);graph.appendChild(row);
 }
 const legend=el('div','hos-live-legend','Graph shows recorded duty periods for the selected day • Running status updates live');
 graph.appendChild(legend);
 events.replaceChildren();
 if(!data.events.length){
   events.appendChild(el('p','muted','No recorded duty events yet. Current status appears in the graph above.'));
 }else for(const event of data.events){
   const row=el('div','hos-live-event');
   row.append(
     el('span','hos-live-event-time',new Date(event.time).toLocaleString([], {month:'numeric',day:'numeric',hour:'numeric',minute:'2-digit'})),
     el('span','hos-live-event-status',event.status),
     el('span','hos-live-event-note',(event.note||event.source)+' • '+event.source)
   );
   events.appendChild(row);
 }
}
function boot(){
 if(!build())return;
 const date=$('logDate');
 if(date)date.addEventListener('change',render);
 const nav=document.querySelector('body>nav');
 if(nav)nav.addEventListener('click',e=>{
   if(e.target.closest('[data-tab="log"]'))setTimeout(render,170);
 });
 window.addEventListener('hos150:state-updated',render);
 window.addEventListener('hos150:sync-status',render);
 render();
 setTimeout(render,1000);
 setInterval(()=>{if($('log')?.classList.contains('active'))render()},2000);
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});
else boot();
})();

"""#
        config.userContentController.addUserScript(WKUserScript(source: hosNativeLiveUI, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let hosNativeLiveCSS = #"""
(()=>{if(!document.getElementById('hosNativeLiveStyle')){const s=document.createElement('style');s.id='hosNativeLiveStyle';s.textContent="/* HOS150 live ELD graph & event log: dedicated read-only display */\n.hos-live-readout{display:flex;align-items:center;flex-wrap:wrap;gap:8px 16px;margin:12px 0 14px}\n.hos-live-status{font-weight:900;font-size:17px;color:#a3f5fc}\n.hos-live-timer{font-weight:750;font-size:14px;color:#fff}\n.hos-live-hint{font-size:12px;color:#9bb6cf;flex-basis:100%}\n.hos-live-graph{width:100%;overflow:hidden;border:1px solid #31556a;border-radius:12px;background:#091827;padding:12px 10px;min-height:246px}\n.hos-live-hours,.hos-live-lane{display:grid;grid-template-columns:36px minmax(0,1fr);align-items:center}\n.hos-live-hours{grid-template-columns:36px repeat(9,minmax(0,1fr));margin-bottom:10px;color:#bed6e8;font-size:10px;text-align:center}\n.hos-live-lane{min-height:42px;margin:4px 0}\n.hos-live-lane-title{font-size:11px;font-weight:900;color:#d9e8f7}\n.hos-live-track{height:34px;position:relative;overflow:hidden;border:1px solid #2a4b62;border-radius:5px;background:repeating-linear-gradient(90deg,#122b42,#122b42 calc(12.5% - 1px),#35506a calc(12.5% - 1px),#35506a 12.5%)}\n.hos-live-bar{height:70%;top:15%;position:absolute;min-width:2px;border-radius:4px}\n.hos-live-bar.off-duty{background:#60d9ef}.hos-live-bar.sleeper{background:#5e92ff}.hos-live-bar.driving{background:#ffbc5c}.hos-live-bar.on-duty{background:#41e3a4}\n.hos-live-legend{font-size:11px;color:#a6c0d9;margin-top:12px;line-height:1.4}\n.hos-live-event-list{display:grid;gap:8px}\n.hos-live-event{display:grid;grid-template-columns:minmax(82px,auto) minmax(75px,auto) 1fr;gap:8px;align-items:start;background:#0b2033;border:1px solid #25506d;border-radius:9px;padding:10px;color:#e5f4ff;font-size:12px;overflow-wrap:anywhere}\n.hos-live-event-time{color:#a5bdd0}.hos-live-event-status{font-weight:900}.hos-live-event-note{color:#d7e3ed}\n@media(max-width:650px){.hos-live-event{grid-template-columns:1fr 1fr}.hos-live-event-note{grid-column:1/-1}.hos-live-graph{padding:10px 7px}.hos-live-readout{gap:6px 12px}}\n";document.head.appendChild(s)}})();
"""#
        config.userContentController.addUserScript(WKUserScript(source: hosNativeLiveCSS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let hosNativeV39Core = #"""
/* HOS150 V39 read-only cockpit calculations, not a certified ELD. */
(function(root,factory){
 const api=factory();
 if(typeof module!=='undefined'&&module.exports)module.exports=api;
 if(root)root.HOS150V39Core=api;
})(typeof window!=='undefined'?window:null,function(){
 'use strict';
 const H=3600000,MIN=60000;
 const DUTIES=new Set(['OFF DUTY','SLEEPER','ON DUTY','DRIVING']);
 const finiteTime=n=>Number.isFinite(Number(n))&&Number(n)>0?Number(n):null;
 function clock(ms){
   if(ms===null||!Number.isFinite(ms))return '—';
   const minutes=Math.floor(Math.max(0,ms)/MIN);
   return String(Math.floor(minutes/60)).padStart(2,'0')+':'+String(minutes%60).padStart(2,'0');
 }
 function model(raw,now=Date.now()){
   const s=raw&&typeof raw==='object'?raw:{};
   const ts=Number(now);
   if(!Number.isFinite(ts)||ts<=0)throw Error('Invalid clock time');
   const status=DUTIES.has(s.status)?s.status:'UNKNOWN';
   const shift=finiteTime(s.shiftStart),active=finiteTime(s.currentStart);
   const start=shift&&shift<=ts?shift:null;
   let error=false;
   const items=[];
   if(start){
     for(const entry of Array.isArray(s.segments)?s.segments:[]){
       if(!entry||!DUTIES.has(entry.status))continue;
       const a=finiteTime(entry.start),b=finiteTime(entry.end);
       if(!a||!b||b<=a){error=true;continue}
       if(b<=start||a>=ts)continue;
       items.push({status:entry.status,start:Math.max(start,a),end:Math.min(ts,b)});
     }
     if(active&&active<=ts&&DUTIES.has(status))items.push({status,start:Math.max(active,start),end:ts});
   }
   items.sort((a,b)=>a.start-b.start||a.end-b.end);
   let cursor=start,driving=0,sinceBreak=0,nonDriving=0;
   for(const entry of items){
     if(entry.start<cursor-1000){error=true;continue}
     if(entry.start>cursor+1000)error=true; // Gaps cannot be assumed to be breaks.
     const span=Math.max(0,entry.end-entry.start);
     cursor=Math.max(cursor,entry.end);
     if(entry.status==='DRIVING'){
       driving+=span;sinceBreak+=span;nonDriving=0;
     }else{
       nonDriving+=span;
       if(nonDriving>=30*MIN)sinceBreak=0;
     }
   }
   if(start&&cursor<ts-1000)error=true;
   // Do not present optimistic clocks if the input history contains gaps or overlaps.
   const drivingLeft=start&&!error?Math.max(0,11*H-driving):null;
   const windowLeft=start?Math.max(0,14*H-(ts-start)):null;
   const breakLeft=start&&!error?Math.max(0,8*H-sinceBreak):null;
   const base=s.cycleRemaining==null?null:Number(s.cycleRemaining);
   const cycleBase=base!==null&&Number.isFinite(base)&&base>=0?base:null;
   const cycleLeft=start&&!error&&cycleBase!==null?Math.max(0,cycleBase*H-driving-items.filter(x=>x.status==='ON DUTY').reduce((n,x)=>n+x.end-x.start,0)):null;
   const loads=Array.isArray(s.loads)?s.loads:[];
   const next=loads.find(x=>x&&typeof x==='object'&&x.status!=='completed'&&x.delivered!==true);
   const destination=next?.delivery||next?.destination||s.routeEnd||'No active destination';
   const gps=s.pos&&Number.isFinite(Number(s.pos.lat))&&Number.isFinite(Number(s.pos.lon))?'GPS recorded':'GPS not available';
   const messages=[];
   if(!start)messages.push('Start shift to calculate HOS estimates.');
   if(error)messages.push('Incomplete or overlapping duty history: review the log.');
   if(windowLeft!==null&&windowLeft<=30*MIN)messages.push('14-hour window is low; verify applicability.');
   if(drivingLeft!==null&&drivingLeft<=30*MIN)messages.push('Driving-time estimate is low.');
   if(breakLeft!==null&&breakLeft<=30*MIN)messages.push('Check 30-minute break requirements and exemptions.');
   const nextStatus=status==='UNKNOWN'?'Duty status unknown':status;
   return {status:nextStatus,shiftStarted:!!start,historyReliable:!error,
      drivingLeft,windowLeft,breakLeft,cycleLeft,
      drivingUsed:!error&&start?driving:null,
      destination:String(destination).slice(0,120),gps,
      syncSensitive:true,messages,clock,counts:{records:items.length,events:Array.isArray(s.events)?s.events.length:0}};
 }
 return {model,clock};
});

"""#
        config.userContentController.addUserScript(WKUserScript(source: hosNativeV39Core, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let hosNativeV39UI = #"""
/* HOS150 V39 Driver Cockpit — display-only; legacy duty buttons remain authoritative. */
(()=>{'use strict';
if(window.__hos150V39Cockpit)return;
window.__hos150V39Cockpit=true;
const $=id=>document.getElementById(id);
const dom=(tag,cls,id)=>{
 const el=document.createElement(tag);
 if(cls)el.className=cls;
 if(id)el.id=id;
 return el;
};
function navigate(tab){
 const button=document.querySelector('body>nav button[data-tab="'+tab+'"]');
 if(button)button.click();
 else {const msg=$('v39Notice');if(msg)msg.textContent='The '+tab+' screen is unavailable; duty records were not changed.'}
}
function repairNav(){
 const nav=document.querySelector('body>nav');
 if(!nav)return;
 const seen=new Map();
 for(const button of [...nav.querySelectorAll('button[data-tab]')].reverse()){
   const key=button.dataset.tab;
   if(!key)continue;
   if(seen.has(key)){
      if(button.classList.contains('sel'))seen.get(key).classList.add('sel');
      button.remove();
   }else seen.set(key,button);
 }
}
function build(){
 const home=$('home');
 if(!home||!window.HOS150V39Core)return false;
 if($('v39Cockpit'))return true;
 const frame=dom('section','v39-cockpit card','v39Cockpit');
 frame.setAttribute('aria-label','V39 Driver Cockpit');
 const eyebrow=dom('div','v39-eyebrow');eyebrow.textContent='V39 • DRIVER COCKPIT';
 const title=dom('h2','v39-title');title.textContent='Ready for the road';
 const sub=dom('p','v39-subtitle');sub.textContent='Live duty guidance • local records • one-tap tools';
 const head=dom('div','v39-heading');
 head.append(eyebrow,title,sub);
 const status=dom('div','v39-status','v39Status');status.setAttribute('aria-live','polite');
 frame.append(head,status);
 const grid=dom('div','v39-clocks');
 for(const [key,label] of [['Driving','11-hour driving'],['Window','14-hour window'],['Break','8-hour break check'],['Cycle','Cycle • manual']]){
    const card=dom('div','v39-clock');
    const t=dom('div','v39-clock-label');t.textContent=label;
    const value=dom('strong','v39-clock-value','v39'+key);value.textContent='—';
    card.append(t,value);grid.appendChild(card);
 }
 frame.appendChild(grid);
 const details=dom('div','v39-details');
 for(const [key,label] of [['Destination','Next stop'],['GPS','Location'],['Sync','Phone / server']]){
    const item=dom('div','v39-detail');
    const t=dom('span','v39-detail-label');t.textContent=label;
    const v=dom('b','v39-detail-value','v39'+key);v.textContent='—';
    item.append(t,v);details.appendChild(item);
 }
 frame.appendChild(details);
 const actions=dom('div','v39-actions');
 for(const [key,label] of [['log','View live log'],['compliance','HOS planner'],['dispatch','Dispatch'],['route','Navigation']]){
    const button=dom('button','v39-action');
    button.type='button';button.dataset.target=key;
    button.textContent=label;
    button.addEventListener('click',()=>navigate(key));
    actions.appendChild(button);
 }
 frame.appendChild(actions);
 const notice=dom('p','v39-notice','v39Notice');
 notice.setAttribute('role','status');
 frame.appendChild(notice);
 const foot=dom('p','v39-legal');
 foot.textContent='Prototype estimates only. Not a registered ELD or legal HOS determination. Verify driving limits, exemptions and records.';
 frame.appendChild(foot);
 home.insertBefore(frame,home.firstChild);
 return true;
}
function render(){
 if(!build())return;
 const read=()=>{
   try{return JSON.parse(localStorage.getItem('hos150v13')||'{}')}
   catch{return null}
 };
 const state=read(),sync=window.HOS150ServerSync?.status?.();
 const n=$('v39Notice');
 if(!state){n.textContent='Local records cannot be read; no calculations shown.';return}
 const m=window.HOS150V39Core.model(state);
 const clock=window.HOS150V39Core.clock;
 for(const [key,value] of [['Driving',m.drivingLeft],['Window',m.windowLeft],['Break',m.breakLeft],['Cycle',m.cycleLeft]]){
   const field=$('v39'+key);if(field)field.textContent=value===null?'—':clock(value);
 }
 $('v39Status').textContent='Duty: '+m.status+(m.shiftStarted?'':' • shift not started');
 $('v39Destination').textContent=m.destination;
 $('v39GPS').textContent=m.gps;
 $('v39Sync').textContent=sync?.conflict?'Conflict — export backup':sync?.dirty?'Saved locally • sync pending':navigator.onLine?'Online • records saved':'Offline • records saved';
 n.textContent=m.messages.join(' ')||(m.shiftStarted?'Advisory clocks updating; verify your logs.':'No shift started.');
 $('v39Cockpit').dataset.warning=(sync?.conflict||m.messages.length)?'true':'false';
}
function boot(){
 if(!build())return;
 repairNav();
 const nav=document.querySelector('body>nav');
 if(nav&&typeof MutationObserver!=='undefined'){
   new MutationObserver(repairNav).observe(nav,{childList:true});
 }
 render();
 window.addEventListener('hos150:state-updated',render);
 window.addEventListener('hos150:sync-status',render);
 window.addEventListener('storage',event=>{if(event.key==='hos150v13')render()});
 document.addEventListener('visibilitychange',()=>{if(!document.hidden)render()});
 setInterval(()=>{if($('home')?.classList.contains('active'))render()},10000);
 setTimeout(()=>{repairNav();render()},1100);
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();

"""#
        config.userContentController.addUserScript(WKUserScript(source: hosNativeV39UI, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let hosNativeV39Style = #"""
(()=>{if(!document.getElementById('hosNativeV39Style')){const s=document.createElement('style');s.id='hosNativeV39Style';s.textContent="/* HOS150 V39 mobile-first, readable Driver Cockpit. */\n#v39Cockpit{background:linear-gradient(145deg,#101f35,#0a1625)!important;color:#f1f8ff!important;border:1px solid #2e779e!important;border-radius:20px!important;padding:16px!important;margin:10px 0 15px!important;box-shadow:0 12px 24px #00101d8c!important}\n.v39-eyebrow{font-size:11px;font-weight:900;letter-spacing:.16em;color:#69dff6}\n.v39-title{font-size:clamp(24px,6vw,33px)!important;line-height:1.16;margin:8px 0 3px!important;font-weight:900!important;letter-spacing:-.015em!important;color:#fff!important}\n.v39-subtitle,.v39-legal{font-size:12px;color:#adcadf;line-height:1.5}\n.v39-status{font-size:14px;font-weight:850;color:#6df2c8;margin:10px 0 12px}\n.v39-clocks{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:9px}\n.v39-clock{background:#172b45;border:1px solid #355d7c;border-radius:14px;padding:14px 11px;min-width:0}\n.v39-clock-label{font-weight:750;font-size:11px;line-height:1.3;color:#afcbe0;letter-spacing:.02em}\n.v39-clock-value{display:block;font-weight:900;font-variant-numeric:tabular-nums;font-size:clamp(24px,6vw,35px);color:#fff;line-height:1.3;margin-top:5px}\n.v39-details{display:grid;gap:8px;margin:12px 0}\n.v39-detail{display:grid;grid-template-columns:92px minmax(0,1fr);align-items:center;gap:6px;background:#0f263e;border:1px solid #244964;border-radius:10px;padding:10px}\n.v39-detail-label{font-size:11px;color:#acc6db}.v39-detail-value{font-size:13px;overflow-wrap:anywhere;color:#eef9ff}\n.v39-actions{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}\n#v39Cockpit button.v39-action{background:#1b4463!important;border:1px solid #3983a8!important;color:#fff!important;border-radius:10px!important;padding:12px 6px!important;min-height:48px!important;font-size:13px!important;font-weight:800!important;white-space:normal!important}\n#v39Cockpit button.v39-action:focus-visible{outline:3px solid #7ae8fa;outline-offset:2px}\n.v39-notice{color:#f4d18b;font-size:12px;font-weight:720;line-height:1.5;margin:11px 0 0}\n#v39Cockpit[data-warning=true] .v39-status{color:#ffcd8d}\n.v39-legal{margin:10px 0 0}\nbody>nav{scrollbar-width:thin}\n@media(max-width:760px){\n body>header,body>nav{position:relative!important;top:auto!important}\n body>nav{display:flex!important;flex-wrap:nowrap!important;max-width:100vw!important;overflow-x:auto!important;overscroll-behavior-x:contain}\n body>nav button[data-tab]{flex:0 0 auto!important;min-height:42px}\n #v39Cockpit{padding:13px!important}\n main{padding:9px!important}\n}\n@media(max-width:355px){.v39-clocks{gap:6px}.v39-clock{padding:11px 8px}.v39-detail{grid-template-columns:70px minmax(0,1fr)}}\n";document.head.appendChild(s)}})();
"""#
        config.userContentController.addUserScript(WKUserScript(source: hosNativeV39Style, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        // SideStore already installs HOS150: suppress leftover install banners from cached web shells.
        let hosNativeNoInstall = #"""
(()=>{'use strict';const hide=()=>{const b=document.getElementById('pwaInstall');if(b)b.remove()};if(!document.getElementById('hosNativeNoInstallStyle')){const st=document.createElement('style');st.id='hosNativeNoInstallStyle';st.textContent='#pwaInstall{display:none!important}';(document.head||document.documentElement).appendChild(st)}hide();new MutationObserver(hide).observe(document.documentElement,{childList:true,subtree:true});})();
"""#
        config.userContentController.addUserScript(WKUserScript(source: hosNativeNoInstall, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let hosNativeNavBridge = #"""
/* HOS150 V39.2 navigation bridge: car navigation apps only; no truck-safe claims. */
(function(root,fn){const api=fn();if(typeof module!=='undefined'&&module.exports)module.exports=api;if(root)root.HOS150NavBridge=api;})(typeof window!=='undefined'?window:null,function(){
 'use strict';
 function normalize(value){
   const raw=String(value??'').trim().replace(/\s+/g,' ');
   if(!raw||raw.length>250)throw Error('Enter a destination under 250 characters.');
   if(/[\u0000-\u001f\u007f]/.test(raw))throw Error('Invalid destination characters.');
   return raw;
 }
 function coords(value){
  const match=normalize(value).match(/^(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)$/);
  if(!match)return null;
  const lat=Number(match[1]),lon=Number(match[2]);
  if(!Number.isFinite(lat)||!Number.isFinite(lon)||Math.abs(lat)>90||Math.abs(lon)>180)throw Error('Invalid GPS coordinates.');
  return {lat,lon};
 }
 function urls(value){
  const address=normalize(value),geo=coords(address),q=encodeURIComponent(address);
  return {
    apple:'https://maps.apple.com/?daddr='+q+'&dirflg=d',
    waze:'https://waze.com/ul?'+(geo?'ll='+encodeURIComponent(geo.lat+','+geo.lon):'q='+q)+'&navigate=yes&utm_source=com.houseofsqueak.hos150'
  };
 }
 return {normalize,coords,urls};
});

"""#
        config.userContentController.addUserScript(WKUserScript(source: hosNativeNavBridge, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let hosNativeNavUI = #"""
/* HOS150 V39.2 Navigation: minimal map + explicit native app hand-off.
   Apple Maps and Waze provide car routing; not truck-cleared routes. */
(()=>{'use strict';
if(window.__hos150CleanNav)return;window.__hos150CleanNav=true;
const $=id=>document.getElementById(id);
let map=null,marker=null,gpsMarker=null,lastFix=null,lastPinned=null;
function status(t){const x=$('n39status');if(x)x.textContent=t;}
function selection(){
 const text=$('n28dest')?.value?.trim()||'';
 const apple=$('n39apple'),waze=$('n39waze');
 try{
   const urls=window.HOS150NavBridge.urls(text);
   apple.href=urls.apple;waze.href=urls.waze;
   return text;
 }catch{
   apple?.removeAttribute('href');waze?.removeAttribute('href');return '';
 }
}
function stop(e){
 if(!selection()){e.preventDefault();status('Enter an address or GPS coordinates first.');$('n28dest')?.focus();}
}
function initializeMap(){
 if(map||!window.L||!$('n39map'))return;
 map=L.map('n39map',{zoomControl:false,preferCanvas:true}).setView([39.8,-96.2],4);
 L.control.zoom({position:'bottomright'}).addTo(map);
 L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:19,attribution:'© OpenStreetMap contributors'}).addTo(map);
 setTimeout(()=>map?.invalidateSize(),150);
}
function place(lat,lon,zoom=14){
 if(!map)return;
 if(!marker)marker=L.marker([lat,lon]).addTo(map);
 else marker.setLatLng([lat,lon]);
 map.setView([lat,lon],zoom);
 lastPinned={lat,lon};
}
async function preview(){
 const text=selection();if(!text)return status('Enter a destination.');
 const c=window.HOS150NavBridge.coords(text);
 if(c){place(c.lat,c.lon);status('Destination located. Choose Apple Maps or Waze to start directions.');return}
 status('Looking up destination for map preview…');
 try{
  const r=await fetch('https://nominatim.openstreetmap.org/search?format=jsonv2&limit=1&q='+encodeURIComponent(text),{headers:{Accept:'application/json'}});
  if(!r.ok)throw Error('Search unavailable');
  const j=await r.json();const p=j[0];
  if(!p)throw Error('No match; check address.');
  place(Number(p.lat),Number(p.lon));
  status('Pinned: '+String(p.display_name||text).slice(0,130));
 }catch(e){status((e?.message||'Preview unavailable')+'. Apple Maps or Waze can still search the address.')}
}
function currentLocation(){
 if(!navigator.geolocation)return status('GPS is not available on this device.');
 status('Finding your location…');
 navigator.geolocation.getCurrentPosition(p=>{
  lastFix={lat:p.coords.latitude,lon:p.coords.longitude,accuracy:p.coords.accuracy};
  if(map){if(!gpsMarker)gpsMarker=L.circleMarker([lastFix.lat,lastFix.lon],{radius:7,color:'#fff',weight:3,fillColor:'#25b5f7',fillOpacity:1}).addTo(map);else gpsMarker.setLatLng([lastFix.lat,lastFix.lon]);map.setView([lastFix.lat,lastFix.lon],15);}
  status('GPS located (±'+Math.round(lastFix.accuracy)+' m). Enter a destination to navigate.');
 },()=>status('GPS permission unavailable. Enter a destination manually.'),{enableHighAccuracy:true,timeout:12000,maximumAge:15000});
}
function build(){
 const section=$('route');if(!section||!window.HOS150NavBridge)return;
 section.className='screen n39-route';
 section.replaceChildren();
 const top=document.createElement('section');
 top.className='n39-nav-top';
 top.innerHTML='<h2>Navigation</h2><p>Simple map and destination search</p>'+
  '<label for="n28dest">Destination</label><input id="n28dest" inputmode="search" autocomplete="street-address" placeholder="Street address, city or GPS coordinates"/>'+
  '<div class="n39-row"><button type="button" id="n28go">PREVIEW ON MAP</button><button type="button" id="n39here">MY LOCATION</button></div>'+
  '<p class="n39-status" id="n39status" role="status">Enter a destination or open a saved customer address.</p>';
 section.appendChild(top);
 const mapBox=document.createElement('div');mapBox.className='n39-map';mapBox.id='n39map';section.appendChild(mapBox);
 const panel=document.createElement('section');panel.className='n39-handoff';
 panel.innerHTML='<h3>Start guided navigation</h3><div class="n39-actions">'+
   '<a id="n39apple" role="button" class="n39-action" rel="noopener">Apple Maps</a>'+
   '<a id="n39waze" role="button" class="n39-action" rel="noopener">Waze</a></div>'+
   '<p class="n39-warning">Important: Apple Maps and Waze calculate car routes. Neither checks your truck height, width, weight or restricted roads. Verify the route with an appropriate truck-specific source and obey posted restrictions.</p>';
 section.appendChild(panel);
 const i=$('n28dest');i?.addEventListener('input',selection);i?.addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();preview()}});
 $('n28go').onclick=preview;$('n39here').onclick=currentLocation;
 $('n39apple').addEventListener('click',stop);$('n39waze').addEventListener('click',stop);
 initializeMap();
}
function boot(){
 build();
 const nav=document.querySelector('body>nav');
 nav?.addEventListener('click',e=>{
  if(e.target?.closest?.('[data-tab="route"]'))setTimeout(()=>{if(!$('n39map')){map?.remove();map=null;marker=null;gpsMarker=null;build()}map?.invalidateSize()},220);
 });
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();

"""#
        config.userContentController.addUserScript(WKUserScript(source: hosNativeNavUI, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let hosNativeNavStyle = #"""
(()=>{if(!document.getElementById('hosNavStyleV39')){const s=document.createElement('style');s.id='hosNavStyleV39';s.textContent="/* V39.2 clean navigation UI: no simulated truck-routing claims. */\n#route.n39-route{background:#071521!important;color:#eaf7ff!important;padding:0!important;border-radius:17px;overflow:hidden}\n.n39-nav-top{padding:18px 15px 12px;background:linear-gradient(130deg,#112c49,#0a182c)}\n.n39-nav-top h2{color:#fff;font-size:26px;line-height:1.1;margin:0}\n.n39-nav-top p{color:#b5cfdf;margin:5px 0 14px;font-size:13px}\n.n39-nav-top label{display:block;font-size:12px;color:#b9d2e4;margin-bottom:5px}\n#route #n28dest{display:block;width:100%;min-height:54px;padding:12px 14px;border-radius:12px;background:#fff;color:#10213a;font-size:16px;border:2px solid #6bd5f1}\n.n39-row,.n39-actions{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;margin-top:11px}\n#route .n39-row button{min-height:49px;border:1px solid #3a83a8;background:#163c5c;color:#fff;border-radius:12px;font-weight:850;font-size:13px;white-space:normal}\n.n39-status{min-height:22px;font-size:12px;line-height:1.4;overflow-wrap:anywhere}\n.n39-map{height:min(43vh,390px);min-height:230px;background:#16283c}\n.n39-handoff{padding:13px 15px 18px;background:#0c1e31}\n.n39-handoff h3{font-size:17px;color:#fff;margin:2px 0 4px}\n.n39-action{display:flex;align-items:center;justify-content:center;min-height:55px;background:#1a5c83;color:#fff!important;border:1px solid #61c4e3;border-radius:13px;font-size:16px;font-weight:900;text-decoration:none!important;line-height:1.2;text-align:center}\n.n39-action:focus-visible{outline:3px solid #b0efff}\n.n39-warning{margin:13px 0 0;padding:11px 13px;background:#442f15;color:#ffe4a0;border-radius:11px;font-size:12px;line-height:1.48;border:1px solid #886b2d}\n@media(max-width:430px){.n39-nav-top{padding:13px 11px 9px}.n39-handoff{padding:12px 11px 16px}.n39-map{height:32vh;min-height:225px}#route .n39-row button{font-size:12px}}\n";document.head.appendChild(s)}})();
"""#
        config.userContentController.addUserScript(WKUserScript(source: hosNativeNavStyle, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = UIColor(red: 0.035, green: 0.055, blue: 0.085, alpha: 1)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        location.webView = view
        context.coordinator.onStatus = onStatus
        if let url = URL(string: address), url.scheme == "https",
           ["hos150.houseofsqueak.com", "squeak-server.tail7517d1.ts.net"].contains(url.host ?? "") {
            context.coordinator.appHost = url.host ?? ""
            view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25))
        } else {
            DispatchQueue.main.async { onStatus("Invalid server URL", true) }
        }
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        location.webView = view
        context.coordinator.onStatus = onStatus
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "hosAlert",
                  message.frameInfo.securityOrigin.host == appHost,
                  UserDefaults.standard.bool(forKey: "hos150Reminders"),
                  let payload = message.body as? [String: Any],
                  let warning = payload["message"] as? String,
                  warning.count < 180 else { return }
            let content = UNMutableNotificationContent()
            content.title = "HOS 150 • Review your clocks"
            content.body = warning
            content.sound = .default
            let request = UNNotificationRequest(identifier: "hos150-advisory", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }

        var appHost = ""
        var onStatus: ((String?, Bool) -> Void)?

        func webView(_ webView: WKWebView, didStartProvisionalNavigation nav: WKNavigation!) {
            onStatus?("Connecting to secure HOS 150…", false)
        }
        func webView(_ webView: WKWebView, didFinish nav: WKNavigation!) {
            onStatus?(nil, false)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation nav: WKNavigation!, withError error: Error) {
            fail(error)
        }
        func webView(_ webView: WKWebView, didFail nav: WKNavigation!, withError error: Error) {
            fail(error)
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            onStatus?("The web view stopped. Tap Retry.", true)
        }
        private func fail(_ error: Error) {
            let e = error as NSError
            if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return }
            onStatus?("\(e.localizedDescription) (error \(e.code))", true)
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            let host = url.host ?? ""
            let allowed = url.scheme == "https" &&
                (host == appHost || host == accessLoginHost)
            if allowed {
                decisionHandler(.allow)
            } else if url.scheme == "https" && action.navigationType == .linkActivated {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else if url.scheme == "tel" || url.scheme == "maps" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.cancel)
            }
        }
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            // iOS app permissions also apply, and requests must come from HOS.
            decisionHandler(origin.host == appHost ? .prompt : .deny)
        }
    }
}

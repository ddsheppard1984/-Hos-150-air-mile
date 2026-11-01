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

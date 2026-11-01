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
            view.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 25))
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

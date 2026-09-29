import Foundation
import Combine
import MicodexCore

/// Watch presentation state for the paired, authenticated Wi-Fi connection.
@MainActor
final class WatchLink: ObservableObject {
    @Published var connected = false
    @Published var status = L10n.t("Connecting to your Mac…")
    @Published var phase: HostPhase = .ready
    @Published var macName = "Mac"
    @Published var demo = false
    @Published var pairingCode: String?
    @Published var microphoneLevel = ""
    @Published var stopping = false
    @Published var microphoneReady = false
    @Published var focusedThreadTitle: String?
    @Published var recordingNotice: String?
    @Published var recordingRequested = false
    @Published var macAddress = ""
    var canUseWiFi: Bool { WatchWiFiConnection.configuration != nil }
    private var wifi: WatchWiFiConnection?
    private var observer: AnyCancellable?
    private var active = true
    init() {
        if ProcessInfo.processInfo.arguments.contains("--demo") { enableDemo() }
        else { useWiFi() }
    }
    func useWiFi() {
        observer?.cancel(); demo = false
        guard let (host, pin) = WatchWiFiConnection.configuration else {
            status = L10n.t("Copy the connection code from Micodex on your Mac to get started.")
            connected = false
            return
        }
        do {
            if wifi == nil { wifi = try WatchWiFiConnection(host: host, pin: pin) }
            wifi?.setActive(active)
            observer = wifi?.objectWillChange.sink { [weak self] in
                DispatchQueue.main.async { self?.sync() }
            }
            sync()
        } catch { status = error.localizedDescription }
    }
    func updateWiFiHost(_ host: String) {
        guard let (_, pin) = WatchWiFiConnection.configuration else { return }
        guard let configuration = WiFiConfiguration(host: host, fingerprint: pin) else {
            status = L10n.t("Enter the full IP address shown in Micodex on your Mac, such as 192.168.1.20.")
            return
        }
        configureWiFi(configuration)
    }
    func configureWiFi(_ configuration: WiFiConfiguration) {
        guard !recordingRequested, !stopping else { return }
        do {
            let replacement = try WatchWiFiConnection(host: configuration.host, pin: configuration.fingerprint)
            wifi?.disconnect(); observer?.cancel()
            wifi = replacement; demo = false
            UserDefaults.standard.set(configuration.host, forKey: "wifiHostOverride")
            UserDefaults.standard.set(configuration.fingerprint, forKey: "wifiPinOverride")
            wifi?.setActive(active)
            observer = wifi?.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.sync() } }
            sync()
        } catch { status = L10n.t("Invalid Mac address: %@", error.localizedDescription) }
    }
    func setActive(_ active: Bool) {
        self.active = active
        if !demo { wifi?.setActive(active); sync() }
    }
    func send(_ action: RemoteAction, value: Int16 = 0) {
        if demo {
            switch action {
            case .beginDictation:
                guard !recordingRequested, phase != .transcribing else { return }
                recordingRequested = true; microphoneReady = true; phase = .listening
            case .finishDictation, .cancelDictation:
                recordingRequested = false; microphoneReady = false; phase = .ready
            default: break
            }
        } else { wifi?.send(action, value: value); sync() }
    }
    func forget() { wifi?.forget(); sync() }
    func enableDemo() {
        wifi?.disconnect(); observer?.cancel()
        demo = true; connected = true; phase = .ready
        recordingRequested = false; microphoneReady = false; stopping = false
        focusedThreadTitle = L10n.t("Demo thread"); recordingNotice = nil
        status = L10n.t("Demo · No Mac connection")
    }
    private func sync() {
        guard !demo, let wifi else { return }
        connected = wifi.connected; status = wifi.status; phase = wifi.phase; macName = wifi.macName
        pairingCode = wifi.pairingCode; microphoneLevel = wifi.microphoneLevel
        stopping = wifi.stopping; microphoneReady = wifi.microphoneReady
        focusedThreadTitle = wifi.focusedThreadTitle; recordingNotice = wifi.recordingNotice
        recordingRequested = wifi.recordingRequested; macAddress = wifi.macAddress
    }
}

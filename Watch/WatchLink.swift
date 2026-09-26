import Foundation
import Combine
import WhisperCore

/// One UI and gesture contract over either transport. Only the selected
/// transport is active; existing BLE pairing remains available as a fallback.
@MainActor
final class WatchLink: ObservableObject {
    @Published var connected = false
    @Published var status = "正在连接 Mac…"
    @Published var phase: HostPhase = .ready
    @Published var macName = "Mac"
    @Published var demo = false
    @Published var nearby: [WatchConnection.NearbyMac] = []
    @Published var usesWiFi = false
    @Published var pairingCode: String?
    @Published var microphoneLevel = ""
    @Published var stopping = false
    @Published var recordingLocked = false
    @Published var recordingRequested = false
    @Published var macAddress = ""
    var canUseWiFi: Bool { WatchWiFiConnection.configuration != nil }
    private var bluetooth: WatchConnection?
    private var wifi: WatchWiFiConnection?
    private var observer: AnyCancellable?
    private var active = true
    init() {
        if ProcessInfo.processInfo.arguments.contains("--demo") { useBluetooth() }
        else if canUseWiFi { useWiFi() }
        else { useBluetooth() }
    }
    func useWiFi() {
        guard let (host, pin) = WatchWiFiConnection.configuration else { return }
        bluetooth?.setActive(false); observer?.cancel()
        do {
            if wifi == nil { wifi = try WatchWiFiConnection(host: host, pin: pin) }
            usesWiFi = true; wifi?.setActive(active)
            observer = wifi?.objectWillChange.sink { [weak self] in
                DispatchQueue.main.async { self?.sync() }
            }
            sync()
        } catch { status = error.localizedDescription }
    }
    func useBluetooth() {
        wifi?.disconnect(); observer?.cancel(); usesWiFi = false
        if bluetooth == nil { bluetooth = WatchConnection() }
        bluetooth?.setActive(active)
        observer = bluetooth?.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.sync() }
        }
        sync()
    }
    func updateWiFiHost(_ host: String) {
        guard let (_, pin) = WatchWiFiConnection.configuration else { return }
        do {
            let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = try WatchWiFiConnection(host: normalized, pin: pin)
            wifi?.disconnect(); bluetooth?.setActive(false); observer?.cancel()
            wifi = replacement; usesWiFi = true
            UserDefaults.standard.set(normalized, forKey: "wifiHostOverride")
            wifi?.setActive(active)
            observer = wifi?.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.sync() } }
            sync()
        } catch { status = "Mac 地址无效：\(error.localizedDescription)" }
    }
    func setActive(_ active: Bool) {
        self.active = active
        if usesWiFi { wifi?.setActive(active) } else { bluetooth?.setActive(active) }
        sync()
    }
    func send(_ action: RemoteAction, value: Int16 = 0) {
        if usesWiFi { wifi?.send(action, value: value) } else { bluetooth?.send(action, value: value) }
        sync()
    }
    func setRecordingLocked(_ value: Bool) {
        if usesWiFi { wifi?.setRecordingLocked(value) }
        sync()
    }
    func forget() { if usesWiFi { wifi?.forget() } else { bluetooth?.forget() }; sync() }
    func choose(_ mac: WatchConnection.NearbyMac) { bluetooth?.choose(mac); sync() }
    func enableDemo() { useBluetooth(); bluetooth?.enableDemo(); sync() }
    private func sync() {
        if usesWiFi, let wifi {
            connected = wifi.connected; status = wifi.status; phase = wifi.phase; macName = wifi.macName
            demo = false; nearby = []; pairingCode = wifi.pairingCode
            microphoneLevel = wifi.microphoneLevel
            stopping = wifi.stopping
            recordingLocked = wifi.recordingLocked
            recordingRequested = wifi.recordingRequested; macAddress = wifi.macAddress
        } else if let bluetooth {
            connected = bluetooth.connected; status = bluetooth.status; phase = bluetooth.phase; macName = bluetooth.macName
            demo = bluetooth.demo; nearby = bluetooth.nearby; pairingCode = nil
            microphoneLevel = "Watch 麦克风 · 最长 2 分钟"
            stopping = false
            recordingLocked = false
            recordingRequested = bluetooth.recordingRequested || (bluetooth.demo && bluetooth.phase == .listening)
            macAddress = ""
        }
    }
}

import Foundation
import Combine
import CoreLocation
#if os(macOS)
import CoreWLAN
#elseif os(watchOS)
import NetworkExtension
#endif

/// Reads only the current network name. Never starts location updates or collects coordinates.
@MainActor
final class WiFiNetworkInfo: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var name: String?
    @Published private(set) var explanation = "正在读取网络名称…"
    @Published private(set) var needsAuthorization = false
    private let location = CLLocationManager()
    private var generation = 0

    override init() {
        super.init()
        location.delegate = self
        refresh()
    }

    func requestNameAccess() {
        if location.authorizationStatus == .notDetermined {
            location.requestWhenInUseAuthorization()
        } else {
            refresh()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.refresh() }
    }

    func refresh() {
        generation += 1
        let token = generation
        let authorization = location.authorizationStatus
        needsAuthorization = authorization == .notDetermined
        guard CLLocationManager.locationServicesEnabled() else {
            name = nil; explanation = "定位服务已关闭；请在系统设置中查看 Wi-Fi 名称"; return
        }
        #if os(macOS)
        let authorized = authorization == .authorizedAlways
        #else
        let authorized = authorization == .authorizedAlways || authorization == .authorizedWhenInUse
        #endif
        guard authorized else {
            name = nil
            explanation = needsAuthorization ? "显示名称需要定位授权，仅用于读取 Wi-Fi 名称" : "未获定位授权；请在系统设置中查看 Wi-Fi 名称"
            return
        }
        needsAuthorization = false
        #if os(macOS)
        let interface = CWWiFiClient.shared().interface()
        name = interface?.ssid()
        explanation = interface?.powerOn() == false ? "Wi-Fi 已关闭" : "未连接 Wi-Fi，或系统未提供名称"
        #elseif os(watchOS)
        guard location.accuracyAuthorization == .fullAccuracy else {
            name = nil; explanation = "需在定位设置中允许精确位置，才能读取 Wi-Fi 名称"; return
        }
        NEHotspotNetwork.fetchCurrent { [weak self] network in
            let ssid = network?.ssid
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.name = ssid
                self.explanation = "系统未提供名称；请在手表「设置 → Wi-Fi」查看当前网络"
            }
        }
        #endif
    }
}

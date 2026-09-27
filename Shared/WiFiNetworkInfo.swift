import Foundation
import Combine
import CoreLocation
import MicodexCore
#if os(macOS)
import CoreWLAN
#elseif os(watchOS)
import NetworkExtension
#endif

/// Reads only the current network name. Never starts location updates or collects coordinates.
@MainActor
final class WiFiNetworkInfo: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var name: String?
    @Published private(set) var explanation = L10n.t("Reading network name…")
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
            name = nil; explanation = L10n.t("Location Services are off. Check the Wi-Fi name in system settings."); return
        }
        #if os(macOS)
        let authorized = authorization == .authorizedAlways
        #else
        let authorized = authorization == .authorizedAlways || authorization == .authorizedWhenInUse
        #endif
        guard authorized else {
            name = nil
            explanation = needsAuthorization ? L10n.t("Allow location access to display the Wi-Fi name. Access is used only to read the network name.") : L10n.t("Location access is not allowed. Check the Wi-Fi name in system settings.")
            return
        }
        needsAuthorization = false
        #if os(macOS)
        let interface = CWWiFiClient.shared().interface()
        name = interface?.ssid()
        explanation = interface?.powerOn() == false ? L10n.t("Wi-Fi is off") : L10n.t("No Wi-Fi connection, or the system did not provide its name.")
        #elseif os(watchOS)
        guard location.accuracyAuthorization == .fullAccuracy else {
            name = nil; explanation = L10n.t("Allow Precise Location in location settings to read the Wi-Fi name."); return
        }
        NEHotspotNetwork.fetchCurrent { [weak self] network in
            let ssid = network?.ssid
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.name = ssid
                self.explanation = L10n.t("The system did not provide a name. Check the current network in Settings → Wi-Fi on your watch.")
            }
        }
        #endif
    }
}

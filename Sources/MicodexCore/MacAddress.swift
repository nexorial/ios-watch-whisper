import Foundation

public enum MacAddress {
    public static func ipv4(_ input: String) -> String? {
        let parts = input.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard (1...3).contains(part.count), part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(part), (0...255).contains(number) else { return nil }
            numbers.append(number)
        }
        guard numbers[0] > 0, numbers[0] < 224, numbers[0] != 127 else { return nil }
        return numbers.map(String.init).joined(separator: ".")
    }
}

public enum WiFiConnectionGuidance {
    public static func message(for error: Error, address: String) -> String {
        guard let error = error as? URLError else { return L10n.t("Connection incomplete: %@", error.localizedDescription) }
        switch error.code {
        case .notConnectedToInternet:
            return L10n.t("No network connection on Watch. Check Settings → Wi-Fi and use the same local network as your Mac.")
        case .cannotConnectToHost, .timedOut, .cannotFindHost, .networkConnectionLost:
            return L10n.t("Cannot reach Mac (%@). Check that Mac shows “Wi-Fi Ready” and that its Mac IP matches this address. Retrying automatically; no need to pair again.", address)
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .secureConnectionFailed, .cancelled:
            return L10n.t("Cannot verify the secure connection to Mac. Check that this IP belongs to your paired Mac. For a different Mac, use “Set Up Another Mac” and copy its connection code.")
        default:
            return L10n.t("Wi-Fi connection failed: %@. Check the receiver status on Mac first.", error.localizedDescription)
        }
    }
}

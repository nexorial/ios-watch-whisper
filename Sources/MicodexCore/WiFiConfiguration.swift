import Foundation

/// Public connection information copied from the user's Mac. This is a full
/// certificate pin, never a pairing key, password, or automatically trusted peer.
public struct WiFiConfiguration: Equatable {
    public let host: String
    public let fingerprint: String

    public init?(host: String, fingerprint: String) {
        guard let address = MacAddress.ipv4(host), fingerprint.count == 64,
              fingerprint.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        self.host = address
        self.fingerprint = fingerprint.lowercased()
    }

    public init?(connectionCode: String) {
        let parts = connectionCode.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "micodex" else { return nil }
        self.init(host: String(parts[1]), fingerprint: String(parts[2]))
    }

    public var connectionCode: String { "micodex:\(host):\(fingerprint)" }
}

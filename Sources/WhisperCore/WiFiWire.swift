import Foundation
import CryptoKit

public struct WiFiRequest: Codable, Sendable {
    public var id: String
    public var ticket: String?
    public var nonce: String?
    public var proof: String?
    public var packet: String?
    public var packets: [String]?
    public init(id: String, ticket: String? = nil, nonce: String? = nil, proof: String? = nil,
                packet: String? = nil, packets: [String]? = nil) {
        self.id = id; self.ticket = ticket; self.nonce = nonce; self.proof = proof; self.packet = packet; self.packets = packets
    }
}
public struct WiFiReply: Codable, Sendable {
    public var status: String
    public var message: String?
    public var name: String?
    public var key: String?
    public var challenge: String?
    public var packet: String?
    public init(_ status: String, message: String? = nil, name: String? = nil, key: String? = nil,
                challenge: String? = nil, packet: String? = nil) {
        self.status = status; self.message = message; self.name = name; self.key = key
        self.challenge = challenge; self.packet = packet
    }
}
public enum WiFiWire {
    public static func pairingCode(id: String, ticket: Data) -> String {
        let digest = Array(SHA256.hash(data: Data(id.utf8) + ticket))
        let number = UInt32(digest[0]) << 24 | UInt32(digest[1]) << 16 | UInt32(digest[2]) << 8 | UInt32(digest[3])
        return String(format: "%06u", number % 1_000_000)
    }
    public static func sessionProof(id: String, nonce: Data, key: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data("WatchWhisper/WiFi/session/v1/\(id)".utf8) + nonce,
                                             using: SymmetricKey(data: key)))
    }
    public static func validProof(_ proof: Data, id: String, nonce: Data, key: Data) -> Bool {
        guard proof.count == 32, nonce.count == 16, key.count == 32 else { return false }
        let expected = sessionProof(id: id, nonce: nonce, key: key)
        return zip(proof, expected).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

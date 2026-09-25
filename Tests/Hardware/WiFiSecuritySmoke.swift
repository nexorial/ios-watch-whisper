import Foundation
import WhisperCore

@main
struct WiFiSecuritySmoke {
    @MainActor static func main() async {
        do { try await run() }
        catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    @MainActor static func run() async throws {
        let identity = try LocalTLSIdentity.prepare()
        guard let address = LocalTLSIdentity.localAddress() else { throw Failure("No local interface") }
        let id = UUID().uuidString, suite = "WatchWhisper.Test.\(UUID())", prefix = "wifi-test-\(UUID())-"
        let preferences = UserDefaults(suiteName: suite)!
        // Production TLS/pairing/session implementation, isolated credentials and
        // a demo controller: this test cannot operate Codex or send user messages.
        let host = WiFiHost(controller: AgentController(demo: true), demo: false, preferences: preferences,
                            accountPrefix: prefix, port: 8767)
        defer { host.shutdown(); try? KeychainStore.delete(prefix + id); preferences.removePersistentDomain(forName: suite) }
        let client = try PinnedHTTPSClient(host: address, port: 8767, fingerprint: identity.fingerprint)
        defer { client.invalidate() }
        for _ in 0..<20 {
            if host.status.hasPrefix("Wi-Fi 已就绪") { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let hello = try await client.request("v1/hello")
        try require(hello.status == "ok", "Pinned TLS health")
        let denied = try await client.request("v1/command", WiFiRequest(id: id, packet: Data(repeating: 0, count: 20).base64EncodedString()))
        try require(denied.status == "unpaired" && denied.packet == nil, "Unapproved commands rejected")
        let ticket = try KeychainStore.random(count: 32)
        let pairing = WiFiRequest(id: id, ticket: ticket.base64EncodedString())
        try require(try await client.request("v1/pair", pairing).key == nil, "Closed pairing window")
        host.allowPairing()
        _ = try await client.request("v1/pair", pairing)
        try require(host.pendingCode == WiFiWire.pairingCode(id: id, ticket: ticket), "Matching verification code")
        host.approve()
        let approved = try await client.request("v1/pair", pairing)
        guard let key = approved.key.flatMap({ Data(base64Encoded: $0) }), key.count == 32 else { throw Failure("Pairing key") }
        let wrongTicket = WiFiRequest(id: id, ticket: Data(repeating: 1, count: 32).base64EncodedString())
        try require(try await client.request("v1/pair", wrongTicket).key == nil, "Other pairing ticket cannot retrieve key")
        let nonce = try KeychainStore.random(count: 16)
        let session = try await client.request("v1/session", WiFiRequest(id: id, nonce: nonce.base64EncodedString(),
            proof: WiFiWire.sessionProof(id: id, nonce: nonce, key: key).base64EncodedString()))
        guard let challenge = session.challenge.flatMap({ Data(base64Encoded: $0) }) else { throw Failure("Session challenge") }
        let packet = try Wire.encode(Command(.heartbeat, sequence: 1), key: key, challenge: challenge)
        let command = WiFiRequest(id: id, packet: packet.base64EncodedString())
        let reply = try await client.request("v1/command", command)
        guard let data = reply.packet.flatMap({ Data(base64Encoded: $0) }) else { throw Failure("Signed acknowledgement") }
        let (_, sequence) = try Wire.decodeStatus(data, key: key, challenge: challenge)
        try require(sequence == 1, "Authenticated heartbeat")
        try require(try await client.request("v1/command", command).packet == nil, "Replay rejected")
        let wrongPin = try PinnedHTTPSClient(host: address, port: 8767, fingerprint: String(repeating: "0", count: 64))
        defer { wrongPin.invalidate() }
        var rejected = false
        do { _ = try await wrongPin.request("v1/hello") } catch { rejected = true }
        try require(rejected, "Wrong certificate rejected")
        host.revokeAll()
        let revoked = try await client.request("v1/command", command)
        try require(revoked.status == "unpaired", "Revoked device rejected")
        print("PASS: pinned HTTPS, pairing approval, ticket binding, authenticated session, replay rejection, wrong-pin rejection, revocation")
    }
    static func require(_ condition: Bool, _ message: String) throws { if !condition { throw Failure(message) } }
    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

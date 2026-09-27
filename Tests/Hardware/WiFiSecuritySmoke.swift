import Foundation
import Network
import MicodexCore

@main
struct WiFiSecuritySmoke {
    @MainActor static func main() async {
        do { try await run() }
        catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    @MainActor static func run() async throws {
        let identity = try LocalTLSIdentity.prepare()
        guard let address = LocalTLSIdentity.localAddress() else { throw Failure("No local interface") }
        let id = UUID().uuidString, suite = "Micodex.Test.\(UUID())", prefix = "wifi-test-\(UUID())-"
        let preferences = UserDefaults(suiteName: suite)!
        // Production TLS/pairing/session implementation, isolated credentials and
        // a demo controller: this test cannot operate Codex or send user messages.
        let playback = TestPlayback()
        let host = WiFiHost(controller: AgentController(demo: true), demo: false, preferences: preferences,
                            accountPrefix: prefix, port: 8767, audioOverride: playback)
        defer { host.shutdown(); try? KeychainStore.delete(prefix + id); preferences.removePersistentDomain(forName: suite) }
        let client = try PinnedHTTPSClient(host: address, port: 8767, fingerprint: identity.fingerprint)
        defer { client.invalidate() }
        for _ in 0..<20 {
            if host.serviceReady { break }
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
        // Exercise real authenticated commands/audio against a demo controller
        // and in-memory sample counter: no audio device or other app is touched.
        func send(_ action: RemoteAction, _ sequence: UInt32) async throws -> HostPhase {
            let packet = try Wire.encode(Command(action, sequence: sequence), key: key, challenge: challenge)
            let reply = try await client.request("v1/command", WiFiRequest(id: id, packet: packet.base64EncodedString()))
            guard let data = reply.packet.flatMap({ Data(base64Encoded: $0) }) else { throw Failure("Command acknowledgement: \(action)") }
            let (phase, returned) = try Wire.decodeStatus(data, key: key, challenge: challenge)
            try require(returned == sequence, "Matching command acknowledgement")
            return phase
        }
        try require(try await send(.beginDictation, 2) == .listening, "Begin test stream")
        // ADPCM transition ringing can consume the first 20 ms quiet window.
        let samples = Array(repeating: Int16(2000), count: 1600) + Array(repeating: Int16(0), count: 35200)
        var offset: UInt32 = 0, audioSequence: UInt32 = 0
        for start in stride(from: 0, to: samples.count, by: 512) {
            let block = Array(samples[start..<min(start + 512, samples.count)])
            audioSequence += 1
            let packet = try AudioWire.encode(samples: block, stream: 2, sequence: audioSequence, offset: offset, key: key, challenge: challenge)
            let result = try await client.request("v1/audio", WiFiRequest(id: id, packets: [packet.base64EncodedString()]))
            try require(result.status == "ok", "Authenticated audio accepted")
            offset += UInt32(block.count)
        }
        for _ in 0..<20 {
            if playback.drains > 0 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try require(playback.drains == 1, "Silence starts exactly one finalization")
        try require(try await send(.cancelDictation, 3) == .transcribing, "Cleanup cancel preserves draining transcript")
        let received = playback.receivedSamples
        audioSequence += 1
        let late = try AudioWire.encode(samples: [2000], stream: 2, sequence: audioSequence, offset: offset, key: key, challenge: challenge)
        try require(try await client.request("v1/audio", WiFiRequest(id: id, packets: [late.base64EncodedString()])).status == "ok", "Late audio validated")
        try require(playback.receivedSamples == received, "Late audio never reaches dictation")
        playback.completeDrain()
        for _ in 0..<20 {
            if playback.stops > 0 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try require(try await send(.heartbeat, 4) == .ready, "Automatic stop acknowledged")
        try require(try await send(.finishDictation, 5) == .ready && playback.drains == 1, "Late release is idempotent")
        try require(try await send(.cancelDictation, 6) == .ready && playback.drains == 1, "Late cleanup is idempotent")
        try require(try await send(.beginDictation, 7) == .listening, "New recording starts after finalization")
        let end = try AudioWire.encode(samples: [], stream: 7, sequence: 1, offset: 0, ended: true, key: key, challenge: challenge)
        try require(try await client.request("v1/audio", WiFiRequest(id: id, packets: [end.base64EncodedString()])).status == "ok", "New stream accepts its end marker")
        try require(try await send(.finishDictation, 8) == .ready && playback.drains == 2, "Manual release still finalizes normally")
        host.refreshNetwork()
        var refreshed = false
        for _ in 0..<20 {
            if let reply = try? await client.request("v1/hello"), reply.status == "ok" { refreshed = true; break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try require(refreshed && host.pairedCount == 1 && host.address == address,
                    "Network refresh: ready=\(refreshed) paired=\(host.pairedCount) address=\(host.address) status=\(host.status)")
        try require(try await client.request("v1/command", command).status == "sessionExpired", "Refresh invalidates old sessions")
        let renewed = try await client.request("v1/session", WiFiRequest(id: id, nonce: nonce.base64EncodedString(),
            proof: WiFiWire.sessionProof(id: id, nonce: nonce, key: key).base64EncodedString()))
        try require(renewed.status == "ok" && renewed.challenge != session.challenge, "Paired Watch can reauthenticate after refresh")
        let wrongPin = try PinnedHTTPSClient(host: address, port: 8767, fingerprint: String(repeating: "0", count: 64))
        defer { wrongPin.invalidate() }
        var rejected = false
        do { _ = try await wrongPin.request("v1/hello") } catch { rejected = true }
        try require(rejected, "Wrong certificate rejected")
        host.revokeAll()
        let revoked = try await client.request("v1/command", command)
        try require(revoked.status == "unpaired", "Revoked device rejected")
        // Repeated refreshes after real keep-alive requests must release the old
        // listener completely, including back-to-back refresh requests.
        for _ in 0..<8 {
            host.refreshNetwork(); host.refreshNetwork()
            try await waitForReady(host)
            try require(try await client.request("v1/hello").status == "ok", "Repeated refresh remains reachable")
        }
        let duplicate = WiFiHost(controller: AgentController(demo: true), demo: false, preferences: preferences,
                                 accountPrefix: prefix, port: 8767)
        try require(duplicate.duplicateReceiver && !duplicate.serviceReady, "Second receiver cannot claim the same port")
        duplicate.allowPairing()
        try require(!duplicate.pairingOpen, "Pairing cannot open on an unavailable receiver")
        duplicate.shutdown()

        // Reproduce a genuine EADDRINUSE from a non-Micodex listener. The host
        // must recover automatically after the owner releases the port.
        let blocker = try NWListener(using: .tcp, on: .any)
        blocker.newConnectionHandler = { $0.cancel() }
        blocker.start(queue: .main)
        defer { blocker.cancel() }
        for _ in 0..<60 {
            if case .ready = blocker.state { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard let occupiedPort = blocker.port?.rawValue else { throw Failure("Blocker did not bind") }
        let recovering = WiFiHost(controller: AgentController(demo: true), demo: false, preferences: preferences,
                                  accountPrefix: prefix, port: occupiedPort)
        defer { recovering.shutdown() }
        for _ in 0..<60 {
            if recovering.serviceIssue != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try require(!recovering.serviceReady && recovering.serviceIssue != nil,
                    "Busy port is explained, never reported ready: \(recovering.status)")
        blocker.cancel()
        try await waitForReady(recovering)
        let recoveredClient = try PinnedHTTPSClient(host: address, port: occupiedPort, fingerprint: identity.fingerprint)
        defer { recoveredClient.invalidate() }
        try require(try await recoveredClient.request("v1/hello").status == "ok", "Automatically recovers after external port owner exits")
        recovering.shutdown(); recovering.shutdown()
        try await Task.sleep(nanoseconds: 100_000_000)
        try require(!recovering.serviceReady, "Shutdown never restarts a pending recovery")
        print("PASS: 8 rapid refresh cycles, duplicate receiver exclusion, pairing readiness, real EADDRINUSE and automatic recovery, repeated shutdown")
        print("PASS: pinned HTTPS, pairing approval, ticket binding, authenticated session, replay rejection, silence stop, late cancel/release/audio protection, new stream and manual stop, network refresh/reconnect, wrong-pin rejection, revocation")
    }
    @MainActor static func waitForReady(_ host: WiFiHost) async throws {
        for _ in 0..<160 {
            if host.serviceReady { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw Failure("Receiver did not recover: \(host.status) / \(host.serviceIssue ?? "none")")
    }
    static func require(_ condition: Bool, _ message: String) throws { if !condition { throw Failure(message) } }
    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

@MainActor
private final class TestPlayback: WatchAudioPlayback {
    var receivedSamples = 0
    var captureSummary: String { "Test sample counter" }
    var drains = 0
    var stops = 0
    private var waiter: CheckedContinuation<Void, Never>?
    private var holdDrain = true
    func start() throws { receivedSamples = 0; stops = 0 }
    func enqueue(_ samples: [Int16]) throws { receivedSamples += samples.count }
    func drain() async throws {
        drains += 1
        if holdDrain { await withCheckedContinuation { waiter = $0 } }
    }
    func stop() { stops += 1 }
    func completeDrain() { holdDrain = false; waiter?.resume(); waiter = nil }
}

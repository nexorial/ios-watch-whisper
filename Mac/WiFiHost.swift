import Foundation
import CryptoKit
import Network
import MicodexCore

@MainActor
final class WiFiHost: ObservableObject {
    @Published var status = L10n.t("Preparing Wi-Fi direct connection…")
    @Published var address = ""
    @Published private(set) var fingerprint = ""
    var connectionCode: String? {
        guard serviceReady else { return nil }
        return WiFiConfiguration(host: address, fingerprint: fingerprint)?.connectionCode
    }
    @Published var pairingOpen = false
    @Published var pendingCode: String?
    @Published var pairedCount = 0
    @Published private(set) var refreshingNetwork = false
    @Published private(set) var serviceReady = false
    @Published private(set) var serviceIssue: String?
    @Published private(set) var duplicateReceiver = false
    private let lease = ReceiverLease()
    private var retryTask: Task<Void, Never>?
    private var networkTask: Task<Void, Never>?
    private var retryAttempt = 0
    private var stopped = false
    let audio = WatchAudioOutput()
    private let audioOverride: WatchAudioPlayback?
    private var playback: WatchAudioPlayback { audioOverride ?? audio }
    private let controller: AgentController
    private let preferences: UserDefaults
    private let accountPrefix: String
    private let port: UInt16
    private var server: TLSHTTPServer?
    private var serverEpoch = UUID()
    private var pairingUntil = Date.distantPast
    private var pending: Pairing?
    private var grants: [UUID: Pairing] = [:]
    private var sessions: [UUID: Session] = [:]
    private var owner: UUID?
    private struct Pairing { let id: UUID; let ticket: Data; let expires: Date }
    private struct Session {
        let key: Data; let challenge: Data; let clientNonce: Data
        var gate = ReplayGate(); var audioGate: AudioGate?
        var finalized = false
        var draining = false
    }
    private var approved: [String] {
        get { preferences.stringArray(forKey: "wifiPairedWatches") ?? [] }
        set { preferences.set(newValue, forKey: "wifiPairedWatches"); pairedCount = newValue.count }
    }
    init(controller: AgentController, demo: Bool, preferences: UserDefaults = .standard,
         accountPrefix: String = "wifi-watch-", port: UInt16 = LocalTLSIdentity.port,
         audioOverride: WatchAudioPlayback? = nil) {
        self.controller = controller; self.preferences = preferences; self.accountPrefix = accountPrefix; self.port = port
        self.audioOverride = audioOverride
        pairedCount = approved.count
        if demo { status = L10n.t("Demo mode") } else {
            start()
            networkTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    guard !Task.isCancelled, let self, !self.stopped else { return }
                    self.refreshAddressIfNeeded()
                }
            }
        }
    }
    func start() {
        guard !stopped, server == nil, !refreshingNetwork else { return }
        retryTask?.cancel(); retryTask = nil
        serviceReady = false
        do {
            guard try lease.acquire(port: port) else {
                duplicateReceiver = true
                serviceIssue = L10n.t("Another Micodex receiver is running. Use its open window; this receiver will take over automatically when it closes.")
                status = L10n.t("Another receiver is running"); scheduleRetry(); return
            }
            duplicateReceiver = false
            guard let host = LocalTLSIdentity.localAddress() else {
                address = ""; status = L10n.t("Not connected to a local network")
                serviceIssue = L10n.t("Connect your Mac to Wi-Fi. Connection will resume automatically when the network returns.")
                scheduleRetry(); return
            }
            address = host
            let identity = try LocalTLSIdentity.prepare()
            fingerprint = identity.fingerprint
            let token = UUID(); serverEpoch = token
            let server = TLSHTTPServer { [weak self] request in
                guard let self else { return (503, WiFiReply("error", message: L10n.message("The receiver has closed"))) }
                return await self.handle(request, epoch: token)
            }
            self.server = server
            status = L10n.t("Starting the receiver…")
            try server.start(identity: identity.identity, address: host, portNumber: port) { [weak self] event in
                Task { @MainActor in
                    guard let self, self.serverEpoch == token, !self.stopped else { return }
                    switch event {
                    case .ready:
                        self.serviceReady = true; self.serviceIssue = nil; self.retryAttempt = 0
                        self.status = L10n.t("Wi-Fi Ready · Waiting for Watch")
                    case .waiting(let error), .failed(let error):
                        self.serviceReady = false
                        self.status = L10n.t("Receiver unavailable · Retrying automatically")
                        if case .posix(.EADDRINUSE) = error {
                            self.serviceIssue = L10n.t("The Mac receiver port is in use. Close other Micodex or older Watch Whisper instances. Keep the Watch IP and pairing; connection will recover when the port is free.")
                        } else {
                            self.serviceIssue = L10n.t("Check the Mac local network connection and Local Network permission. The service will retry automatically. Details: %@", error.localizedDescription)
                        }
                        ConnectionTrace.record("wifi-server", "port=\(self.port) listener error=\(error)")
                        self.retireServer(retry: true)
                    }
                }
            }
        } catch {
            serviceIssue = L10n.t("Could not start the receiver: %@", error.localizedDescription)
            status = L10n.t("Receiver unavailable · Retrying automatically")
            retireServer(retry: true)
        }
    }
    private func scheduleRetry() {
        guard !stopped, retryTask == nil else { return }
        let delay = min(30, 1 << min(retryAttempt, 5)); retryAttempt += 1
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.retryTask = nil; self.start()
        }
    }
    private func retireServer(retry: Bool) {
        let previous = server
        serverEpoch = UUID(); serviceReady = false
        controller.stopScrolling()
        sessions = [:]; owner = nil; grants = [:]
        pending = nil; pendingCode = nil; pairingOpen = false; pairingUntil = .distantPast
        if controller.isRecording && !controller.isFinishing {
            Task { _ = await controller.perform(.finishReceivedAudio); playback.stop() }
        } else { playback.stop() }
        guard let previous else {
            if retry { scheduleRetry() }
            return
        }
        refreshingNetwork = true
        // Keep the old server referenced until its cancellation callback. Failed
        // listeners must be discarded too, otherwise start() stays a no-op.
        previous.stop { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.server = nil; self.refreshingNetwork = false
                guard !self.stopped else { self.lease.release(); return }
                if retry { self.scheduleRetry() } else { self.start() }
            }
        }
    }
    var canRefreshNetwork: Bool {
        !refreshingNetwork && !controller.isRecording && !controller.isFinishing && !controller.isBusy && !sessions.values.contains { $0.draining }
    }
    func refreshNetwork() {
        guard canRefreshNetwork, !stopped else { return }
        retryTask?.cancel(); retryTask = nil; retryAttempt = 0
        status = L10n.t("Reconnecting to the local network…")
        if server == nil { start() } else { retireServer(retry: false) }
    }
    func refreshAddressIfNeeded() {
        guard !stopped else { return }
        if LocalTLSIdentity.localAddress() != address { refreshNetwork() }
        else if server == nil && retryTask == nil && !refreshingNetwork { start() }
    }
    func shutdown() {
        stopped = true
        networkTask?.cancel(); networkTask = nil; retryTask?.cancel(); retryTask = nil
        retireServer(retry: false)
        if server == nil { lease.release() }
    }
    func allowPairing() {
        guard serviceReady else { refreshNetwork(); return }
        pairingUntil = Date().addingTimeInterval(60); pairingOpen = true; pending = nil; pendingCode = nil
        status = L10n.t("Check the pairing code on your Watch")
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard let self, self.pairingUntil <= Date() else { return }
            self.pairingOpen = false; self.pending = nil; self.pendingCode = nil
            if self.sessions.isEmpty { self.status = L10n.t("The pairing window closed") }
        }
    }
    func approve() {
        guard pairingOpen, Date() < pairingUntil, let pending else { return }
        do {
            let key = try KeychainStore.random(count: 32)
            try KeychainStore.save(key, account: "\(accountPrefix)\(pending.id)")
            sessions[pending.id] = nil
            if owner == pending.id {
                owner = nil; playback.stop()
                Task { _ = await controller.perform(.cancelDictation) }
            }
            var ids = approved
            if !ids.contains(pending.id.uuidString) { ids.append(pending.id.uuidString) }; approved = ids
            grants[pending.id] = Pairing(id: pending.id, ticket: pending.ticket, expires: Date().addingTimeInterval(90))
            self.pending = nil; pendingCode = nil; pairingOpen = false; status = L10n.t("Watch allowed. Verifying the connection…")
        } catch { status = L10n.t("Could not save Wi-Fi pairing: %@", error.localizedDescription) }
    }
    func revokeAll() {
        controller.stopScrolling()
        let ids = approved, wasRecording = owner != nil
        approved = []; owner = nil; sessions = [:]; grants = [:]
        pending = nil; pendingCode = nil; pairingOpen = false; pairingUntil = .distantPast
        playback.stop()
        Task {
            if wasRecording { _ = await controller.perform(.cancelDictation) }
            do {
                for id in ids { try KeychainStore.delete("\(accountPrefix)\(id)") }
                status = L10n.t("Wi-Fi pairing removed")
            } catch { status = L10n.t("Could not remove pairing") }
        }
    }
    private func handle(_ request: HTTPEnvelope, epoch: UUID) async -> (Int, WiFiReply) {
        guard serverEpoch == epoch, serviceReady else { return (503, WiFiReply("error", message: L10n.message("The network was refreshed. Connect again."))) }
        if request.method == "GET", request.path == "/v1/hello" {
            return (200, WiFiReply("ok", name: Host.current().localizedName ?? "Mac"))
        }
        guard request.method == "POST", let input = try? JSONDecoder().decode(WiFiRequest.self, from: request.body),
              let id = UUID(uuidString: input.id) else { return (400, WiFiReply("error", message: L10n.message("Invalid request format"))) }
        do {
            if request.path == "/v1/pair" { return try pair(id: id, input: input) }
            guard approved.contains(id.uuidString), let key = try KeychainStore.read("\(accountPrefix)\(id)"), key.count == 32 else {
                return (403, WiFiReply("unpaired", message: L10n.message("Click Allow This Watch on your Mac")))
            }
            if request.path == "/v1/session" {
                guard let nonce = input.nonce.flatMap({ Data(base64Encoded: $0) }),
                      let proof = input.proof.flatMap({ Data(base64Encoded: $0) }),
                      WiFiWire.validProof(proof, id: id.uuidString, nonce: nonce, key: key) else {
                    return (403, WiFiReply("unpaired", message: L10n.message("Pairing verification failed. Pair again.")))
                }
                if let session = sessions[id], session.clientNonce == nonce {
                    return (200, WiFiReply("ok", challenge: session.challenge.base64EncodedString()))
                }
                guard !controller.isBusy, !sessions.values.contains(where: { $0.draining }),
                      !controller.isRecording || controller.isFinishing else { return (409, WiFiReply("error", message: L10n.message("Finish the current dictation first"))) }
                let challenge = try KeychainStore.random(count: 16)
                sessions[id] = Session(key: key, challenge: challenge, clientNonce: nonce); grants[id] = nil
                return (200, WiFiReply("ok", challenge: challenge.base64EncodedString()))
            }
            guard var session = sessions[id] else { return (403, WiFiReply("sessionExpired", message: L10n.message("The connection needs verification again"))) }
            if request.path == "/v1/audio" {
                guard (owner == id && controller.isRecording) || session.finalized else {
                    return (409, WiFiReply("error", message: L10n.message("No recording session is active for this Watch")))
                }
                guard var gate = session.audioGate,
                      let packets = input.packets, !packets.isEmpty, packets.count <= 32 else {
                    return (409, WiFiReply("error", message: L10n.message("No recording session is active for this Watch")))
                }
                for packet in packets {
                    guard let data = Data(base64Encoded: packet) else { throw WireError.malformed }
                    let frame = try AudioWire.decode(data, key: session.key, challenge: session.challenge)
                    let gap = try gate.accept(frame)
                    // Validate late packets, but never feed them to a recording
                    // which is already being finalized. Gaps are not speech silence.
                    if !session.finalized {
                        if gap > 0 { try playback.enqueue([Int16](repeating: 0, count: gap)) }
                        try playback.enqueue(frame.samples)
                    }
                    if frame.ended { ConnectionTrace.record("audio", "Watch end marker received samples=\(frame.offset)") }
                }
                if session.audioGate?.nextOffset == 0 {
                    ConnectionTrace.record("audio", "first Watch audio batch received")
                }
                session.audioGate = gate; sessions[id] = session
                return (200, WiFiReply("ok"))
            }
            guard request.path == "/v1/command", let packet = input.packet.flatMap({ Data(base64Encoded: $0) }) else {
                return (404, WiFiReply("error", message: L10n.message("Unknown request")))
            }
            let command = try Wire.decode(packet, key: session.key, challenge: session.challenge)
            try session.gate.accept(command); sessions[id] = session
            let phase: HostPhase
            if controller.isRecording && owner != id { phase = .unavailable }
            else if session.draining { phase = .transcribing }
            else if (session.finalized || controller.isFinishing) && [.finishDictation, .finishReceivedAudio, .cancelDictation].contains(command.action) {
                // Old clients send a cleanup cancel on reconnect. Once this
                // stream has ended, that must not abort the pending transcript.
                phase = await controller.perform(.heartbeat)
            }
            else if command.action == .beginDictation {
                guard !controller.isRecording && !controller.isFinishing else {
                    return (409, WiFiReply("error", message: L10n.message("Wait for the previous dictation to finish before starting again")))
                }
                do {
                    try playback.start()
                    controller.drainBeforePreserving = { [weak playback] in
                        try? await playback?.drain(); playback?.stop()
                    }
                    phase = await controller.perform(.beginDictation)
                    if phase == .listening {
                        owner = id; sessions[id]?.audioGate = AudioGate(stream: command.sequence)
                        sessions[id]?.finalized = false
                    }
                    else { playback.stop() }
                } catch {
                    playback.stop(); controller.phase = .failed; controller.detailMessage = (error as? LocalizedMessageError)?.localizedMessage ?? L10n.message("Audio failed: %@", error.localizedDescription); phase = .failed
                }
            } else if [.finishDictation, .finishReceivedAudio].contains(command.action), owner == id {
                guard command.action == .finishReceivedAudio || sessions[id]?.audioGate?.ended == true else {
                    throw LocalTLSIdentity.Failure(L10n.message("Watch audio has not finished completely"))
                }
                sessions[id]?.finalized = true; sessions[id]?.draining = true
                phase = await finishAudio(id: id, challenge: session.challenge)
            } else { phase = await controller.perform(command.action, value: command.value) }
            if !controller.isRecording { owner = nil; playback.stop() }
            if [.beginDictation, .finishDictation, .cancelDictation, .finishReceivedAudio].contains(command.action) {
                ConnectionTrace.record("audio", "\(command.action) phase=\(phase) samples=\(playback.receivedSamples) \(playback.captureSummary)")
            }
            let newStatus = L10n.t("Wi-Fi connected · %@", phase.caption)
            if status != newStatus { status = newStatus }
            return (200, WiFiReply("ok", message: controller.detailMessage,
                                  packet: try Wire.status(phase, sequence: command.sequence, key: session.key,
                                                          challenge: session.challenge).base64EncodedString(),
                                  focusedThreadTitle: controller.focusedThreadTitle()))
        } catch {
            ConnectionTrace.record("wifi", "request failed path=\(request.path) samples=\(playback.receivedSamples) error=\(error.localizedDescription)")
            if request.path == "/v1/audio", owner == id {
                if sessions[id]?.finalized == false {
                    sessions[id]?.finalized = true; sessions[id]?.draining = true
                    _ = await finishAudio(id: id, challenge: sessions[id]!.challenge)
                }
            }
            return (403, WiFiReply("error", message: L10n.message("Request verification failed or audio transfer was interrupted")))
        }
    }
    private func finishAudio(id: UUID, challenge: Data) async -> HostPhase {
        guard owner == id, sessions[id]?.challenge == challenge else { return controller.phase }
        do {
            let started = ProcessInfo.processInfo.systemUptime
            try await playback.drain()
            ConnectionTrace.record("audio", String(format: "tail playback drained in %.0f ms", (ProcessInfo.processInfo.systemUptime - started) * 1000))
        } catch {
            ConnectionTrace.record("audio", "tail playback stopped: \(error.localizedDescription)")
        }
        guard owner == id, sessions[id]?.challenge == challenge else { return controller.phase }
        playback.stop()
        let phase = await controller.perform(.finishDictation)
        if sessions[id]?.challenge == challenge { sessions[id]?.draining = false }
        if !controller.isRecording { owner = nil }
        status = L10n.t("Wi-Fi connected · %@", phase.caption)
        return phase
    }
    private func pair(id: UUID, input: WiFiRequest) throws -> (Int, WiFiReply) {
        guard let ticket = input.ticket.flatMap({ Data(base64Encoded: $0) }), ticket.count == 32 else {
            return (400, WiFiReply("error", message: L10n.message("Invalid pairing request format")))
        }
        grants = grants.filter { $0.value.expires > Date() }
        if let grant = grants[id], grant.ticket == ticket,
           let key = try KeychainStore.read("\(accountPrefix)\(id)") {
            return (200, WiFiReply("ok", name: Host.current().localizedName ?? "Mac", key: key.base64EncodedString()))
        }
        guard pairingOpen, Date() < pairingUntil else {
            return (403, WiFiReply("pending", message: L10n.message("Click Allow Wi-Fi Watch on your Mac")))
        }
        if pending == nil {
            pending = Pairing(id: id, ticket: ticket, expires: pairingUntil)
            pendingCode = WiFiWire.pairingCode(id: id.uuidString, ticket: ticket)
        }
        guard pending?.id == id, pending?.ticket == ticket else {
            return (409, WiFiReply("pending", message: L10n.message("The Mac is handling another pairing request")))
        }
        return (202, WiFiReply("pending", message: L10n.message("Check the pairing code, then click Codes Match — Allow on your Mac")))
    }
}

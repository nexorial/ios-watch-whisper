import Foundation
import CryptoKit
import WhisperCore

@MainActor
final class WiFiHost: ObservableObject {
    @Published var status = "正在准备 Wi-Fi 直连…"
    @Published var address = ""
    @Published var pairingOpen = false
    @Published var pendingCode: String?
    @Published var pairedCount = 0
    let audio = WatchAudioOutput()
    private let controller: AgentController
    private let preferences: UserDefaults
    private let accountPrefix: String
    private let port: UInt16
    private var server: TLSHTTPServer?
    private var pairingUntil = Date.distantPast
    private var pending: Pairing?
    private var grants: [UUID: Pairing] = [:]
    private var sessions: [UUID: Session] = [:]
    private var owner: UUID?
    private struct Pairing { let id: UUID; let ticket: Data; let expires: Date }
    private struct Session {
        let key: Data; let challenge: Data; let clientNonce: Data
        var gate = ReplayGate(); var audioGate: AudioGate?
    }
    private var approved: [String] {
        get { preferences.stringArray(forKey: "wifiPairedWatches") ?? [] }
        set { preferences.set(newValue, forKey: "wifiPairedWatches"); pairedCount = newValue.count }
    }
    init(controller: AgentController, demo: Bool, preferences: UserDefaults = .standard,
         accountPrefix: String = "wifi-watch-", port: UInt16 = LocalTLSIdentity.port) {
        self.controller = controller; self.preferences = preferences; self.accountPrefix = accountPrefix; self.port = port
        pairedCount = approved.count
        if demo { status = "演示模式" } else { start() }
    }
    func start() {
        guard server == nil else { return }
        do {
            let identity = try LocalTLSIdentity.prepare()
            guard let host = LocalTLSIdentity.localAddress() else { status = "请连接 Mac 的 Wi-Fi 局域网"; return }
            address = host
            let server = TLSHTTPServer { [weak self] request in
                guard let self else { return (503, WiFiReply("error", message: "接收端已退出")) }
                return await self.handle(request)
            }
            self.server = server
            try server.start(identity: identity.identity, address: host, portNumber: port) { [weak self] state in
                Task { @MainActor in self?.status = state }
            }
        } catch { server = nil; status = error.localizedDescription }
    }
    func shutdown() { controller.stopScrolling(); server?.stop(); server = nil; audio.stop() }
    func allowPairing() {
        guard server != nil else { start(); return }
        pairingUntil = Date().addingTimeInterval(60); pairingOpen = true; pending = nil; pendingCode = nil
        status = "请在手表核对配对码"
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard let self, self.pairingUntil <= Date() else { return }
            self.pairingOpen = false; self.pending = nil; self.pendingCode = nil
            if self.sessions.isEmpty { self.status = "配对窗口已结束" }
        }
    }
    func approve() {
        guard pairingOpen, Date() < pairingUntil, let pending else { return }
        do {
            let key = try KeychainStore.random(count: 32)
            try KeychainStore.save(key, account: "\(accountPrefix)\(pending.id)")
            sessions[pending.id] = nil
            if owner == pending.id {
                owner = nil; audio.stop()
                Task { _ = await controller.perform(.cancelDictation) }
            }
            var ids = approved
            if !ids.contains(pending.id.uuidString) { ids.append(pending.id.uuidString) }; approved = ids
            grants[pending.id] = Pairing(id: pending.id, ticket: pending.ticket, expires: Date().addingTimeInterval(90))
            self.pending = nil; pendingCode = nil; pairingOpen = false; status = "已允许手表，正在验证连接…"
        } catch { status = "保存 Wi-Fi 配对失败：\(error.localizedDescription)" }
    }
    func revokeAll() {
        controller.stopScrolling()
        let ids = approved, wasRecording = owner != nil
        approved = []; owner = nil; sessions = [:]; grants = [:]
        pending = nil; pendingCode = nil; pairingOpen = false; pairingUntil = .distantPast
        audio.stop()
        Task {
            if wasRecording { _ = await controller.perform(.cancelDictation) }
            do {
                for id in ids { try KeychainStore.delete("\(accountPrefix)\(id)") }
                status = "Wi-Fi 配对已移除"
            } catch { status = "移除配对失败" }
        }
    }
    private func handle(_ request: HTTPEnvelope) async -> (Int, WiFiReply) {
        if request.method == "GET", request.path == "/v1/hello" {
            return (200, WiFiReply("ok", name: Host.current().localizedName ?? "Mac"))
        }
        guard request.method == "POST", let input = try? JSONDecoder().decode(WiFiRequest.self, from: request.body),
              let id = UUID(uuidString: input.id) else { return (400, WiFiReply("error", message: "请求格式错误")) }
        do {
            if request.path == "/v1/pair" { return try pair(id: id, input: input) }
            guard approved.contains(id.uuidString), let key = try KeychainStore.read("\(accountPrefix)\(id)"), key.count == 32 else {
                return (403, WiFiReply("unpaired", message: "请在 Mac 允许这块手表"))
            }
            if request.path == "/v1/session" {
                guard let nonce = input.nonce.flatMap({ Data(base64Encoded: $0) }),
                      let proof = input.proof.flatMap({ Data(base64Encoded: $0) }),
                      WiFiWire.validProof(proof, id: id.uuidString, nonce: nonce, key: key) else {
                    return (403, WiFiReply("unpaired", message: "配对验证失败，请重新配对"))
                }
                if let session = sessions[id], session.clientNonce == nonce {
                    return (200, WiFiReply("ok", challenge: session.challenge.base64EncodedString()))
                }
                guard !controller.isRecording || controller.isFinishing else { return (409, WiFiReply("error", message: "请先结束当前听写")) }
                let challenge = try KeychainStore.random(count: 16)
                sessions[id] = Session(key: key, challenge: challenge, clientNonce: nonce); grants[id] = nil
                return (200, WiFiReply("ok", challenge: challenge.base64EncodedString()))
            }
            guard var session = sessions[id] else { return (403, WiFiReply("sessionExpired", message: "连接需要重新验证")) }
            if request.path == "/v1/audio" {
                guard owner == id, controller.isRecording, var gate = session.audioGate,
                      let packets = input.packets, !packets.isEmpty, packets.count <= 32 else {
                    return (409, WiFiReply("error", message: "当前没有此手表的录音会话"))
                }
                for packet in packets {
                    guard let data = Data(base64Encoded: packet) else { throw WireError.malformed }
                    let frame = try AudioWire.decode(data, key: session.key, challenge: session.challenge)
                    let gap = try gate.accept(frame)
                    if gap > 0 { try audio.enqueue([Int16](repeating: 0, count: gap)) }
                    try audio.enqueue(frame.samples)
                    if frame.ended { ConnectionTrace.record("audio", "Watch end marker received samples=\(frame.offset)") }
                }
                if session.audioGate?.nextOffset == 0 {
                    ConnectionTrace.record("audio", "first Watch audio batch received")
                }
                session.audioGate = gate; sessions[id] = session
                return (200, WiFiReply("ok"))
            }
            guard request.path == "/v1/command", let packet = input.packet.flatMap({ Data(base64Encoded: $0) }) else {
                return (404, WiFiReply("error", message: "未知请求"))
            }
            let command = try Wire.decode(packet, key: session.key, challenge: session.challenge)
            try session.gate.accept(command); sessions[id] = session
            let phase: HostPhase
            if controller.isRecording && owner != id { phase = .unavailable }
            else if command.action == .beginDictation {
                do {
                    try audio.start()
                    controller.drainBeforePreserving = { [weak audio] in
                        try? await audio?.drain(); audio?.stop()
                    }
                    phase = await controller.perform(.beginDictation)
                    if phase == .listening { owner = id; sessions[id]?.audioGate = AudioGate(stream: command.sequence) }
                    else { audio.stop() }
                } catch {
                    audio.stop(); controller.phase = .failed; controller.detail = error.localizedDescription; phase = .failed
                }
            } else if [.finishDictation, .finishReceivedAudio].contains(command.action), owner == id {
                do {
                    guard command.action == .finishReceivedAudio || sessions[id]?.audioGate?.ended == true else { throw LocalTLSIdentity.Failure("手表音频尚未完整结束") }
                    let started = ProcessInfo.processInfo.systemUptime
                    try await audio.drain()
                    ConnectionTrace.record("audio", String(format: "tail playback drained in %.0f ms", (ProcessInfo.processInfo.systemUptime - started) * 1000))
                    phase = await controller.perform(.finishDictation)
                } catch {
                    _ = await controller.perform(.finishReceivedAudio)
                    controller.phase = .failed; controller.detail = error.localizedDescription; phase = .failed
                }
                audio.stop(); sessions[id]?.audioGate = nil
            } else { phase = await controller.perform(command.action, value: command.value) }
            if !controller.isRecording { owner = nil; audio.stop() }
            if [.beginDictation, .finishDictation, .cancelDictation, .finishReceivedAudio].contains(command.action) {
                ConnectionTrace.record("audio", "\(command.action) phase=\(phase) samples=\(audio.receivedSamples) \(audio.captureSummary)")
            }
            let newStatus = "Wi-Fi 已连接 · \(phase.caption)"
            if status != newStatus { status = newStatus }
            return (200, WiFiReply("ok", message: controller.detail,
                                  packet: try Wire.status(phase, sequence: command.sequence, key: session.key,
                                                          challenge: session.challenge).base64EncodedString()))
        } catch {
            ConnectionTrace.record("wifi", "request failed path=\(request.path) samples=\(audio.receivedSamples) error=\(error.localizedDescription)")
            if request.path == "/v1/audio", owner == id {
                _ = await controller.perform(.finishReceivedAudio); audio.stop(); owner = nil
            }
            return (403, WiFiReply("error", message: "请求验证失败或音频传输中断"))
        }
    }
    private func pair(id: UUID, input: WiFiRequest) throws -> (Int, WiFiReply) {
        guard let ticket = input.ticket.flatMap({ Data(base64Encoded: $0) }), ticket.count == 32 else {
            return (400, WiFiReply("error", message: "配对请求格式错误"))
        }
        grants = grants.filter { $0.value.expires > Date() }
        if let grant = grants[id], grant.ticket == ticket,
           let key = try KeychainStore.read("\(accountPrefix)\(id)") {
            return (200, WiFiReply("ok", name: Host.current().localizedName ?? "Mac", key: key.base64EncodedString()))
        }
        guard pairingOpen, Date() < pairingUntil else {
            return (403, WiFiReply("pending", message: "在 Mac 点「允许 Wi-Fi 手表」"))
        }
        if pending == nil {
            pending = Pairing(id: id, ticket: ticket, expires: pairingUntil)
            pendingCode = WiFiWire.pairingCode(id: id.uuidString, ticket: ticket)
        }
        guard pending?.id == id, pending?.ticket == ticket else {
            return (409, WiFiReply("pending", message: "Mac 正在处理另一条配对请求"))
        }
        return (202, WiFiReply("pending", message: "请核对配对码，再在 Mac 允许这块手表"))
    }
}

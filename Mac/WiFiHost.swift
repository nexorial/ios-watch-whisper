import Foundation
import CryptoKit
import Network
import MicodexCore

@MainActor
final class WiFiHost: ObservableObject {
    @Published var status = "正在准备 Wi-Fi 直连…"
    @Published var address = ""
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
        var silence = SilenceEndpoint()
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
        if demo { status = "演示模式" } else {
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
                serviceIssue = "另一个 Micodex 接收端正在运行。请使用已打开的窗口；关闭它后，这里会自动接管。"
                status = "已有接收端"; scheduleRetry(); return
            }
            duplicateReceiver = false
            guard let host = LocalTLSIdentity.localAddress() else {
                address = ""; status = "尚未连接局域网"
                serviceIssue = "请将 Mac 连上 Wi-Fi；网络恢复后会自动连接。"
                scheduleRetry(); return
            }
            address = host
            let identity = try LocalTLSIdentity.prepare()
            let token = UUID(); serverEpoch = token
            let server = TLSHTTPServer { [weak self] request in
                guard let self else { return (503, WiFiReply("error", message: "接收端已退出")) }
                return await self.handle(request, epoch: token)
            }
            self.server = server
            status = "正在启动接收服务…"
            try server.start(identity: identity.identity, address: host, portNumber: port) { [weak self] event in
                Task { @MainActor in
                    guard let self, self.serverEpoch == token, !self.stopped else { return }
                    switch event {
                    case .ready:
                        self.serviceReady = true; self.serviceIssue = nil; self.retryAttempt = 0
                        self.status = "Wi-Fi 已就绪 · 等待手表"
                    case .waiting(let error), .failed(let error):
                        self.serviceReady = false
                        self.status = "接收服务暂不可用 · 自动重试中"
                        if case .posix(.EADDRINUSE) = error {
                            self.serviceIssue = "Mac 的接收端口被占用。请关闭其他 Micodex 或旧版 Watch Whisper；无需改手表 IP 或重新配对。端口释放后会自动恢复。"
                        } else {
                            self.serviceIssue = "请检查 Mac 的局域网连接和本地网络权限。服务会自动重试。详情：\(error.localizedDescription)"
                        }
                        ConnectionTrace.record("wifi-server", "port=\(self.port) listener error=\(error)")
                        self.retireServer(retry: true)
                    }
                }
            }
        } catch {
            serviceIssue = "接收服务启动失败：\(error.localizedDescription)"
            status = "接收服务暂不可用 · 自动重试中"
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
        status = "正在重新连接局域网…"
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
                owner = nil; playback.stop()
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
        playback.stop()
        Task {
            if wasRecording { _ = await controller.perform(.cancelDictation) }
            do {
                for id in ids { try KeychainStore.delete("\(accountPrefix)\(id)") }
                status = "Wi-Fi 配对已移除"
            } catch { status = "移除配对失败" }
        }
    }
    private func handle(_ request: HTTPEnvelope, epoch: UUID) async -> (Int, WiFiReply) {
        guard serverEpoch == epoch, serviceReady else { return (503, WiFiReply("error", message: "网络已刷新，请重新连接")) }
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
                guard !controller.isBusy, !sessions.values.contains(where: { $0.draining }),
                      !controller.isRecording || controller.isFinishing else { return (409, WiFiReply("error", message: "请先结束当前听写")) }
                let challenge = try KeychainStore.random(count: 16)
                sessions[id] = Session(key: key, challenge: challenge, clientNonce: nonce); grants[id] = nil
                return (200, WiFiReply("ok", challenge: challenge.base64EncodedString()))
            }
            guard var session = sessions[id] else { return (403, WiFiReply("sessionExpired", message: "连接需要重新验证")) }
            if request.path == "/v1/audio" {
                guard (owner == id && controller.isRecording) || session.finalized else {
                    return (409, WiFiReply("error", message: "当前没有此手表的录音会话"))
                }
                guard var gate = session.audioGate,
                      let packets = input.packets, !packets.isEmpty, packets.count <= 32 else {
                    return (409, WiFiReply("error", message: "当前没有此手表的录音会话"))
                }
                var endpoint: SilenceEndpoint.Reason?
                for packet in packets {
                    guard let data = Data(base64Encoded: packet) else { throw WireError.malformed }
                    let frame = try AudioWire.decode(data, key: session.key, challenge: session.challenge)
                    let gap = try gate.accept(frame)
                    // Validate late packets, but never feed them to a recording
                    // which is already being finalized. Gaps are not speech silence.
                    if !session.finalized {
                        if gap > 0 { try playback.enqueue([Int16](repeating: 0, count: gap)) }
                        try playback.enqueue(frame.samples)
                        if let reason = session.silence.consume(frame.samples) {
                            endpoint = reason; session.finalized = true; session.draining = true
                        }
                    }
                    if frame.ended { ConnectionTrace.record("audio", "Watch end marker received samples=\(frame.offset)") }
                }
                if session.audioGate?.nextOffset == 0 {
                    ConnectionTrace.record("audio", "first Watch audio batch received")
                }
                session.audioGate = gate; sessions[id] = session
                if let endpoint {
                    let challenge = session.challenge
                    ConnectionTrace.record("audio", "silence endpoint=\(endpoint) samples=\(playback.receivedSamples)")
                    Task { [weak self] in _ = await self?.finishAudio(id: id, challenge: challenge) }
                }
                return (200, WiFiReply("ok"))
            }
            guard request.path == "/v1/command", let packet = input.packet.flatMap({ Data(base64Encoded: $0) }) else {
                return (404, WiFiReply("error", message: "未知请求"))
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
                    return (409, WiFiReply("error", message: "请等上一次听写结束后再开始"))
                }
                do {
                    try playback.start()
                    controller.drainBeforePreserving = { [weak playback] in
                        try? await playback?.drain(); playback?.stop()
                    }
                    phase = await controller.perform(.beginDictation)
                    if phase == .listening {
                        owner = id; sessions[id]?.audioGate = AudioGate(stream: command.sequence)
                        sessions[id]?.silence = SilenceEndpoint(); sessions[id]?.finalized = false
                    }
                    else { playback.stop() }
                } catch {
                    playback.stop(); controller.phase = .failed; controller.detail = error.localizedDescription; phase = .failed
                }
            } else if [.finishDictation, .finishReceivedAudio].contains(command.action), owner == id {
                guard command.action == .finishReceivedAudio || sessions[id]?.audioGate?.ended == true else {
                    throw LocalTLSIdentity.Failure("手表音频尚未完整结束")
                }
                sessions[id]?.finalized = true; sessions[id]?.draining = true
                phase = await finishAudio(id: id, challenge: session.challenge)
            } else { phase = await controller.perform(command.action, value: command.value) }
            if !controller.isRecording { owner = nil; playback.stop() }
            if [.beginDictation, .finishDictation, .cancelDictation, .finishReceivedAudio].contains(command.action) {
                ConnectionTrace.record("audio", "\(command.action) phase=\(phase) samples=\(playback.receivedSamples) \(playback.captureSummary)")
            }
            let newStatus = "Wi-Fi 已连接 · \(phase.caption)"
            if status != newStatus { status = newStatus }
            return (200, WiFiReply("ok", message: controller.detail,
                                  packet: try Wire.status(phase, sequence: command.sequence, key: session.key,
                                                          challenge: session.challenge).base64EncodedString()))
        } catch {
            ConnectionTrace.record("wifi", "request failed path=\(request.path) samples=\(playback.receivedSamples) error=\(error.localizedDescription)")
            if request.path == "/v1/audio", owner == id {
                if sessions[id]?.finalized == false {
                    sessions[id]?.finalized = true; sessions[id]?.draining = true
                    _ = await finishAudio(id: id, challenge: sessions[id]!.challenge)
                }
            }
            return (403, WiFiReply("error", message: "请求验证失败或音频传输中断"))
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
        status = "Wi-Fi 已连接 · \(phase.caption)"
        return phase
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

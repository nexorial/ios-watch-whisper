import Foundation
import WatchKit
import WhisperCore

@MainActor
final class WatchWiFiConnection: ObservableObject {
    @Published var connected = false
    @Published var status = "正在通过 Wi-Fi 寻找 Mac…"
    @Published var phase: HostPhase = .ready
    @Published var macName = "Mac"
    @Published var pairingCode: String?
    @Published var microphoneLevel = ""
    private let client: PinnedHTTPSClient
    private let account: String
    private let id: UUID
    private let microphone = WatchMicrophone()
    private var active = true
    private var epoch = UUID()
    private var key: Data?
    private var challenge: Data?
    private var ticket: Data?
    private var sequence: UInt32 = 0
    private var connecting: Task<Void, Never>?
    private var controlTask: Task<Void, Never>?
    private var micTask: Task<Void, Never>?
    private var audioTask: Task<Void, Never>?
    private var audioEpoch = UUID()
    private var heartbeats: Task<Void, Never>?
    private var queue: [(RemoteAction, Int16)] = []
    private var samples: [Int16] = []
    private var audioPackets: [Data] = []
    private var stream: UInt32 = 0
    private var audioSequence: UInt32 = 0
    private var audioOffset: UInt32 = 0
    private var recordingRequested = false
    private var audioAccepted = false
    private var finishing = false
    static var configuration: (String, String)? {
        let host = UserDefaults.standard.string(forKey: "wifiHostOverride")
            ?? (Bundle.main.object(forInfoDictionaryKey: "WatchWhisperWiFiHost") as? String ?? "")
        let pin = Bundle.main.object(forInfoDictionaryKey: "WatchWhisperWiFiPin") as? String ?? ""
        guard !host.isEmpty, pin.count == 64, pin.allSatisfy({ $0.isHexDigit }) else { return nil }
        return (host, pin)
    }
    init(host: String, pin: String) throws {
        client = try PinnedHTTPSClient(host: host, fingerprint: pin)
        account = "wifi-mac-\(pin)"
        if let raw = UserDefaults.standard.string(forKey: "wifiWatchID"), let value = UUID(uuidString: raw) { id = value }
        else { let value = UUID(); id = value; UserDefaults.standard.set(value.uuidString, forKey: "wifiWatchID") }
        key = try KeychainStore.read(account)
        heartbeats = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                if self.active && self.connected && self.controlTask == nil && self.queue.isEmpty { self.enqueue(.heartbeat) }
            }
        }
        connect()
    }
    func connect() {
        guard active, !connected, connecting == nil else { return }
        let token = epoch
        connecting = Task { [weak self] in
            guard let self else { return }
            defer { if self.epoch == token { self.connecting = nil } }
            while self.active && self.epoch == token && !Task.isCancelled && !self.connected {
                do {
                    let hello = try await self.client.request("v1/hello")
                    try self.check(token)
                    guard hello.status == "ok" else { throw Failure("Mac Wi-Fi 服务不可用") }
                    self.macName = hello.name ?? "Mac"
                    if self.key == nil {
                        if self.ticket == nil { self.ticket = try KeychainStore.random(count: 32) }
                        let ticket = self.ticket!
                        self.pairingCode = WiFiWire.pairingCode(id: self.id.uuidString, ticket: ticket)
                        let reply = try await self.client.request("v1/pair", WiFiRequest(id: self.id.uuidString, ticket: ticket.base64EncodedString()))
                        try self.check(token)
                        guard reply.status == "ok", let key = reply.key.flatMap({ Data(base64Encoded: $0) }), key.count == 32 else {
                            self.status = reply.message ?? "请在 Mac 允许 Wi-Fi 手表"
                            try await Task.sleep(nanoseconds: 1_500_000_000); continue
                        }
                        try KeychainStore.save(key, account: self.account); self.key = key; self.pairingCode = nil
                    }
                    let nonce = try KeychainStore.random(count: 16), key = self.key!
                    let reply = try await self.client.request("v1/session", WiFiRequest(id: self.id.uuidString,
                        nonce: nonce.base64EncodedString(), proof: WiFiWire.sessionProof(id: self.id.uuidString, nonce: nonce, key: key).base64EncodedString()))
                    try self.check(token)
                    if reply.status == "unpaired" {
                        try KeychainStore.delete(self.account); self.key = nil; self.ticket = nil; continue
                    }
                    guard reply.status == "ok", let challenge = reply.challenge.flatMap({ Data(base64Encoded: $0) }), challenge.count == 16 else {
                        throw Failure(reply.message ?? "Mac 会话未准备好")
                    }
                    self.challenge = challenge; self.sequence = 1
                    let heartbeat = try Wire.encode(Command(.heartbeat, sequence: 1), key: key, challenge: challenge)
                    let acknowledgement = try await self.client.request("v1/command", WiFiRequest(id: self.id.uuidString, packet: heartbeat.base64EncodedString()))
                    try self.check(token)
                    guard let data = acknowledgement.packet.flatMap({ Data(base64Encoded: $0) }) else { throw Failure("Mac 未确认连接") }
                    let (phase, sequence) = try Wire.decodeStatus(data, key: key, challenge: challenge)
                    guard sequence == 1 else { throw WireError.replay }
                    self.connected = true; self.phase = phase; self.status = "Wi-Fi 已连接 \(self.macName)"
                    ConnectionTrace.record("wifi", "authenticated HTTPS heartbeat received")
                } catch {
                    guard self.epoch == token, !Task.isCancelled else { return }
                    self.status = "Wi-Fi 连接失败：\(error.localizedDescription)"
                    ConnectionTrace.record("wifi", self.status)
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
    }
    func setActive(_ value: Bool) {
        active = value
        if value { connect() }
        else { reset(sendCancel: true); status = "抬腕后恢复 Wi-Fi 连接" }
    }
    func forget() {
        reset(sendCancel: true); try? KeychainStore.delete(account)
        key = nil; ticket = nil; pairingCode = nil; status = "正在重新配对 Wi-Fi…"; connect()
    }
    func send(_ action: RemoteAction, value: Int16 = 0) {
        guard connected else { return }
        if action == .beginDictation {
            guard !recordingRequested else { return }
            clearAudio(); recordingRequested = true; status = "正在开启 Watch 麦克风…"
            microphoneLevel = "正在开启 Watch 麦克风…"
            let token = epoch
            micTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.microphone.start(onFailure: { [weak self] in self?.fail($0) }) { [weak self] in self?.capture($0) }
                    try self.check(token)
                    guard self.recordingRequested else { self.microphone.stop(); return }
                    self.enqueue(.beginDictation)
                } catch {
                    guard self.epoch == token, !Task.isCancelled else { return }
                    self.clearAudio(); self.phase = .failed; self.status = error.localizedDescription
                }
            }
        } else if action == .finishDictation || (action == .enter && recordingRequested) {
            guard recordingRequested else { enqueue(action); return }
            guard !finishing else { return }
            microphone.stop(); finishing = true
            if stream == 0 {
                queue.removeAll { $0.0 == .beginDictation }; clearAudio(); return
            }
            packAudio(ending: true); drainAudio()
        } else if action == .cancelDictation { clearAudio(); enqueue(action) }
        else { enqueue(action, value: value) }
    }
    private func enqueue(_ action: RemoteAction, value: Int16 = 0) {
        if action == .heartbeat && (!queue.isEmpty || controlTask != nil) { return }
        if action == .scroll, let last = queue.last, last.0 == .scroll {
            queue[queue.count - 1].1 = Int16(max(-600, min(600, Int(last.1) + Int(value))))
        } else {
            if queue.count >= 12 { queue.removeAll { $0.0 == .scroll || $0.0 == .heartbeat } }
            guard queue.count < 16 else { fail("指令积压，已停止"); return }
            queue.append((action, value))
        }
        drainControls()
    }
    private func drainControls() {
        guard connected, controlTask == nil, let key, let challenge else { return }
        let token = epoch
        controlTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.epoch == token { self.controlTask = nil } }
            while !self.queue.isEmpty && self.connected && !Task.isCancelled {
                let (action, value) = self.queue.removeFirst()
                self.sequence += 1; let sequence = self.sequence
                if action == .beginDictation { self.stream = sequence; self.packAudio() }
                do {
                    let packet = try Wire.encode(Command(action, sequence: sequence, value: value), key: key, challenge: challenge)
                    let reply = try await self.client.request("v1/command", WiFiRequest(id: self.id.uuidString, packet: packet.base64EncodedString()))
                    try self.check(token)
                    guard reply.status == "ok", let data = reply.packet.flatMap({ Data(base64Encoded: $0) }) else {
                        throw Failure(reply.message ?? "Mac 未确认操作")
                    }
                    let (phase, returnedSequence) = try Wire.decodeStatus(data, key: key, challenge: challenge)
                    guard sequence == returnedSequence else { throw WireError.replay }
                    self.phase = phase; self.status = reply.message ?? phase.caption
                    if action == .beginDictation {
                        if phase == .listening { self.audioAccepted = true; self.drainAudio(); WKInterfaceDevice.current().play(.start) }
                        else { self.clearAudio() }
                    } else if action == .finishDictation || action == .cancelDictation { self.clearAudio(); WKInterfaceDevice.current().play(.stop) }
                    else if [.failed, .unavailable, .permissionRequired].contains(phase) || (self.audioAccepted && phase != .listening) { self.clearAudio() }
                } catch {
                    guard self.epoch == token, !Task.isCancelled else { return }
                    self.fail("Wi-Fi 操作失败：\(error.localizedDescription)"); return
                }
            }
        }
    }
    private func capture(_ chunk: [Int16]) {
        guard recordingRequested, !finishing else { return }
        var level = AudioLevel(); level.append(chunk); microphoneLevel = level.caption
        guard Int(audioOffset) + samples.count + chunk.count <= 1_920_000,
              samples.count + chunk.count <= 32_000, audioPackets.count < 80 else { fail("音频积压或录音达到上限"); return }
        samples.append(contentsOf: chunk); packAudio(); drainAudio()
    }
    private func packAudio(ending: Bool = false) {
        guard stream > 0, let key, let challenge else { return }
        do {
            while samples.count >= 512 || (ending && !samples.isEmpty) {
                let count = min(512, samples.count), block = Array(samples.prefix(512))
                samples.removeFirst(count); audioSequence += 1
                audioPackets.append(try AudioWire.encode(samples: block, stream: stream, sequence: audioSequence,
                                                       offset: audioOffset, key: key, challenge: challenge))
                audioOffset += UInt32(count)
            }
            if ending {
                audioSequence += 1
                audioPackets.append(try AudioWire.encode(samples: [], stream: stream, sequence: audioSequence,
                                                       offset: audioOffset, ended: true, key: key, challenge: challenge))
            }
        } catch { fail("音频编码失败") }
    }
    private func drainAudio() {
        guard audioAccepted, audioTask == nil else { return }
        let token = epoch, audioToken = audioEpoch
        audioTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.epoch == token && self.audioEpoch == audioToken { self.audioTask = nil } }
            do {
                while !self.audioPackets.isEmpty && !Task.isCancelled {
                    let batch = Array(self.audioPackets.prefix(20)); self.audioPackets.removeFirst(batch.count)
                    let reply = try await self.client.request("v1/audio", WiFiRequest(id: self.id.uuidString,
                                                                                   packets: batch.map { $0.base64EncodedString() }))
                    try self.check(token)
                    guard self.audioEpoch == audioToken else { throw CancellationError() }
                    guard reply.status == "ok" else { throw Failure(reply.message ?? "音频未被接收") }
                }
                if self.finishing && self.audioPackets.isEmpty {
                    self.finishing = false; self.recordingRequested = false; self.phase = .transcribing
                    self.enqueue(.finishDictation)
                }
            } catch {
                guard self.epoch == token, !Task.isCancelled else { return }
                self.fail("Wi-Fi 音频中断：\(error.localizedDescription)")
            }
        }
    }
    private func clearAudio() {
        audioEpoch = UUID()
        micTask?.cancel(); micTask = nil; microphone.stop(); audioTask?.cancel(); audioTask = nil
        samples = []; audioPackets = []; stream = 0; audioSequence = 0; audioOffset = 0
        recordingRequested = false; finishing = false; audioAccepted = false
    }
    private func reset(sendCancel: Bool) {
        if sendCancel, connected, let key, let challenge {
            sequence += 1
            if let packet = try? Wire.encode(Command(.cancelDictation, sequence: sequence), key: key, challenge: challenge) {
                let client = client, id = id.uuidString
                Task { _ = try? await client.request("v1/command", WiFiRequest(id: id, packet: packet.base64EncodedString())) }
            }
        }
        epoch = UUID(); connecting?.cancel(); connecting = nil; controlTask?.cancel(); controlTask = nil
        clearAudio(); queue = []; challenge = nil; connected = false; phase = .ready
    }
    private func fail(_ message: String) {
        reset(sendCancel: true); status = message; phase = .failed
        ConnectionTrace.record("wifi", message); WKInterfaceDevice.current().play(.failure)
        Task { [weak self] in try? await Task.sleep(nanoseconds: 2_000_000_000); self?.connect() }
    }
    private func check(_ token: UUID) throws {
        try Task.checkCancellation()
        guard epoch == token, active else { throw CancellationError() }
    }
    private struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

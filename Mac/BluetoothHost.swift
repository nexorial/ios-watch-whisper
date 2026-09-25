import Foundation
import CoreBluetooth
import WhisperCore

@MainActor
// CoreBluetooth delivers every delegate callback on the explicitly selected main queue.
final class BluetoothHost: NSObject, ObservableObject, @preconcurrency CBPeripheralManagerDelegate {
    @Published var connection = "蓝牙未启动"
    @Published var pendingWatch: String?
    @Published var pairingOpen = false
    @Published var pairedCount = 0
    private var manager: CBPeripheralManager!
    private var statusCharacteristic: CBMutableCharacteristic!
    let audio = WatchAudioOutput()
    private let controller: AgentController
    private var sessions: [UUID: Session] = [:]
    private var pairingUntil = Date.distantPast
    private var approvedIDs: [String] { get { UserDefaults.standard.stringArray(forKey: "pairedWatches") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "pairedWatches"); pairedCount = newValue.count } }
    private var pendingCentral: UUID?
    private var owner: UUID?
    private var work: [(CBCentral, Command)] = []
    private var draining = false
    private var pendingNotifications: [(Data, CBCentral)] = []
    private let demo: Bool
    private struct Session { var key: Data; var nonce: Data; var gate = ReplayGate(); var audioGate: AudioGate? }

    init(controller: AgentController, demo: Bool = false) {
        self.controller = controller; self.demo = demo
        super.init()
        pairedCount = approvedIDs.count
        if demo { connection = "演示模式 · 无蓝牙连接" }
        else { manager = CBPeripheralManager(delegate: self, queue: .main) }
    }
    func allowPairing() {
        pairingUntil = Date().addingTimeInterval(60); pairingOpen = true
        connection = "60 秒内在手表选择这台 Mac"
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard let self, self.pairingUntil <= Date() else { return }
            self.pairingOpen = false; self.pendingWatch = nil; self.pendingCentral = nil
        }
    }
    func approve() {
        guard pairingOpen, Date() < pairingUntil, let id = pendingCentral else { return }
        do {
            try KeychainStore.save(KeychainStore.random(count: 32), account: "watch-\(id)")
            var ids = approvedIDs; if !ids.contains(id.uuidString) { ids.append(id.uuidString) }; approvedIDs = ids
            pendingWatch = nil; pendingCentral = nil; pairingOpen = false
            connection = "已允许这块手表，正在建立加密连接…"
        } catch { connection = "无法保存配对密钥：\(error.localizedDescription)" }
    }
    func revokeAll() {
        Task {
            _ = await controller.perform(.cancelDictation)
            do {
                for id in approvedIDs { try KeychainStore.delete("watch-\(id)") }
                approvedIDs = []; sessions = [:]; owner = nil; work = []; pendingNotifications = []
                connection = "已移除配对，请在手表也点忘记 Mac"
            } catch { connection = "移除配对失败：\(error.localizedDescription)" }
        }
    }
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else {
            connection = peripheral.state == .unauthorized ? "请在系统设置允许蓝牙" : "请打开 Mac 蓝牙"
            audio.stop(); sessions = [:]; work = []; owner = nil
            Task { _ = await controller.perform(.cancelDictation) }
            return
        }
        let service = CBMutableService(type: CBUUID(string: Wire.service), primary: true)
        let pair = CBMutableCharacteristic(type: CBUUID(string: Wire.pairing), properties: [.read], value: nil, permissions: [.readable, .readEncryptionRequired])
        let challenge = CBMutableCharacteristic(type: CBUUID(string: Wire.challenge), properties: [.read], value: nil, permissions: [.readable])
        let command = CBMutableCharacteristic(type: CBUUID(string: Wire.command), properties: [.write], value: nil, permissions: [.writeable, .writeEncryptionRequired])
        statusCharacteristic = CBMutableCharacteristic(type: CBUUID(string: Wire.status), properties: [.notify, .notifyEncryptionRequired], value: nil, permissions: [.readable])
        let audioStream = CBMutableCharacteristic(type: CBUUID(string: AudioWire.characteristic),
            properties: [.writeWithoutResponse], value: nil, permissions: [.writeable, .writeEncryptionRequired])
        service.characteristics = [pair, challenge, command, statusCharacteristic, audioStream]
        peripheral.removeAllServices(); peripheral.add(service)
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil else { connection = "蓝牙服务失败：\(error!.localizedDescription)"; return }
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: Wire.service)],
                                     CBAdvertisementDataLocalNameKey: "Whisper · \(Host.current().localizedName ?? "Mac")"])
    }
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        connection = error == nil ? "等待已配对手表 · 蓝牙直连" : "广播失败：\(error!.localizedDescription)"
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        let id = request.central.identifier
        let uuid = request.characteristic.uuid
        do {
            let payload: Data
            if uuid == CBUUID(string: Wire.pairing) {
                guard approvedIDs.contains(id.uuidString), let key = try KeychainStore.read("watch-\(id)") else {
                    if pairingOpen && Date() < pairingUntil && (pendingCentral == nil || pendingCentral == id) {
                        pendingCentral = id; pendingWatch = String(id.uuidString.prefix(8))
                        connection = "手表请求配对，请核对手表上的请求后允许"
                    }
                    peripheral.respond(to: request, withResult: .insufficientAuthorization); return
                }
                payload = key
            } else if uuid == CBUUID(string: Wire.challenge) {
                guard approvedIDs.contains(id.uuidString), let key = try KeychainStore.read("watch-\(id)") else {
                    peripheral.respond(to: request, withResult: .insufficientAuthorization); return
                }
                // Long reads must not rotate the nonce at nonzero offsets.
                if request.offset == 0 {
                    guard !controller.isRecording || owner != id else {
                        peripheral.respond(to: request, withResult: .unlikelyError); return
                    }
                    sessions[id] = Session(key: key, nonce: try KeychainStore.random(count: 16))
                }
                guard let session = sessions[id] else { peripheral.respond(to: request, withResult: .unlikelyError); return }
                payload = session.nonce
            } else { peripheral.respond(to: request, withResult: .requestNotSupported); return }
            guard request.offset <= payload.count else { peripheral.respond(to: request, withResult: .invalidOffset); return }
            request.value = payload.subdata(in: request.offset..<payload.count)
            peripheral.respond(to: request, withResult: .success)
        } catch { peripheral.respond(to: request, withResult: .unlikelyError); connection = "配对数据不可用" }
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests where request.characteristic.uuid == CBUUID(string: AudioWire.characteristic) { receiveAudio(request) }
        let requests = requests.filter { $0.characteristic.uuid != CBUUID(string: AudioWire.characteristic) }
        guard !requests.isEmpty else { return }
        // Watch sends one 20-byte write-with-response at a time.
        guard requests.count == 1, let request = requests.first else {
            if let first = requests.first { peripheral.respond(to: first, withResult: .invalidAttributeValueLength) }; return
        }
        let id = request.central.identifier
        guard request.characteristic.uuid == CBUUID(string: Wire.command), request.offset == 0,
              let data = request.value, var session = sessions[id], approvedIDs.contains(id.uuidString) else {
            peripheral.respond(to: request, withResult: .insufficientAuthorization); return
        }
        do {
            let command = try Wire.decode(data, key: session.key, challenge: session.nonce)
            try session.gate.accept(command); sessions[id] = session
            guard work.count < 16 else { peripheral.respond(to: request, withResult: .insufficientResources); return }
            work.append((request.central, command))
            peripheral.respond(to: request, withResult: .success)
            drain()
        } catch { peripheral.respond(to: request, withResult: .insufficientAuthorization) }
    }
    private func receiveAudio(_ request: CBATTRequest) {
        let id = request.central.identifier
        guard owner == id, controller.isRecording, request.offset == 0,
              let data = request.value, var session = sessions[id], var gate = session.audioGate else { return }
        do {
            let frame = try AudioWire.decode(data, key: session.key, challenge: session.nonce)
            let gap = try gate.accept(frame)
            session.audioGate = gate; sessions[id] = session
            if gap > 0 { try audio.enqueue([Int16](repeating: 0, count: gap)) }
            try audio.enqueue(frame.samples)
        } catch WireError.replay { return }
        catch {
            audio.stop(); sessions[id]?.audioGate = nil
            Task {
                _ = await controller.perform(.cancelDictation)
                controller.phase = .failed; controller.detail = "Watch 音频传输失败：\(error.localizedDescription)"
            }
        }
    }
    private func drain() {
        guard !draining else { return }; draining = true
        Task {
            while !work.isEmpty {
                let (central, command) = work.removeFirst()
                guard let session = sessions[central.identifier] else { continue }
                let phase: HostPhase
                if controller.isRecording, let owner, owner != central.identifier {
                    phase = .unavailable
                } else {
                    if command.action == .beginDictation {
                        do {
                            try audio.start()
                            phase = await controller.perform(command.action, value: command.value)
                            if phase == .listening {
                                owner = central.identifier
                                sessions[central.identifier]?.audioGate = AudioGate(stream: command.sequence)
                            } else { audio.stop() }
                        } catch {
                            audio.stop(); controller.phase = .failed; controller.detail = error.localizedDescription
                            phase = .failed
                        }
                    } else if command.action == .finishDictation, owner == central.identifier {
                        do {
                            guard sessions[central.identifier]?.audioGate?.ended == true else {
                                throw WatchAudioOutput.AudioFailure("手表音频未完整结束，已取消听写，请重试。")
                            }
                            try await audio.drain()
                            phase = await controller.perform(.finishDictation)
                        } catch {
                            _ = await controller.perform(.cancelDictation)
                            controller.phase = .failed; controller.detail = error.localizedDescription; phase = .failed
                        }
                        audio.stop(); sessions[central.identifier]?.audioGate = nil
                    } else {
                        phase = await controller.perform(command.action, value: command.value)
                    }
                    if !controller.isRecording { owner = nil; audio.stop() }

                }
                if let data = try? Wire.status(phase, sequence: command.sequence, key: session.key, challenge: session.nonce) {
                    if !manager.updateValue(data, for: statusCharacteristic, onSubscribedCentrals: [central]) {
                        pendingNotifications.append((data, central))
                    }
                }
                connection = "手表已连接 · \(phase.caption)"
            }
            draining = false
        }
    }
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        while let item = pendingNotifications.first {
            guard peripheral.updateValue(item.0, for: statusCharacteristic, onSubscribedCentrals: [item.1]) else { return }
            pendingNotifications.removeFirst()
        }
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        sessions[central.identifier] = nil
        work.removeAll { $0.0.identifier == central.identifier }
        pendingNotifications.removeAll { $0.1.identifier == central.identifier }
        if owner == central.identifier {
            audio.stop()
            Task { _ = await controller.perform(.cancelDictation); owner = nil }
        }
        connection = "手表已断开 · 等待自动重连"
    }
}

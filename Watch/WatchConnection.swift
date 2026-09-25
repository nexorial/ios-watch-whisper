import Foundation
import CoreBluetooth
import WatchKit
import WhisperCore

@MainActor
// Both managers and peripherals deliver callbacks on our central manager's main queue.
final class WatchConnection: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    struct NearbyMac: Identifiable { let id: UUID; let name: String; let peripheral: CBPeripheral }
    @Published var nearby: [NearbyMac] = []
    @Published var connected = false
    @Published var status = "正在寻找 Mac…"
    @Published var phase: HostPhase = .ready
    @Published var macName = "Mac"
    @Published var demo = false
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristics: [CBUUID: CBCharacteristic] = [:]
    private var key: Data?
    private var challenge: Data?
    private var sequence: UInt32 = 0
    private var queue: [(RemoteAction, Int16)] = []
    private var inflight: Command?
    private var timeout: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var pairAttempts = 0
    private var active = true
    private var lastError: String?
    private let microphone = WatchMicrophone()
    private var microphoneTask: Task<Void, Never>?
    private var audioStream: UInt32 = 0
    private var audioSequence: UInt32 = 0
    private var audioOffset: UInt32 = 0
    private var audioSamples: [Int16] = []
    private var audioPackets: [Data] = []
    private var audioAccepted = false
    private var recordingRequested = false
    private var finishRequested = false
    private var audioTimeout: Task<Void, Never>?
    private var savedID: UUID? {
        get { UserDefaults.standard.string(forKey: "macID").flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "macID") }
    }

    override init() {
        super.init()
        if ProcessInfo.processInfo.arguments.contains("--demo") { enableDemo(); return }
        central = CBCentralManager(delegate: self, queue: .main)
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                if self.active && self.connected && self.queue.isEmpty && self.inflight == nil { self.send(.heartbeat) }
            }
        }
    }
    func enableDemo() {
        central?.stopScan()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        reset(); demo = true; connected = true; macName = "演示 Mac"; status = "界面演示 · 不控制 Mac"
    }
    func choose(_ mac: NearbyMac) {
        guard !demo else { return }
        retryTask?.cancel(); lastError = nil
        central.stopScan(); peripheral = mac.peripheral; peripheral?.delegate = self
        macName = mac.name; status = "正在连接 \(mac.name)…"
        central.connect(mac.peripheral)
        armConnectTimeout(mac.peripheral)
    }
    func forget() {
        retryTask?.cancel(); timeout?.cancel()
        if let id = savedID { try? KeychainStore.delete("mac-\(id)") }
        savedID = nil; demo = false; connected = false
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil; nearby = []; reset()
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else { discover() }
    }
    func setActive(_ active: Bool) {
        self.active = active
        if active { if !connected && !demo { discover() } }
        else {
            // Stop intent is sent even if start acknowledgement is still pending.
            if connected { send(.cancelDictation) }
            central?.stopScan()
            retryTask?.cancel()
        }
    }
    func send(_ action: RemoteAction, value: Int16 = 0) {
        guard connected, !demo else { sendCommand(action, value: value); return }
        if action == .beginDictation {
            guard !recordingRequested else { return }
            guard characteristics[CBUUID(string: AudioWire.characteristic)] != nil,
                  let peripheral, peripheral.maximumWriteValueLength(for: .withoutResponse) >= 64 else {
                status = "请更新 Mac 接收端；当前连接不支持手表音频。"; phase = .failed; return
            }
            clearAudio(); recordingRequested = true; status = "正在开启 Watch 麦克风…"
            microphoneTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.microphone.start { [weak self] in self?.capture($0) }
                    guard !Task.isCancelled, self.recordingRequested else { self.microphone.stop(); return }
                    self.sendCommand(.beginDictation)
                } catch {
                    guard !Task.isCancelled else { return }
                    self.clearAudio(); self.status = error.localizedDescription; self.phase = .failed
                }
            }
        } else if action == .finishDictation || (action == .enter && recordingRequested) {
            guard recordingRequested else { sendCommand(action, value: value); return }
            guard !finishRequested else { return }
            microphone.stop(); finishRequested = true
            if audioStream == 0 { microphoneTask?.cancel(); clearAudio(); return }
            flushAudio(ending: true); drainAudio()
            audioTimeout?.cancel()
            audioTimeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled, let self, self.finishRequested else { return }
                self.send(.cancelDictation); self.status = "音频发送超时，请重试。"; self.phase = .failed
            }
        } else if action == .cancelDictation {
            clearAudio(); sendCommand(action)
        } else { sendCommand(action, value: value) }
    }
    private func capture(_ samples: [Int16]) {
        guard recordingRequested, !finishRequested else { return }
        guard Int(audioOffset) + audioSamples.count + samples.count <= AudioWire.sampleRate * 120,
              audioSamples.count + samples.count <= 32000, audioPackets.count < 100 else {
            send(.cancelDictation); status = "录音达到上限或蓝牙积压，已停止。"; phase = .failed; return
        }
        audioSamples.append(contentsOf: samples); flushAudio(); drainAudio()
    }
    private func flushAudio(ending: Bool = false) {
        guard audioStream > 0, let peripheral, let key, let challenge else { return }
        let capacity = min(512, (peripheral.maximumWriteValueLength(for: .withoutResponse) - AudioWire.overhead) * 2)
        guard capacity > 0 else { return }
        do {
            while audioSamples.count >= capacity || (ending && !audioSamples.isEmpty) {
                let count = min(capacity, audioSamples.count)
                let samples = Array(audioSamples.prefix(count)); audioSamples.removeFirst(count); audioSequence += 1
                audioPackets.append(try AudioWire.encode(samples: samples, stream: audioStream, sequence: audioSequence,
                                                       offset: audioOffset, key: key, challenge: challenge))
                audioOffset += UInt32(count)
            }
            if ending {
                audioSequence += 1
                audioPackets.append(try AudioWire.encode(samples: [], stream: audioStream, sequence: audioSequence,
                                                       offset: audioOffset, ended: true, key: key, challenge: challenge))
            }
        } catch { send(.cancelDictation); status = "音频编码失败"; phase = .failed }
    }
    private func drainAudio() {
        guard audioAccepted, let peripheral, let characteristic = characteristics[CBUUID(string: AudioWire.characteristic)] else { return }
        while peripheral.canSendWriteWithoutResponse && !audioPackets.isEmpty {
            peripheral.writeValue(audioPackets.removeFirst(), for: characteristic, type: .withoutResponse)
        }
        if finishRequested && audioPackets.isEmpty {
            finishRequested = false; recordingRequested = false; audioTimeout?.cancel()
            sendCommand(.finishDictation)
        }
    }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) { drainAudio() }
    private func clearAudio() {
        microphoneTask?.cancel(); microphoneTask = nil; microphone.stop(); audioTimeout?.cancel()
        audioStream = 0; audioSequence = 0; audioOffset = 0; audioSamples = []; audioPackets = []
        audioAccepted = false; recordingRequested = false; finishRequested = false
    }
    private func sendCommand(_ action: RemoteAction, value: Int16 = 0) {
        guard connected else { return }
        if demo {
            switch action {
            case .beginDictation: phase = .listening
            case .finishDictation:
                if phase == .listening {
                    phase = .transcribing
                    Task { try? await Task.sleep(nanoseconds: 600_000_000); phase = .ready }
                }
            case .cancelDictation: phase = .ready
            case .enter: status = "演示：已点击 Enter"; WKInterfaceDevice.current().play(.success)
            case .scroll: status = value >= 0 ? "演示：向下滚动" : "演示：向上滚动"
            case .heartbeat: break
            }
            return
        }
        if action == .scroll, let last = queue.last, last.0 == .scroll {
            queue[queue.count - 1].1 = Int16(max(-600, min(600, Int(last.1) + Int(value))))
        } else {
            if action == .heartbeat && (!queue.isEmpty || inflight != nil) { return }
            // Never let crown traffic crowd out stop/Enter commands.
            if queue.count >= 12 { queue.removeAll { $0.0 == .scroll || $0.0 == .heartbeat } }
            guard queue.count < 16 else { fail("指令过多，已断开；请重新连接"); return }
            queue.append((action, value))
        }
        drain()
    }
    private func drain() {
        guard connected, inflight == nil, !queue.isEmpty, let peripheral,
              let characteristic = characteristics[CBUUID(string: Wire.command)], let key, let challenge else { return }
        guard sequence < UInt32.max else { fail("连接需要更新，请重连"); return }
        sequence += 1
        let next = queue.removeFirst(); let command = Command(next.0, sequence: sequence, value: next.1)
        do {
            let data = try Wire.encode(command, key: key, challenge: challenge)
            inflight = command
            if command.action == .beginDictation { audioStream = command.sequence; flushAudio() }
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
            timeout?.cancel()
            timeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled, let self, self.inflight?.sequence == command.sequence else { return }
                self.fail("Mac 没有确认操作，已断开；指令不会重发")
            }
        } catch { fail("无法认证指令，请重新配对") }
    }
    private func reset() {
        clearAudio()
        connected = false; key = nil; challenge = nil; sequence = 0
        queue = []; inflight = nil; characteristics = [:]
        timeout?.cancel(); timeout = nil; phase = .ready; pairAttempts = 0
    }
    private func fail(_ message: String) {
        clearAudio()
        lastError = message; status = message; connected = false
        queue = []; inflight = nil; timeout?.cancel()
        WKInterfaceDevice.current().play(.failure)
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
    }
    private func discover() {
        guard !demo, active, central?.state == .poweredOn else { return }
        guard peripheral?.state != .connecting, peripheral?.state != .connected else { return }
        if let id = savedID, let known = central.retrievePeripherals(withIdentifiers: [id]).first {
            choose(NearbyMac(id: id, name: known.name ?? "已配对 Mac", peripheral: known))
        } else {
            status = lastError ?? "在 Mac 点「允许新手表」"
            central.scanForPeripherals(withServices: [CBUUID(string: Wire.service)], options: nil)
        }
    }
    private func armConnectTimeout(_ p: CBPeripheral) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled, let self, !self.connected, p.state == .connecting else { return }
            self.fail("Mac 暂时不可达，正在等待重连…")
        }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { discover() }
        else {
            reset()
            status = central.state == .unauthorized ? "请在手表设置允许蓝牙" : "请打开手表蓝牙"
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Whisper Mac"
        let mac = NearbyMac(id: peripheral.identifier, name: name, peripheral: peripheral)
        if !nearby.contains(where: { $0.id == mac.id }) { nearby.append(mac) }
        if savedID == mac.id { choose(mac) }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        timeout?.cancel(); reset(); self.peripheral = peripheral; peripheral.delegate = self
        status = "正在验证配对…"
        peripheral.discoverServices([CBUUID(string: Wire.service)])
        // Discovery and authorization must not hang indefinitely either.
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 90_000_000_000)
            guard !Task.isCancelled, let self, !self.connected else { return }
            self.fail("配对超时，请在 Mac 允许后重试")
        }
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        reset(); self.peripheral = nil; status = "暂时无法连接 Mac"; scheduleReconnect()
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard !demo else { return }
        reset(); self.peripheral = nil; status = lastError ?? "连接中断，正在重连…"
        scheduleReconnect()
    }
    private func scheduleReconnect() {
        retryTask?.cancel()
        guard active else { return }
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.discover()
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: Wire.service) }) else {
            fail("Mac 的服务不可用，请重启接收端"); return
        }
        peripheral.discoverCharacteristics(nil, for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { fail("无法读取 Mac 服务"); return }
        for characteristic in service.characteristics ?? [] { characteristics[characteristic.uuid] = characteristic }
        guard [Wire.pairing, Wire.challenge, Wire.command, Wire.status].allSatisfy({ characteristics[CBUUID(string: $0)] != nil }) else {
            fail("Mac 服务版本不兼容"); return
        }
        do { key = try KeychainStore.read("mac-\(peripheral.identifier)") }
        catch { fail("无法读取配对密钥，请解锁手表"); return }
        if key != nil { readChallenge() }
        else { readPairing() }
    }
    private func readPairing() {
        guard let peripheral, let characteristic = characteristics[CBUUID(string: Wire.pairing)] else { return }
        peripheral.readValue(for: characteristic)
    }
    private func readChallenge() {
        guard let peripheral, let characteristic = characteristics[CBUUID(string: Wire.challenge)] else { return }
        peripheral.readValue(for: characteristic)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == CBUUID(string: Wire.pairing) {
            guard error == nil, let value = characteristic.value, value.count == 32 else {
                pairAttempts += 1
                guard pairAttempts < 40 else { fail("配对未获允许，请在 Mac 重试"); return }
                status = "请在 Mac 允许这块手表\n如弹出系统配对，也请确认"
                retryTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard !Task.isCancelled else { return }; self?.readPairing()
                }
                return
            }
            do { try KeychainStore.save(value, account: "mac-\(peripheral.identifier)") }
            catch { fail("无法保存配对，请解锁手表"); return }
            key = value; savedID = peripheral.identifier; readChallenge()
        } else if characteristic.uuid == CBUUID(string: Wire.challenge) {
            guard error == nil, let nonce = characteristic.value, nonce.count == 16 else {
                fail("Mac 未允许连接；请停止录音或重新配对"); return
            }
            challenge = nonce
            if let characteristic = characteristics[CBUUID(string: Wire.status)] { peripheral.setNotifyValue(true, for: characteristic) }
        } else if characteristic.uuid == CBUUID(string: Wire.status) {
            guard error == nil, let data = characteristic.value, let key, let challenge else { fail("状态读取失败"); return }
            do {
                let (newPhase, seq) = try Wire.decodeStatus(data, key: key, challenge: challenge)
                guard let current = inflight, seq == current.sequence else { return }
                timeout?.cancel(); inflight = nil; phase = newPhase
                status = newPhase.caption
                if current.action == .beginDictation {
                    if newPhase == .listening { audioAccepted = true; drainAudio() }
                    else { clearAudio() }
                } else if [.failed, .unavailable, .permissionRequired].contains(newPhase) { clearAudio() }
                if [.permissionRequired, .targetInactive, .unavailable, .failed].contains(newPhase), current.action != .heartbeat {
                    WKInterfaceDevice.current().play(.failure)
                } else if current.action == .beginDictation && newPhase == .listening { WKInterfaceDevice.current().play(.start) }
                else if current.action == .finishDictation { WKInterfaceDevice.current().play(.stop) }
                drain()
            } catch { fail("Mac 状态认证失败，请重新配对") }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.isNotifying else { fail("无法接收 Mac 状态"); return }
        timeout?.cancel(); connected = true; status = "已连接 \(macName)"; lastError = nil
        send(.heartbeat)
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if error != nil { fail("Mac 拒绝了指令，请重新配对或查看 Mac") }
        // ATT success is not an execution acknowledgement; wait for the signed notification.
    }
}

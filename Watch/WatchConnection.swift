import Foundation
import CoreBluetooth
import WatchKit
import MicodexCore

@MainActor
// Both managers and peripherals deliver callbacks on our central manager's main queue.
final class WatchConnection: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    struct NearbyMac: Identifiable { let id: UUID; let name: String; let peripheral: CBPeripheral }
    @Published var nearby: [NearbyMac] = []
    @Published var connected = false
    @Published var status = L10n.t("Looking for your Mac…")
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
    private var visible = true
    private var lastError: String?
    private var recovery = ConnectionRecovery()
    private var transportReady = false
    private let microphone = WatchMicrophone()
    private var microphoneTask: Task<Void, Never>?
    private var audioStream: UInt32 = 0
    private var audioSequence: UInt32 = 0
    private var audioOffset: UInt32 = 0
    private var audioSamples: [Int16] = []
    private var audioPackets: [Data] = []
    private var audioAccepted = false
    @Published private(set) var recordingRequested = false
    @Published private(set) var recordingLocked = false
    @Published private(set) var stopping = false
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
        reset(); demo = true; connected = true; macName = L10n.t("Demo Mac"); status = L10n.t("Demo mode · Mac control is off")
    }
    func choose(_ mac: NearbyMac) {
        guard !demo else { return }
        guard ![CBPeripheralState.connecting, .connected, .disconnecting].contains(mac.peripheral.state) else { return }
        retryTask?.cancel(); lastError = nil
        if let previous = peripheral, previous.identifier != mac.id {
            previous.delegate = nil; central.cancelPeripheralConnection(previous)
        }
        recovery.begin(mac.id)
        ConnectionTrace.record("watch", "connect \(mac.id.uuidString.prefix(8)) state=\(mac.peripheral.state.rawValue)")
        central.stopScan(); peripheral = mac.peripheral; peripheral?.delegate = self
        macName = mac.name; status = L10n.t("Connecting to %@…", mac.name)
        central.connect(mac.peripheral)
        armConnectTimeout(mac.peripheral)
    }
    func forget() {
        retryTask?.cancel(); timeout?.cancel()
        if let id = savedID { try? KeychainStore.delete("mac-\(id)") }
        savedID = nil; demo = false; lastError = nil; recovery.forget()
        // Discard the old manager too: its delayed cancellation callback must not
        // tear down a new pairing attempt with the same peripheral identifier.
        central?.delegate = nil; central?.stopScan()
        if let peripheral { peripheral.delegate = nil; central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil; nearby = []; reset()
        ConnectionTrace.record("watch", "forget; create fresh central manager")
        central = CBCentralManager(delegate: self, queue: .main)
    }
    func setActive(_ value: Bool) {
        visible = value
        ConnectionTrace.record("watch", "scene active=\(value)")
        if value {
            active = true
            if !connected && !demo { discover() }
            return
        }
        central?.stopScan(); retryTask?.cancel()
        queue.removeAll { $0.0 == .scroll || $0.0 == .heartbeat }
        switch RecordingVisibility.onHide(locked: recordingLocked, recording: recordingRequested, stopping: stopping) {
        case .stayActive:
            active = true
        case .finishAndSuspend:
            active = true
            send(.finishDictation)
        case .disconnect:
            active = false
        }
    }
    func setRecordingLocked(_ value: Bool) { recordingLocked = value && recordingRequested && !stopping }
    /// Switching transports must stop capture even when wrist-down recording is locked.
    func disconnect() {
        visible = false
        if recordingRequested || audioAccepted || stopping { preserveReceivedAudio(L10n.t("Watch recording stopped")) }
        active = false; central?.stopScan(); retryTask?.cancel()
    }
    func send(_ action: RemoteAction, value: Int16 = 0) {
        guard connected, !demo else { sendCommand(action, value: value); return }
        if action == .beginDictation {
            guard visible, !recordingRequested, !stopping else { return }
            guard characteristics[CBUUID(string: AudioWire.characteristic)] != nil,
                  let peripheral, peripheral.maximumWriteValueLength(for: .withoutResponse) >= 64 else {
                status = L10n.t("Update Micodex on your Mac to use Watch audio."); phase = .failed; return
            }
            clearAudio(); recordingRequested = true; status = L10n.t("Starting the Watch microphone…")
            microphoneTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.microphone.start(onSilence: { [weak self] _ in self?.send(.finishDictation) },
                                                    onFailure: { [weak self] in self?.preserveReceivedAudio($0) }) { [weak self] in self?.capture($0) }
                    guard !Task.isCancelled, self.recordingRequested else { self.microphone.stop(); return }
                    self.sendCommand(.beginDictation)
                } catch {
                    guard !Task.isCancelled else { return }
                    self.clearAudio(); self.status = error.localizedDescription; self.phase = .failed
                }
            }
        } else if action == .finishDictation || (action == .enter && recordingRequested) {
            guard !stopping else { return }
            guard recordingRequested else { sendCommand(action, value: value); return }
            guard !finishRequested else { return }
            microphone.stop(); finishRequested = true; stopping = true; recordingLocked = false
            phase = .transcribing
            if audioStream == 0 {
                queue.removeAll { $0.0 == .beginDictation }
                clearAudio(); phase = .ready; active = visible; return
            }
            flushAudio(ending: true); drainAudio()
            audioTimeout?.cancel()
            audioTimeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled, let self, self.finishRequested else { return }
                self.preserveReceivedAudio(L10n.t("Audio transfer timed out. Your Mac was asked to keep the audio it received."))
            }
        } else if action == .cancelDictation {
            clearAudio(); sendCommand(action)
        } else { sendCommand(action, value: value) }
    }
    private func capture(_ samples: [Int16]) {
        guard recordingRequested, !finishRequested else { return }
        guard Int(audioOffset) + audioSamples.count + samples.count <= AudioWire.sampleRate * 120,
              audioSamples.count + samples.count <= 32000, audioPackets.count < 100 else {
            preserveReceivedAudio(L10n.t("Recording reached its limit or Bluetooth fell behind. Your Mac was asked to keep the audio it received.")); return
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
        } catch { preserveReceivedAudio(L10n.t("Audio encoding failed. Your Mac was asked to keep the audio it received.")) }
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
        recordingLocked = false; stopping = false
    }
    private func preserveReceivedAudio(_ message: String) {
        let started = audioStream != 0
        queue.removeAll { $0.0 == .beginDictation }
        clearAudio()
        if started {
            stopping = true; phase = .transcribing
            sendCommand(.finishReceivedAudio)
        } else { active = visible; phase = .ready }
        status = message
    }
    private func sendCommand(_ action: RemoteAction, value: Int16 = 0) {
        guard connected || (transportReady && action == .heartbeat) else { return }
        if demo {
            switch action {
            case .beginDictation:
                guard visible else { return }
                recordingRequested = true; phase = .listening
            case .finishDictation, .finishReceivedAudio:
                if phase == .listening {
                    clearAudio()
                    phase = .transcribing
                    Task { try? await Task.sleep(nanoseconds: 600_000_000); phase = .ready }
                }
            case .cancelDictation: clearAudio(); phase = .ready
            case .enter: status = L10n.t("Demo: Enter pressed"); WKInterfaceDevice.current().play(.success)
            case .scroll: status = value >= 0 ? L10n.t("Demo: scrolling down") : L10n.t("Demo: scrolling up")
            case .heartbeat: break
            }
            return
        }
        if action == .scroll, let last = queue.last, last.0 == .scroll {
            queue[queue.count - 1].1 = ScrollMotion.coalescing(last.1, with: value)
        } else {
            if action == .heartbeat && (!queue.isEmpty || inflight != nil) { return }
            // Never let crown traffic crowd out stop/Enter commands.
            if queue.count >= 12 { queue.removeAll { $0.0 == .scroll || $0.0 == .heartbeat } }
            guard queue.count < 16 else { fail(L10n.t("Too many commands. Disconnected; please reconnect.")); return }
            queue.append((action, value))
        }
        drain()
    }
    private func drain() {
        guard transportReady, inflight == nil, !queue.isEmpty, let peripheral,
              let characteristic = characteristics[CBUUID(string: Wire.command)], let key, let challenge else { return }
        guard sequence < UInt32.max else { fail(L10n.t("The connection needs to be renewed. Please reconnect.")); return }
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
                self.fail(L10n.t("Your Mac did not confirm the action. Disconnected; the command will not be resent."))
            }
        } catch { fail(L10n.t("Could not authenticate the command. Please pair again.")) }
    }
    private func reset() {
        clearAudio()
        connected = false; transportReady = false; key = nil; challenge = nil; sequence = 0
        queue = []; inflight = nil; characteristics = [:]
        timeout?.cancel(); timeout = nil; phase = .ready; pairAttempts = 0
    }
    private func fail(_ message: String) {
        clearAudio()
        ConnectionTrace.record("watch", "failure: \(message)")
        lastError = message; status = message; connected = false; transportReady = false
        queue = []; inflight = nil; timeout?.cancel()
        WKInterfaceDevice.current().play(.failure)
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
    }
    private func discover() {
        guard !demo, active, central?.state == .poweredOn else { return }
        guard peripheral?.state != .connecting, peripheral?.state != .connected else { return }
        if let id = recovery.takeCachedID(savedID), let known = central.retrievePeripherals(withIdentifiers: [id]).first {
            choose(NearbyMac(id: id, name: known.name ?? L10n.t("Paired Mac"), peripheral: known))
        } else {
            status = lastError ?? L10n.t("Click “Allow Bluetooth Watch” on your Mac.")
            ConnectionTrace.record("watch", "scan for fresh Mac advertisement")
            central.scanForPeripherals(withServices: [CBUUID(string: Wire.service)], options: nil)
        }
    }
    private func armConnectTimeout(_ p: CBPeripheral) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled, let self, !self.connected, p.state == .connecting else { return }
            self.fail(L10n.t("Your Mac is unavailable. Waiting to reconnect…"))
        }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === self.central else { return }
        ConnectionTrace.record("watch", "central state=\(central.state.rawValue)")
        if central.state == .poweredOn { discover() }
        else {
            reset(); peripheral = nil; recovery.forget()
            status = central.state == .unauthorized ? L10n.t("Allow Bluetooth access in Watch Settings.") : L10n.t("Turn on Bluetooth on your Watch.")
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard central === self.central else { return }
        ConnectionTrace.record("watch", "discovered \(peripheral.identifier.uuidString.prefix(8)) RSSI=\(RSSI)")
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Micodex Mac"
        let mac = NearbyMac(id: peripheral.identifier, name: name, peripheral: peripheral)
        if let index = nearby.firstIndex(where: { $0.id == mac.id }) { nearby[index] = mac }
        else { nearby.append(mac) }
        if savedID == mac.id { choose(mac) }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard central === self.central, recovery.accepts(peripheral.identifier) else { return }
        ConnectionTrace.record("watch", "BLE connected; discover GATT service")
        timeout?.cancel(); reset(); self.peripheral = peripheral; peripheral.delegate = self
        status = L10n.t("Verifying pairing…")
        peripheral.discoverServices([CBUUID(string: Wire.service)])
        // Discovery and authorization must not hang indefinitely either.
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 90_000_000_000)
            guard !Task.isCancelled, let self, !self.connected else { return }
            self.fail(L10n.t("Pairing timed out. Approve it on your Mac, then try again."))
        }
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard central === self.central, recovery.failed(peripheral.identifier) else { return }
        let reason = bluetoothError(error)
        reset(); self.peripheral = nil; nearby.removeAll { $0.id == peripheral.identifier }
        lastError = lastError ?? L10n.t("Connection failed (%@). Looking for your Mac again.", reason); status = lastError!
        ConnectionTrace.record("watch", "connect failed: \(reason)")
        scheduleReconnect()
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard !demo, central === self.central, recovery.failed(peripheral.identifier) else { return }
        ConnectionTrace.record("watch", "disconnected: \(bluetoothError(error))")
        reset(); self.peripheral = nil; status = lastError ?? L10n.t("Connection lost. Looking for your Mac again…")
        scheduleReconnect()
    }
    private func bluetoothError(_ error: Error?) -> String {
        guard let error = error as NSError? else { return L10n.t("No error code was provided by the system") }
        return "\(error.domain) \(error.code)：\(error.localizedDescription)"
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
        guard peripheral === self.peripheral, recovery.accepts(peripheral.identifier) else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: Wire.service) }) else {
            fail(L10n.t("Mac service unavailable (%@)", bluetoothError(error))); return
        }
        ConnectionTrace.record("watch", "GATT service found; discovering characteristics")
        peripheral.discoverCharacteristics(nil, for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === self.peripheral, recovery.accepts(peripheral.identifier) else { return }
        guard error == nil else { fail(L10n.t("Could not read the Mac service (%@)", bluetoothError(error))); return }
        for characteristic in service.characteristics ?? [] { characteristics[characteristic.uuid] = characteristic }
        guard [Wire.pairing, Wire.challenge, Wire.command, Wire.status].allSatisfy({ characteristics[CBUUID(string: $0)] != nil }) else {
            fail(L10n.t("The Mac service version is incompatible.")); return
        }
        do { key = try KeychainStore.read("mac-\(peripheral.identifier)") }
        catch { fail(L10n.t("Could not read the pairing key. Please unlock your Watch.")); return }
        ConnectionTrace.record("watch", "GATT ready; stored key=\(key != nil)")
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
        guard peripheral === self.peripheral, recovery.accepts(peripheral.identifier) else { return }
        if characteristic.uuid == CBUUID(string: Wire.pairing) {
            if let error { ConnectionTrace.record("watch", "pair read: \(bluetoothError(error))") }
            guard error == nil, let value = characteristic.value, value.count == 32 else {
                pairAttempts += 1
                guard pairAttempts < 40 else { fail(L10n.t("Pairing was not approved. Please try again on your Mac.")); return }
                status = L10n.t("Approve this Watch on your Mac.\nAlso confirm any system pairing request.")
                retryTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard !Task.isCancelled else { return }; self?.readPairing()
                }
                return
            }
            do { try KeychainStore.save(value, account: "mac-\(peripheral.identifier)") }
            catch { fail(L10n.t("Could not save pairing. Please unlock your Watch.")); return }
            key = value; savedID = peripheral.identifier; readChallenge()
        } else if characteristic.uuid == CBUUID(string: Wire.challenge) {
            guard error == nil, let nonce = characteristic.value, nonce.count == 16 else {
                fail(L10n.t("Your Mac did not allow the connection. Stop recording or pair again.")); return
            }
            challenge = nonce
            if let characteristic = characteristics[CBUUID(string: Wire.status)] { peripheral.setNotifyValue(true, for: characteristic) }
        } else if characteristic.uuid == CBUUID(string: Wire.status) {
            guard error == nil, let data = characteristic.value, let key, let challenge else { fail(L10n.t("Could not read the connection status.")); return }
            do {
                let (newPhase, seq) = try Wire.decodeStatus(data, key: key, challenge: challenge)
                guard let current = inflight, seq == current.sequence else { return }
                timeout?.cancel(); inflight = nil
                phase = stopping && newPhase == .listening ? .transcribing : newPhase
                if !connected {
                    connected = true; lastError = nil; recovery.authenticated()
                    ConnectionTrace.record("watch", "authenticated Mac heartbeat received")
                }
                status = phase.caption
                if current.action == .beginDictation {
                    if newPhase == .listening { audioAccepted = true; drainAudio() }
                    else { clearAudio() }
                } else if [.finishDictation, .finishReceivedAudio, .cancelDictation].contains(current.action)
                            || [.failed, .unavailable, .permissionRequired].contains(newPhase)
                            || (audioAccepted && newPhase != .listening) {
                    clearAudio(); active = visible
                }
                if [.permissionRequired, .targetInactive, .unavailable, .failed].contains(newPhase), current.action != .heartbeat {
                    WKInterfaceDevice.current().play(.failure)
                } else if current.action == .beginDictation && newPhase == .listening { WKInterfaceDevice.current().play(.start) }
                else if current.action == .finishDictation { WKInterfaceDevice.current().play(.stop) }
                drain()
            } catch { fail(L10n.t("Could not authenticate the Mac status. Please pair again.")) }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, recovery.accepts(peripheral.identifier) else { return }
        guard error == nil, characteristic.isNotifying else { fail(L10n.t("Could not receive the Mac status (%@)", bluetoothError(error))); return }
        timeout?.cancel(); transportReady = true; status = L10n.t("Authenticating your Mac…")
        ConnectionTrace.record("watch", "subscribed; send authenticated heartbeat")
        sendCommand(.heartbeat)
    }
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard recovery.accepts(peripheral.identifier), invalidatedServices.contains(where: { $0.uuid == CBUUID(string: Wire.service) }) else { return }
        fail(L10n.t("The Mac service was updated. Reconnecting…"))
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, recovery.accepts(peripheral.identifier) else { return }
        if error != nil { fail(L10n.t("Your Mac rejected the command (%@)", bluetoothError(error))) }
        // ATT success is not an execution acknowledgement; wait for the signed notification.
    }
}

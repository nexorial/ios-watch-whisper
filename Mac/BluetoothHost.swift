import Foundation
import CoreBluetooth
import MicodexCore

@MainActor
// CoreBluetooth delivers every delegate callback on the explicitly selected main queue.
final class BluetoothHost: NSObject, ObservableObject, @preconcurrency CBPeripheralManagerDelegate {
    @Published var connection = L10n.t("Bluetooth has not started")
    @Published var pendingWatch: String?
    @Published var pairingOpen = false
    @Published var pairedCount = 0
    @Published var radioStatus = L10n.t("Starting Bluetooth")
    private var serviceReady = false
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

    init(controller: AgentController, demo: Bool = false, enabled: Bool = true) {
        self.controller = controller; self.demo = demo
        super.init()
        pairedCount = approvedIDs.count
        if demo { connection = L10n.t("Demo mode · No Bluetooth connection") }
        else if enabled { manager = CBPeripheralManager(delegate: self, queue: .main) }
        else { connection = L10n.t("Bluetooth backup is off"); radioStatus = L10n.t("Wi-Fi direct connection preferred") }
    }
    func enableBluetooth() {
        guard manager == nil, !demo else { return }
        manager = CBPeripheralManager(delegate: self, queue: .main)
    }
    func allowPairing() {
        guard manager?.state == .poweredOn, serviceReady else {
            refreshRadio(); connection = L10n.t("Bluetooth is not ready. Check its status."); return
        }
        if !manager.isAdvertising { advertise() }
        refreshRadio()
        ConnectionTrace.record("mac", "pairing window opened; advertising=\(manager.isAdvertising)")
        pairingUntil = Date().addingTimeInterval(60); pairingOpen = true
        connection = L10n.t("Select this Mac on your Watch within 60 seconds")
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard let self, self.pairingUntil <= Date() else { return }
            self.pairingOpen = false; self.pendingWatch = nil; self.pendingCentral = nil
            if self.sessions.isEmpty { self.connection = L10n.t("The pairing window closed. Allow your Watch again to retry.") }
            self.refreshRadio()
        }
    }
    func refreshRadio() {
        guard !demo else { radioStatus = L10n.t("Demo mode"); return }
        guard manager != nil else { radioStatus = L10n.t("Bluetooth backup is off"); return }
        switch manager?.state {
        case .poweredOn: radioStatus = manager.isAdvertising ? L10n.t("Mac Bluetooth is advertising") : L10n.t("Mac Bluetooth is on, but advertising has not started")
        case .unauthorized: radioStatus = L10n.t("Micodex needs Bluetooth permission")
        case .poweredOff: radioStatus = L10n.t("Mac Bluetooth is off")
        default: radioStatus = L10n.t("Preparing Bluetooth")
        }
    }
    func restartAdvertising() {
        guard !demo, manager?.state == .poweredOn, serviceReady else { refreshRadio(); return }
        manager.stopAdvertising(); advertise()
        ConnectionTrace.record("mac", "advertising restarted")
    }
    private func advertise() {
        manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: Wire.service)],
                                  CBAdvertisementDataLocalNameKey: "Micodex · \(Host.current().localizedName ?? "Mac")"])
    }
    func approve() {
        guard pairingOpen, Date() < pairingUntil, let id = pendingCentral else { return }
        do {
            try KeychainStore.save(KeychainStore.random(count: 32), account: "watch-\(id)")
            var ids = approvedIDs; if !ids.contains(id.uuidString) { ids.append(id.uuidString) }; approvedIDs = ids
            ConnectionTrace.record("mac", "watch approved \(id.uuidString.prefix(8))")
            pendingWatch = nil; pendingCentral = nil; pairingOpen = false
            connection = L10n.t("Watch allowed. Establishing an encrypted connection…")
        } catch { connection = L10n.t("Could not save the pairing key: %@", error.localizedDescription) }
    }
    func revokeAll() {
        Task {
            _ = await controller.perform(.cancelDictation)
            audio.stop()
            do {
                for id in approvedIDs { try KeychainStore.delete("watch-\(id)") }
                approvedIDs = []; sessions = [:]; owner = nil; work = []; pendingNotifications = []
                connection = L10n.t("Pairing removed. Tap Forget Mac on your Watch too.")
            } catch { connection = L10n.t("Could not remove pairing: %@", error.localizedDescription) }
        }
    }
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        serviceReady = false; refreshRadio()
        ConnectionTrace.record("mac", "peripheral manager state=\(peripheral.state.rawValue)")
        guard peripheral.state == .poweredOn else {
            connection = peripheral.state == .unauthorized ? L10n.t("Allow Bluetooth in System Settings") : L10n.t("Turn on Bluetooth on your Mac")
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
        guard error == nil else {
            connection = L10n.t("Bluetooth service failed: %@", error!.localizedDescription)
            ConnectionTrace.record("mac", connection); return
        }
        serviceReady = true; ConnectionTrace.record("mac", "GATT service registered")
        advertise()
    }
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        refreshRadio()
        connection = error == nil ? L10n.t("Waiting for a paired Watch · Bluetooth direct") : L10n.t("Bluetooth advertising failed: %@", error!.localizedDescription)
        ConnectionTrace.record("mac", "advertising=\(peripheral.isAdvertising) error=\(String(describing: error))")
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        let id = request.central.identifier
        let uuid = request.characteristic.uuid
        ConnectionTrace.record("mac", "read \(uuid) from \(id.uuidString.prefix(8)) offset=\(request.offset) approved=\(approvedIDs.contains(id.uuidString))")
        do {
            let payload: Data
            if uuid == CBUUID(string: Wire.pairing) {
                guard approvedIDs.contains(id.uuidString), let key = try KeychainStore.read("watch-\(id)") else {
                    if pairingOpen && Date() < pairingUntil && (pendingCentral == nil || pendingCentral == id) {
                        pendingCentral = id; pendingWatch = String(id.uuidString.prefix(8))
                        connection = L10n.t("A Watch requested pairing. Check the request on your Watch, then allow it.")
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
        } catch { peripheral.respond(to: request, withResult: .unlikelyError); connection = L10n.t("Pairing data is unavailable") }
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
            sessions[id]?.audioGate = nil
            Task {
                _ = await controller.perform(.finishReceivedAudio)
                controller.phase = .failed; controller.detailMessage = (error as? LocalizedMessageError)?.localizedMessage ?? L10n.message("Watch audio transfer failed: %@", error.localizedDescription)
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
                if controller.isRecording, owner != central.identifier {
                    phase = .unavailable
                } else {
                    if command.action == .beginDictation {
                        do {
                            try audio.start()
                            controller.drainBeforePreserving = { [weak audio] in
                                try? await audio?.drain(); audio?.stop()
                            }
                            phase = await controller.perform(command.action, value: command.value)
                            if phase == .listening {
                                owner = central.identifier
                                sessions[central.identifier]?.audioGate = AudioGate(stream: command.sequence)
                            } else { audio.stop() }
                        } catch {
                            audio.stop(); controller.phase = .failed; controller.detailMessage = (error as? LocalizedMessageError)?.localizedMessage ?? L10n.message("Audio failed: %@", error.localizedDescription)
                            phase = .failed
                        }
                    } else if [.finishDictation, .finishReceivedAudio].contains(command.action), owner == central.identifier {
                        do {
                            guard command.action == .finishReceivedAudio || sessions[central.identifier]?.audioGate?.ended == true else {
                                throw WatchAudioOutput.AudioFailure(L10n.message("Watch audio did not finish completely. Received audio has been kept."))
                            }
                            try await audio.drain()
                            phase = await controller.perform(.finishDictation)
                        } catch {
                            _ = await controller.perform(.finishReceivedAudio)
                            controller.phase = .failed; controller.detailMessage = (error as? LocalizedMessageError)?.localizedMessage ?? L10n.message("Audio failed: %@", error.localizedDescription); phase = .failed
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
                connection = L10n.t("Watch connected · %@", phase.caption)
            }
            draining = false
        }
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        ConnectionTrace.record("mac", "watch subscribed \(central.identifier.uuidString.prefix(8))")
    }
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        while let item = pendingNotifications.first {
            guard peripheral.updateValue(item.0, for: statusCharacteristic, onSubscribedCentrals: [item.1]) else { return }
            pendingNotifications.removeFirst()
        }
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        ConnectionTrace.record("mac", "watch unsubscribed \(central.identifier.uuidString.prefix(8))")
        sessions[central.identifier] = nil
        work.removeAll { $0.0.identifier == central.identifier }
        pendingNotifications.removeAll { $0.1.identifier == central.identifier }
        if owner == central.identifier {
            Task {
                guard owner == central.identifier else { return }
                _ = await controller.perform(.finishReceivedAudio)
                if owner == central.identifier { owner = nil }
            }
        }
        connection = L10n.t("Watch disconnected · Waiting to reconnect")
    }
}

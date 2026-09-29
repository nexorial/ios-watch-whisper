import AVFoundation
import CoreAudio
import MicodexCore

@MainActor
protocol WatchAudioPlayback: AnyObject {
    var receivedSamples: Int { get }
    var captureSummary: String { get }
    func start() throws
    func enqueue(_ samples: [Int16]) throws
    func drain() async throws
    func stop()
}

/// Sends only authenticated Watch samples to the loopback device. Never uses
/// the Mac microphone, the default speaker, or a third party transcription API.
@MainActor
final class WatchAudioOutput: ObservableObject, WatchAudioPlayback {
    @Published var status = L10n.t("Checking virtual microphone…")
    @Published var receivedSamples = 0
    @Published var captureSummary = L10n.t("No Watch recording yet")
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var device: AudioDeviceID = 0
    private var queuedSamples = 0
    private var generation = UUID()
    private var level = AudioLevel()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    var installed: Bool { loopbackDevice() != nil }
    var selectedForDictation: Bool {
        guard let id = loopbackDevice() else { return false }
        return defaultInput() == id
    }

    init() { refresh() }
    func refresh() {
        guard let id = loopbackDevice() else { status = L10n.t("Install the BlackHole 2ch virtual microphone"); return }
        status = defaultInput() == id ? L10n.t("Watch audio → BlackHole 2ch") : L10n.t("Set dictation input to BlackHole 2ch")
    }
    /// Only invoked by the explicitly labelled setup button, never by connecting
    /// a Watch or starting a recording. Global input changes remain a user action.
    func useForDictation() {
        guard engine == nil else { status = L10n.t("Finish dictation before changing the input device."); return }
        guard var id = loopbackDevice() else { refresh(); return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let result = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                                UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        guard result == noErr else { status = L10n.t("The input could not be changed (%@). Select it in Sound settings.", String(result)); return }
        refresh()
    }
    func start() throws {
        stop()
        guard let id = loopbackDevice() else { throw AudioFailure(L10n.message("BlackHole 2ch is not installed. The Mac microphone will not be used.")) }
        guard defaultInput() == id else {
            throw AudioFailure(L10n.message("Set the system sound input to BlackHole 2ch, and set Codex to use the default input or BlackHole 2ch."))
        }
        let engine = AVAudioEngine(), player = AVAudioPlayerNode()
        guard let unit = engine.outputNode.audioUnit else { throw AudioFailure(L10n.message("The virtual microphone output is unavailable.")) }
        var target = id
        let result = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                         kAudioUnitScope_Global, 0, &target, UInt32(MemoryLayout.size(ofValue: target)))
        guard result == noErr else { throw AudioFailure(L10n.message("Could not connect to BlackHole audio output (%@).", String(result))) }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()
        self.engine = engine; self.player = player; device = id; receivedSamples = 0; level = AudioLevel()
        status = L10n.t("Waiting for Watch microphone audio")
        captureSummary = L10n.t("Received 0.0 seconds this session")
    }
    func enqueue(_ samples: [Int16]) throws {
        guard !samples.isEmpty else { return }
        guard let engine, let player, engine.isRunning, defaultInput() == device,
              loopbackDevice() == device, let unit = engine.outputNode.audioUnit else {
            throw AudioFailure(L10n.message("The virtual microphone connection changed. Audio stopped."))
        }
        var actual: AudioDeviceID = 0, size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global,
                                   0, &actual, &size) == noErr, actual == device else {
            throw AudioFailure(L10n.message("The audio output changed from BlackHole. Audio stopped."))
        }
        // Watch buffers while Codex opens dictation. Its bounded startup burst
        // can exceed the former 1.5-second queue before playback catches up.
        guard queuedSamples + samples.count <= 48_000,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { throw AudioFailure(L10n.message("Audio transfer is backed up. Start speaking again.")) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (i, sample) in samples.enumerated() { channel[i] = Float(sample) / 32768 }
        let token = generation, count = samples.count
        queuedSamples += count; receivedSamples += count
        level.append(samples)
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.queuedSamples = max(0, self.queuedSamples - count)
            }
        }
        // Start with a short jitter buffer; keep receiving independent BLE blocks.
        if !player.isPlaying && queuedSamples >= 2400 { player.play() }
        status = L10n.t("Watch microphone · %@ seconds received", String(format: "%.1f", Double(receivedSamples) / 16000))
        captureSummary = L10n.t("Received this session: %@", level.diagnostic)
    }
    func drain() async throws {
        if queuedSamples > 0 { player?.play() }
        for _ in 0..<80 {
            if queuedSamples == 0 { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw AudioFailure(L10n.message("Audio playback has not finished. Check the virtual microphone."))
    }
    func stop() {
        generation = UUID(); player?.stop(); engine?.stop()
        player = nil; engine = nil; queuedSamples = 0; device = 0
    }
    private func defaultInput() -> AudioDeviceID {
        var value: AudioDeviceID = 0, size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &value)
        return value
    }
    private func loopbackDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return nil }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let result = devices.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, $0.baseAddress!)
        }
        guard result == noErr else { return nil }
        return devices.first { id in
            var name: CFString = "" as CFString, size = UInt32(MemoryLayout<CFString>.size)
            var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                     mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr && name as String == "BlackHole 2ch"
        }
    }
    struct AudioFailure: LocalizedMessageError {
        let message: LocalizedMessage
        init(_ message: LocalizedMessage) { self.message = message }
        init(_ message: String) { self.message = L10n.message(message) }
        var localizedMessage: LocalizedMessage { message }
    }
}

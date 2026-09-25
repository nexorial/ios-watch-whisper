import AVFoundation
import CoreAudio
import WhisperCore

/// Sends only authenticated Watch samples to the loopback device. Never uses
/// the Mac microphone, the default speaker, or a third party transcription API.
@MainActor
final class WatchAudioOutput: ObservableObject {
    @Published var status = "检查虚拟麦克风…"
    @Published var receivedSamples = 0
    @Published var captureSummary = "尚无 Watch 录音"
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var device: AudioDeviceID = 0
    private var queuedSamples = 0
    private var generation = UUID()
    private var level = AudioLevel()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    var installed: Bool { loopbackDevice() != nil }

    init() { refresh() }
    func refresh() {
        guard let id = loopbackDevice() else { status = "需要安装 BlackHole 2ch 虚拟麦克风"; return }
        status = defaultInput() == id ? "Watch 音频 → BlackHole 2ch" : "请将听写音频输入设为 BlackHole 2ch"
    }
    /// Only invoked by the explicitly labelled setup button, never by connecting
    /// a Watch or starting a recording. Global input changes remain a user action.
    func useForDictation() {
        guard engine == nil else { status = "请先结束当前听写，再更改输入设备。"; return }
        guard var id = loopbackDevice() else { refresh(); return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let result = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                                UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        guard result == noErr else { status = "系统未接受输入切换（\(result)），请在声音设置中选择。"; return }
        refresh()
    }
    func start() throws {
        stop()
        guard let id = loopbackDevice() else { throw AudioFailure("尚未安装 BlackHole 2ch；不会改用 Mac 麦克风。") }
        guard defaultInput() == id else {
            throw AudioFailure("请在系统声音设置将输入设为 BlackHole 2ch，并让 Codex 使用默认输入或 BlackHole 2ch。")
        }
        let engine = AVAudioEngine(), player = AVAudioPlayerNode()
        guard let unit = engine.outputNode.audioUnit else { throw AudioFailure("虚拟麦克风输出不可用。") }
        var target = id
        let result = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                         kAudioUnitScope_Global, 0, &target, UInt32(MemoryLayout.size(ofValue: target)))
        guard result == noErr else { throw AudioFailure("无法连接 BlackHole 音频输出（\(result)）。") }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()
        self.engine = engine; self.player = player; device = id; receivedSamples = 0; level = AudioLevel()
        status = "等待 Watch 麦克风音频"
        captureSummary = "本次已接收 0.0 秒"
    }
    func enqueue(_ samples: [Int16]) throws {
        guard !samples.isEmpty else { return }
        guard let engine, let player, engine.isRunning, defaultInput() == device,
              loopbackDevice() == device, let unit = engine.outputNode.audioUnit else {
            throw AudioFailure("虚拟麦克风连接已变化，已停止音频。")
        }
        var actual: AudioDeviceID = 0, size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global,
                                   0, &actual, &size) == noErr, actual == device else {
            throw AudioFailure("音频输出已离开 BlackHole，已停止。")
        }
        // Watch buffers while Codex opens dictation. Its bounded startup burst
        // can exceed the former 1.5-second queue before playback catches up.
        guard queuedSamples + samples.count <= 48_000,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { throw AudioFailure("音频传输积压，请重新开始说话。") }
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
        status = String(format: "Watch 麦克风 · 已接收 %.1f 秒", Double(receivedSamples) / 16000)
        captureSummary = "本次已接收 " + level.diagnostic
    }
    func drain() async throws {
        if queuedSamples > 0 { player?.play() }
        for _ in 0..<80 {
            if queuedSamples == 0 { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw AudioFailure("音频尚未播放完毕，请检查虚拟麦克风。")
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
    struct AudioFailure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

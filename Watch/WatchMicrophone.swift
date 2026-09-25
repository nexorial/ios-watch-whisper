import AVFoundation

@MainActor
final class WatchMicrophone {
    private var engine: AVAudioEngine?
    private var captureID: UUID?
    func start(onSamples: @escaping ([Int16]) -> Void) async throws {
        let granted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        try Task.checkCancellation()
        guard granted else { throw MicFailure("请在手表设置允许 Watch Whisper 使用麦克风。") }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)
        // watchOS chooses the recording input; unlike iOS, setPreferredInput is
        // unavailable. Refuse an external route instead of silently using it.
        guard session.currentRoute.inputs.contains(where: { $0.portType == .builtInMic }) else {
            try? session.setActive(false)
            throw MicFailure("未能启用 Apple Watch 内置麦克风。")
        }
        let engine = AVAudioEngine(), input = engine.inputNode
        let source = input.outputFormat(forBus: 0)
        guard source.sampleRate > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: target) else { throw MicFailure("手表音频格式不可用。") }
        let id = UUID(); captureID = id
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(source.sampleRate / 10), format: source) { [weak self] buffer, _ in
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16_000 / source.sampleRate) + 32)
            guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var consumed = false, error: NSError?
            let result = converter.convert(to: converted, error: &error) { _, status in
                if consumed { status.pointee = .noDataNow; return nil }
                consumed = true; status.pointee = .haveData; return buffer
            }
            guard error == nil, result != .error, let channel = converted.int16ChannelData?[0], converted.frameLength > 0 else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
            Task { @MainActor in
                guard self?.captureID == id else { return }
                onSamples(samples)
            }
        }
        do { try engine.start(); self.engine = engine }
        catch { input.removeTap(onBus: 0); stop(); throw error }
    }
    func stop() {
        captureID = nil
        engine?.inputNode.removeTap(onBus: 0); engine?.stop(); engine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    struct MicFailure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

import AVFoundation
import WhisperCore

@MainActor
final class WatchMicrophone {
    private var engine: AVAudioEngine?
    private var captureID: UUID?
    private var observers: [NSObjectProtocol] = []
    private var silenceEndpoint = SilenceEndpoint()
    func start(onSilence: @escaping (SilenceEndpoint.Reason) -> Void = { _ in }, onFailure: @escaping (String) -> Void = { _ in }, onSamples: @escaping ([Int16]) -> Void) async throws {
        let granted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        try Task.checkCancellation()
        guard granted else { throw MicFailure("请在手表设置允许 Watch Whisper 使用麦克风。") }
        let session = AVAudioSession.sharedInstance()
        // Speech capture needs normal input processing, not measurement mode's
        // reduced dynamics processing. Never override an OS microphone mute.
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)
        if #available(watchOS 10.0, *), AVAudioApplication.shared.isInputMuted {
            try? session.setActive(false)
            throw MicFailure("手表系统已将麦克风静音，请先在手表解除静音。")
        }
        // watchOS chooses the recording input; unlike iOS, setPreferredInput is
        // unavailable. Refuse an external route instead of silently using it.
        guard session.currentRoute.inputs.contains(where: { $0.portType == .builtInMic }) else {
            try? session.setActive(false)
            throw MicFailure("未能启用 Apple Watch 内置麦克风。")
        }
        let engine = AVAudioEngine(), input = engine.inputNode
        let source = input.outputFormat(forBus: 0)
        let converter: MicrophoneSamples
        do { converter = try MicrophoneSamples(source: source) }
        catch { try? session.setActive(false); throw MicFailure("手表音频格式不可用。") }
        let id = UUID(); captureID = id; silenceEndpoint = SilenceEndpoint()
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in
                guard self?.captureID == id else { return }
                self?.stop(); onFailure("录音被系统中断，已请求保留收到的内容")
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard self?.captureID == id, !session.currentRoute.inputs.contains(where: { $0.portType == .builtInMic }) else { return }
                self?.stop(); onFailure("Watch 内置麦克风已断开，已请求保留收到的内容")
            }
        })
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(source.sampleRate / 10), format: source) { [weak self] buffer, _ in
            do {
                let samples = try converter.convert(buffer)
                guard !samples.isEmpty else { return }
                Task { @MainActor in
                    guard self?.captureID == id else { return }
                    onSamples(samples)
                    guard let self, self.captureID == id else { return }
                    if let reason = self.silenceEndpoint.consume(samples) {
                        self.stop(); onSilence(reason)
                    }
                }
            } catch {
                Task { @MainActor in
                    guard self?.captureID == id else { return }
                    self?.stop(); onFailure("手表音频格式发生变化，请重新开始录音。")
                }
            }
        }
        do { engine.prepare(); try engine.start(); self.engine = engine }
        catch { input.removeTap(onBus: 0); stop(); throw error }
    }
    func stop() {
        captureID = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers = []
        engine?.inputNode.removeTap(onBus: 0); engine?.stop(); engine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    struct MicFailure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

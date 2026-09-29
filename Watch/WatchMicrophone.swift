import AVFoundation
import MicodexCore

@MainActor
final class WatchMicrophone {
    private var engine: AVAudioEngine?
    private var captureID: UUID?
    private var observers: [NSObjectProtocol] = []
    private var capturedSamples = 0
    func start(onLimit: @escaping () -> Void = {}, onFailure: @escaping (String) -> Void = { _ in }, onSamples: @escaping ([Int16]) -> Void) async throws {
        let granted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        try Task.checkCancellation()
        guard granted else { throw MicFailure(L10n.t("Allow Micodex to use the microphone in Watch Settings.")) }
        let session = AVAudioSession.sharedInstance()
        // Speech capture needs normal input processing, not measurement mode's
        // reduced dynamics processing. Never override an OS microphone mute.
        try session.setCategory(.record, mode: .default)
        try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        // Ringtones/alerts can defer to capture. Siri and accepted calls still
        // own the microphone; this preference does not disable system Siri.
        try session.setPrefersNoInterruptionsFromSystemAlerts(true)
        try session.setActive(true)
        if #available(watchOS 10.0, *), AVAudioApplication.shared.isInputMuted {
            try? session.setActive(false)
            throw MicFailure(L10n.t("Your Watch microphone is muted. Unmute it on your Watch first."))
        }
        // watchOS chooses the recording input; unlike iOS, setPreferredInput is
        // unavailable. Refuse an external route instead of silently using it.
        guard session.currentRoute.inputs.contains(where: { $0.portType == .builtInMic }) else {
            try? session.setActive(false)
            throw MicFailure(L10n.t("Could not activate the built-in Apple Watch microphone."))
        }
        let engine = AVAudioEngine(), input = engine.inputNode
        let source = input.outputFormat(forBus: 0)
        let converter: MicrophoneSamples
        do { converter = try MicrophoneSamples(source: source) }
        catch { try? session.setActive(false); throw MicFailure(L10n.t("The Watch audio format is unavailable.")) }
        let id = UUID(); captureID = id; capturedSamples = 0
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in
                guard self?.captureID == id else { return }
                let reason = notification.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt
                ConnectionTrace.record("microphone", "system interruption reason=\(reason.map(String.init) ?? "unknown")")
                self?.stop(); onFailure(L10n.t("Recording interrupted by the system. Review the captured audio on your Mac, then tap to record again."))
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard self?.captureID == id, !session.currentRoute.inputs.contains(where: { $0.portType == .builtInMic }) else { return }
                self?.stop(); onFailure(L10n.t("The built-in Watch microphone disconnected. Your Mac was asked to keep the audio it received."))
            }
        })
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(source.sampleRate / 10), format: source) { [weak self] buffer, _ in
            do {
                let samples = try converter.convert(buffer)
                guard !samples.isEmpty else { return }
                Task { @MainActor in
                    guard let self, self.captureID == id else { return }
                    let count = min(samples.count, 1_920_000 - self.capturedSamples)
                    self.capturedSamples += count
                    onSamples(Array(samples.prefix(count)))
                    if self.captureID == id && self.capturedSamples >= 1_920_000 {
                        self.stop(); onLimit()
                    }
                }
            } catch {
                Task { @MainActor in
                    guard self?.captureID == id else { return }
                    self?.stop(); onFailure(L10n.t("The Watch audio format changed. Please start recording again."))
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

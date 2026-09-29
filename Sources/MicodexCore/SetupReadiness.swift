/// Locally observable setup checks, separate from the user's end-to-end tests.
/// Pairing alone never claims that Codex permissions or transcription work.
public struct SetupReadiness: Equatable {
    public var driverAvailable: Bool
    public var inputSelected: Bool
    public var accessibilityAllowed: Bool
    public var receiverReady: Bool
    public var watchPaired: Bool

    public init(driverAvailable: Bool = false, inputSelected: Bool = false,
                accessibilityAllowed: Bool = false, receiverReady: Bool = false,
                watchPaired: Bool = false) {
        self.driverAvailable = driverAvailable
        self.inputSelected = inputSelected
        self.accessibilityAllowed = accessibilityAllowed
        self.receiverReady = receiverReady
        self.watchPaired = watchPaired
    }

    public var audioReady: Bool { driverAvailable && inputSelected }

    public func canFinish(voiceEnabled: Bool, scrollingConfirmed: Bool,
                          transcriptionConfirmed: Bool) -> Bool {
        accessibilityAllowed && receiverReady && watchPaired && scrollingConfirmed
            && (!voiceEnabled || (audioReady && transcriptionConfirmed))
    }
}

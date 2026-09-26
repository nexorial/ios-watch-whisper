import Foundation

/// Touch-down starts; a short tap latches, a hold releases to finish, right-drag locks.
/// Keep local gesture intent separate from the acknowledged recording state on the Mac.
public struct TalkGesture {
    public enum State: Equatable { case idle, touching, locked }
    public private(set) var state: State = .idle
    private var beganAt: TimeInterval = 0
    private var stopOnRelease = false
    private var recordingAcknowledged = false
    public init() {}

    public mutating func touchDown(at time: TimeInterval) -> RemoteAction? {
        guard state != .touching else { return nil }
        if state == .locked {
            state = .idle; stopOnRelease = true
            return .finishDictation
        }
        stopOnRelease = false; recordingAcknowledged = false; beganAt = time; state = .touching
        return .beginDictation
    }
    public mutating func drag(right: Double) -> Bool {
        guard state == .touching, right >= 44 else { return false }
        state = .locked
        return true
    }
    public mutating func release(at time: TimeInterval) -> RemoteAction? {
        if stopOnRelease { stopOnRelease = false; return nil }
        guard state == .touching else { return nil }
        if time - beganAt < 0.28 { state = .locked; return nil }
        state = .idle
        return .finishDictation
    }
    public mutating func stop(cancel: Bool = false) -> RemoteAction? {
        guard state != .idle else { return nil }
        state = .idle; stopOnRelease = false
        return cancel ? .cancelDictation : .finishDictation
    }
    /// A delayed host reply must never erase a physical press or its release.
    public mutating func hostChanged(_ phase: HostPhase) {
        if phase == .listening, state != .idle { recordingAcknowledged = true }
        guard state != .touching else { return }
        if [.failed, .unavailable, .permissionRequired, .targetInactive].contains(phase)
            || (phase == .ready && recordingAcknowledged) { reset() }
    }
    public mutating func reset() { state = .idle; stopOnRelease = false; recordingAcknowledged = false }
    public mutating func restoreLockedRecording() { state = .locked; recordingAcknowledged = true; stopOnRelease = false }
}

public struct CrownAccumulator {
    private var residual: Double = 0
    public init() {}
    public mutating func add(_ delta: Double) -> Int16 {
        guard delta.isFinite, abs(delta) < 100 else { return 0 }
        residual = max(-600, min(600, residual + delta * 22))
        let pixels = max(-600, min(600, Int(residual)))
        residual -= Double(pixels)
        return Int16(pixels)
    }
}

public struct RecordingLease {
    public private(set) var beganAt: TimeInterval?
    private var lastHeartbeat: TimeInterval = 0
    public init() {}
    public mutating func begin(at now: TimeInterval) { beganAt = now; lastHeartbeat = now }
    public mutating func renew(at now: TimeInterval) { lastHeartbeat = now }
    public mutating func finish() { beganAt = nil }
    public func expired(at now: TimeInterval) -> Bool {
        guard let start = beganAt else { return false }
        return now - lastHeartbeat > 5 || now - start > 120
    }
}

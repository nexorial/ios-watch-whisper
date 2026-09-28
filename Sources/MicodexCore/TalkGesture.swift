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
    private var lastTime: TimeInterval?
    private var lastDirection = 0.0
    private var speed = 0.0
    public init() {}
    public mutating func add(_ delta: Double, at now: TimeInterval) -> Int16 {
        guard delta.isFinite, abs(delta) < 100, now.isFinite else { reset(); return 0 }
        guard delta != 0 else { return 0 }
        let direction = delta > 0 ? 1.0 : -1.0
        let elapsed = lastTime.map { now - $0 }
        if let elapsed, elapsed > 0, elapsed < 0.25, direction == lastDirection {
            let measured = abs(delta) / max(elapsed, 1.0 / 120)
            // Ease acceleration over ~40 ms; slowing down takes effect immediately.
            speed = min(measured, speed + (measured - speed) * (1 - exp(-elapsed / 0.04)))
        } else {
            // A new gesture or reversal starts precise, without stale fractional motion.
            speed = 0; residual = 0
        }
        lastTime = now; lastDirection = direction
        // Crown units/second: fine control below 1; smoothly reach 6x at 10.
        let progress = max(0, min(1, (speed - 1) / 9))
        let gain = 1 + 5 * progress * progress * (3 - 2 * progress)
        residual = max(-600, min(600, residual + delta * 12 * gain))
        let pixels = Int(residual)
        residual -= Double(pixels)
        return Int16(pixels)
    }
    public mutating func reset() {
        residual = 0; lastTime = nil; lastDirection = 0; speed = 0
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

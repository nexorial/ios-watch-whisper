import Foundation

/// Convert continuous Crown units and the system-provided units/second to pixels.
public struct CrownAccumulator {
    private var residual = 0.0
    private var lastDirection = 0
    public init() {}
    public mutating func add(_ delta: Double, velocity: Double) -> Int16 {
        guard delta.isFinite, abs(delta) < 100, velocity.isFinite else { reset(); return 0 }
        guard delta != 0 else { return 0 }
        let direction = delta > 0 ? 1 : -1
        if direction != lastDirection { residual = 0 }
        lastDirection = direction
        // Continuous input preserves subpixel precision. A normal turn should move
        // lines of desktop text, and a fast turn should traverse whole screens.
        let progress = max(0, min(1, (abs(velocity) - 0.25) / 3.75))
        let gain = 1 + 11 * progress * progress * (3 - 2 * progress)
        residual = max(-600, min(600, residual + delta * 240 * gain))
        let pixels = Int(residual)
        residual -= Double(pixels)
        return Int16(pixels)
    }
    public mutating func reset() { residual = 0; lastDirection = 0 }
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

import Foundation

/// Short interpolation, not an unbounded inertia queue. Reversals take effect
/// immediately and stop/target changes can discard all pending movement.
public struct ScrollMotion {
    public private(set) var pending = 0
    public init() {}
    /// Share reversal and backlog limits with the Watch transport queues.
    public static func coalescing(_ pending: Int16, with pixels: Int16) -> Int16 {
        let previous = pending != 0 && pixels != 0 && (pending > 0) != (pixels > 0) ? 0 : Int(pending)
        return Int16(max(-600, min(600, previous + Int(pixels))))
    }
    public mutating func add(_ pixels: Int) {
        if pixels != 0 && pending != 0 && (pixels > 0) != (pending > 0) { pending = 0 }
        pending = max(-600, min(600, pending + pixels))
    }
    public mutating func next() -> Int16 {
        guard pending != 0 else { return 0 }
        let amount = max(1, Int(ceil(Double(abs(pending)) * 0.5)))
        let step = pending > 0 ? amount : -amount
        pending -= step
        return Int16(step)
    }
    public mutating func reset() { pending = 0 }
}

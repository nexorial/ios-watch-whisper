import Foundation

/// A cached CoreBluetooth identifier may outlive a Mac reboot. Try it once,
/// then require a fresh advertisement. Callbacks from replaced attempts cannot
/// clear a newer connection.
public struct ConnectionRecovery {
    public private(set) var activeID: UUID?
    private var mayRetrieveCached = true
    public init() {}
    public mutating func takeCachedID(_ savedID: UUID?) -> UUID? {
        guard mayRetrieveCached else { return nil }
        mayRetrieveCached = false
        return savedID
    }
    public mutating func begin(_ id: UUID) { activeID = id }
    public func accepts(_ id: UUID) -> Bool { activeID == id }
    @discardableResult public mutating func failed(_ id: UUID) -> Bool {
        guard accepts(id) else { return false }
        activeID = nil; mayRetrieveCached = false
        return true
    }
    public mutating func authenticated() { mayRetrieveCached = true }
    public mutating func forget() { activeID = nil; mayRetrieveCached = false }
}

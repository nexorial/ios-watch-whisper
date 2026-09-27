import Foundation
import Darwin

/// The OS releases this advisory lock on exit/crash; the file itself is not a stale lock.
/// Separate app copies and windows must never share a receiving port.
final class ReceiverLease {
    private var descriptor: Int32 = -1
    func acquire(port: UInt16) throws -> Bool {
        if descriptor >= 0 { return true }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Micodex", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("receiver-\(port).lock").path
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno; close(fd)
            if code == EWOULDBLOCK { return false }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        descriptor = fd
        return true
    }
    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN); close(descriptor); descriptor = -1
    }
    deinit { release() }
}

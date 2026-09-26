import Foundation

/// Debug-only bounded diagnostics. Never accepts audio, pairing keys or prompt text.
@MainActor public enum ConnectionTrace {
    private static var events: [String] = []
    public static func record(_ component: String, _ event: String) {
        #if DEBUG
        let line = "\(ISO8601DateFormatter().string(from: Date())) [\(component)] \(event)"
        print(line)
        events.append(line)
        if events.count > 100 { events.removeFirst(events.count - 100) }
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let folder = base.appendingPathComponent("Micodex", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? events.joined(separator: "\n").write(to: folder.appendingPathComponent("connection-trace.log"), atomically: true, encoding: .utf8)
        #endif
    }
}

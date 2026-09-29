import Foundation

public enum ThreadTitle {
    /// Keep user text intact; discard application-only window titles and bound
    /// metadata size so a malformed accessibility tree cannot fill a reply.
    public static func clean(_ value: String, application: String) -> String? {
        var title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [" — ", " – ", " - "] {
            if title == (application + separator).trimmingCharacters(in: .whitespaces) { return nil }
            if title.hasSuffix(separator + application) { title.removeLast(separator.count + application.count) }
            if title.hasPrefix(application + separator) { title.removeFirst(application.count + separator.count) }
        }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.caseInsensitiveCompare(application) != .orderedSame else { return nil }
        return String(title.prefix(240))
    }
}

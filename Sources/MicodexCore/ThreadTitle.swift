import Foundation
import CoreGraphics

public enum ThreadTitle {
    public enum Kind: Int { case heading, text, control }

    public struct Candidate {
        public let text: String
        public let frame: CGRect
        public let kind: Kind
        public init(_ text: String, frame: CGRect, kind: Kind) {
            self.text = text; self.frame = frame; self.kind = kind
        }
    }

    /// Prefer the content header to an Electron window title, which can be an
    /// application name or lag behind a switch between conversations.
    public static func select(_ candidates: [Candidate], window: CGRect, composer: CGRect,
                              windowTitle: String, application: String) -> String? {
        let header = candidates.filter {
            $0.frame.width > 0 && $0.frame.height > 0
                && $0.frame.minY >= window.minY && $0.frame.maxY <= window.minY + 112
                && $0.frame.midX >= max(window.minX, composer.minX - 64)
                && $0.frame.midX <= min(window.maxX, composer.maxX + 64)
                && window.intersects($0.frame)
        }
        for kind in [Kind.heading, .text, .control] {
            let titles = Set(header.filter { $0.kind == kind }.compactMap {
                clean($0.text, application: application)
            })
            // Do not substitute a sidebar selection or stale OS title when the
            // active content header itself is ambiguous.
            if !titles.isEmpty { return titles.count == 1 ? titles.first : nil }
        }
        return clean(windowTitle, application: application)
    }

    /// Keep user text intact; discard application-only window titles and bound
    /// metadata size so a malformed accessibility tree cannot fill a reply.
    public static func clean(_ value: String, application: String) -> String? {
        var title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // com.openai.codex can expose "ChatGPT" as its macOS window/app title.
        let names = application.caseInsensitiveCompare("Codex") == .orderedSame
            ? [application, "ChatGPT"] : [application]
        for name in names {
            for separator in [" — ", " – ", " - "] {
                if title.caseInsensitiveCompare((name + separator).trimmingCharacters(in: .whitespaces)) == .orderedSame { return nil }
                if title.lowercased().hasSuffix((separator + name).lowercased()) { title.removeLast(separator.count + name.count) }
                if title.lowercased().hasPrefix((name + separator).lowercased()) { title.removeFirst(name.count + separator.count) }
            }
        }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !names.contains(where: { title.caseInsensitiveCompare($0) == .orderedSame }) else { return nil }
        return String(title.prefix(240))
    }
}

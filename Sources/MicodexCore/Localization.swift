import Foundation

/// English source keys with native bundle language selection. No device-wide or
/// per-user override is persisted; each app follows its own preferred language.
public enum L10n {
    public static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        // Command-line smoke tools compile the module directly. They use the
        // readable English source value when no resource bundle is embedded.
        return .main
        #endif
    }

    public static func t(_ key: String, _ arguments: String...) -> String {
        render(key, arguments: arguments)
    }

    public static func message(_ key: String, _ arguments: String...) -> LocalizedMessage {
        LocalizedMessage(key: key, arguments: arguments)
    }

    public static func render(_ key: String, arguments: [String] = [], language: String? = nil) -> String {
        let selected: Bundle
        if let language {
            let match = Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: [language]).first ?? "en"
            selected = bundle.path(forResource: match, ofType: "lproj").flatMap(Bundle.init(path:)) ?? bundle
        } else {
            selected = bundle
        }
        let format = selected.localizedString(forKey: key, value: key, table: "Localizable")
        guard !arguments.isEmpty else { return format }
        // Wire keys are data, even from a paired Mac. Never pass arbitrary
        // printf directives or mismatched arguments to Foundation's formatter.
        guard stringArgumentCount(format) == arguments.count else { return format }
        return String(format: format, locale: language.map(Locale.init(identifier:)) ?? .current,
                      arguments: arguments.map { $0 as CVarArg })
    }
    private static func stringArgumentCount(_ format: String) -> Int? {
        let characters = Array(format)
        var index = 0, count = 0
        while index < characters.count {
            if characters[index] == "%" {
                index += 1
                guard index < characters.count else { return nil }
                if characters[index] == "@" { count += 1 }
                else if characters[index] != "%" { return nil }
            }
            index += 1
        }
        return count
    }

}

/// Carries the translation key and values, not a string rendered in the sender's
/// language. The receiver selects its own bundle language.
public struct LocalizedMessage: Codable, Equatable, Sendable {
    public let key: String
    public let arguments: [String]
    public init(key: String, arguments: [String] = []) {
        self.key = key; self.arguments = arguments
    }
    public var localizedString: String { L10n.render(key, arguments: arguments) }
    public func localizedString(language: String) -> String {
        L10n.render(key, arguments: arguments, language: language)
    }
}

public protocol LocalizedMessageError: LocalizedError {
    var localizedMessage: LocalizedMessage { get }
}
public extension LocalizedMessageError {
    var errorDescription: String? { localizedMessage.localizedString }
}

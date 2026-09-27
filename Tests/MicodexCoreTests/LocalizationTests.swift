import XCTest
@testable import MicodexCore

final class LocalizationTests: XCTestCase {
    func testUsesNativeEnglishAndChineseResources() {
        XCTAssertEqual(L10n.render("Ready", language: "en-US"), "Ready")
        XCTAssertEqual(L10n.render("Ready", language: "zh-Hans-CN"), "准备好了")
        XCTAssertEqual(L10n.render("Ready", language: "fr-FR"), "Ready")
    }
    func testWireMessageIsRenderedInReceivingDevicesLanguage() throws {
        let source = L10n.message("Connection incomplete: %@", "192.168.1.20")
        let reply = WiFiReply("error", message: source)
        let received = try JSONDecoder().decode(WiFiReply.self, from: JSONEncoder().encode(reply))
        XCTAssertEqual(received.renderedMessage(language: "en"), "Connection incomplete: 192.168.1.20")
        XCTAssertEqual(received.renderedMessage(language: "zh-Hans"), "连接未完成：192.168.1.20")
        XCTAssertEqual(received.messageKey, source.key)
        XCTAssertEqual(received.messageArguments, source.arguments)
        XCTAssertNotNil(received.message, "Legacy clients retain a readable fallback")
    }
    func testUnknownWireFormatsCannotExecutePrintfDirectives() {
        XCTAssertEqual(L10n.render("Unknown %n", arguments: ["value"]), "Unknown %n")
        XCTAssertEqual(L10n.render("Missing %@ %@", arguments: ["value"]), "Missing %@ %@")
    }
    func testLegacyRepliesAndUserDataArePreserved() throws {
        let reply = try JSONDecoder().decode(WiFiReply.self, from: Data(#"{"status":"error","message":"Old receiver message"}"#.utf8))
        XCTAssertEqual(reply.localizedMessage, "Old receiver message")
        let message = LocalizedMessage(key: "Connection incomplete: %@", arguments: ["James’s Mac · 100%"])
        XCTAssertEqual(message.localizedString(language: "en"), "Connection incomplete: James’s Mac · 100%")
    }
}

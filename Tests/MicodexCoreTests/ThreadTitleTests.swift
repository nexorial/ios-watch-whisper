import XCTest
@testable import MicodexCore

final class ThreadTitleTests: XCTestCase {
    func testApplicationOnlyAndBlankTitlesAreUnknown() {
        for title in ["", " \n", "Codex", "codex", "Codex — "] {
            XCTAssertNil(ThreadTitle.clean(title, application: "Codex"))
        }
    }
    func testUserThreadNamesKeepUnicodeAndOnlyRemoveAppDecoration() {
        XCTAssertEqual(ThreadTitle.clean("修复手表录音 — Codex", application: "Codex"), "修复手表录音")
        XCTAssertEqual(ThreadTitle.clean("Codex – Fix audio", application: "Codex"), "Fix audio")
        XCTAssertEqual(ThreadTitle.clean("Investigate Codex naming", application: "Codex"), "Investigate Codex naming")
        XCTAssertEqual(ThreadTitle.clean(String(repeating: "测", count: 300), application: "Codex")?.count, 240)
    }
    func testTitleMetadataIsOptionalForOlderReceivers() throws {
        let legacy = try JSONDecoder().decode(WiFiReply.self, from: Data(#"{"status":"ok","packet":"old"}"#.utf8))
        XCTAssertNil(legacy.focusedThreadTitle)
        let reply = WiFiReply("ok", packet: "authenticated", focusedThreadTitle: "修复录音 🎤")
        let decoded = try JSONDecoder().decode(WiFiReply.self, from: JSONEncoder().encode(reply))
        XCTAssertEqual(decoded.focusedThreadTitle, "修复录音 🎤")
        XCTAssertNil(WiFiReply("ok", name: "Mac").focusedThreadTitle)
    }
}

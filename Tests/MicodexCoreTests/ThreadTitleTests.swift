import XCTest
@testable import MicodexCore

final class ThreadTitleTests: XCTestCase {
    func testApplicationOnlyAndBlankTitlesAreUnknown() {
        for title in ["", " \n", "Codex", "codex", "Codex — ", "ChatGPT", "chatgpt", "ChatGPT – ", "ChatGPT — Codex"] {
            XCTAssertNil(ThreadTitle.clean(title, application: "Codex"))
        }
    }
    func testUserThreadNamesKeepUnicodeAndOnlyRemoveAppDecoration() {
        XCTAssertEqual(ThreadTitle.clean("修复手表录音 — Codex", application: "Codex"), "修复手表录音")
        XCTAssertEqual(ThreadTitle.clean("Codex – Fix audio", application: "Codex"), "Fix audio")
        XCTAssertEqual(ThreadTitle.clean("Investigate Codex naming", application: "Codex"), "Investigate Codex naming")
        XCTAssertEqual(ThreadTitle.clean("准备 watch whisper 开源与发布 — ChatGPT", application: "Codex"), "准备 watch whisper 开源与发布")
        XCTAssertEqual(ThreadTitle.clean("ChatGPT – Fix audio", application: "Codex"), "Fix audio")
        XCTAssertEqual(ThreadTitle.clean("Investigate ChatGPT naming", application: "Codex"), "Investigate ChatGPT naming")
        XCTAssertEqual(ThreadTitle.clean(String(repeating: "测", count: 300), application: "Codex")?.count, 240)
    }

    private let window = CGRect(x: 80, y: 40, width: 1200, height: 900)
    private let composer = CGRect(x: 400, y: 780, width: 650, height: 100)

    func testCurrentHeaderWinsOverGenericOrStaleWindowTitle() {
        let title = "准备 watch whisper 开源与发布"
        let heading = ThreadTitle.Candidate(title, frame: CGRect(x: 370, y: 75, width: 400, height: 30), kind: .heading)
        for oldTitle in ["ChatGPT", "Old conversation — Codex"] {
            XCTAssertEqual(ThreadTitle.select([heading], window: window, composer: composer,
                                            windowTitle: oldTitle, application: "Codex"), title)
        }
    }

    func testTextAndButtonTitlesSupportHeadersWithoutHeadingRoles() {
        for kind in [ThreadTitle.Kind.text, .control] {
            let title = ThreadTitle.Candidate("第二个对话", frame: CGRect(x: 370, y: 75, width: 300, height: 30), kind: kind)
            XCTAssertEqual(ThreadTitle.select([title], window: window, composer: composer,
                                            windowTitle: "ChatGPT", application: "Codex"), "第二个对话")
        }
    }

    func testSidebarAndTranscriptCannotBecomeTheCurrentThread() {
        let candidates = [
            ThreadTitle.Candidate("Another sidebar chat", frame: CGRect(x: 95, y: 75, width: 200, height: 30), kind: .text),
            ThreadTitle.Candidate("A heading inside a reply", frame: CGRect(x: 400, y: 220, width: 300, height: 30), kind: .heading),
            ThreadTitle.Candidate("Hidden tab", frame: CGRect(x: 1400, y: 75, width: 200, height: 30), kind: .heading)
        ]
        XCTAssertNil(ThreadTitle.select(candidates, window: window, composer: composer,
                                       windowTitle: "ChatGPT", application: "Codex"))
    }

    func testAmbiguousHeaderDoesNotFallBackToAStaleThread() {
        let frame = CGRect(x: 370, y: 75, width: 400, height: 30)
        let candidates = [ThreadTitle.Candidate("First", frame: frame, kind: .heading),
                          ThreadTitle.Candidate("Second", frame: frame, kind: .heading)]
        XCTAssertNil(ThreadTitle.select(candidates, window: window, composer: composer,
                                       windowTitle: "Old title — Codex", application: "Codex"))
    }

    func testDuplicateHeaderAccessibilityNodesAndMissingHeader() {
        let title = ThreadTitle.Candidate("Current", frame: CGRect(x: 370, y: 75, width: 300, height: 30), kind: .heading)
        XCTAssertEqual(ThreadTitle.select([title, title], window: window, composer: composer,
                                         windowTitle: "ChatGPT", application: "Codex"), "Current")
        XCTAssertEqual(ThreadTitle.select([], window: window, composer: composer,
                                         windowTitle: "Current — Codex", application: "Codex"), "Current")
        XCTAssertNil(ThreadTitle.select([], window: window, composer: composer,
                                       windowTitle: "ChatGPT", application: "Codex"))
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

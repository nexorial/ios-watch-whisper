import XCTest
@testable import WhisperCore

final class ComposerSelectionTests: XCTestCase {
    private let window = CGRect(x: 0, y: 0, width: 1200, height: 900)
    private func editor(_ id: Int, _ rect: CGRect, prose: Bool = true) -> ComposerSelection.Candidate {
        .init(index: id, frame: rect, proseMirror: prose, multiline: true)
    }
    func testShortEmptyComposerIsStillEditable() {
        XCTAssertEqual(ComposerSelection.select([editor(1, CGRect(x: 300, y: 800, width: 600, height: 14))],
                                                 window: window, dictateButtons: []), 1)
    }
    func testWritingBlockDoesNotDisplaceComposerNearDictationToolbar() {
        let candidates = [editor(1, CGRect(x: 300, y: 300, width: 600, height: 120)),
                          editor(2, CGRect(x: 300, y: 780, width: 600, height: 30))]
        XCTAssertEqual(ComposerSelection.select(candidates, window: window,
                                                dictateButtons: [CGRect(x: 860, y: 830, width: 28, height: 28)]), 2)
    }
    func testOffscreenEditorAndAdjacentTerminalAreExcluded() {
        let candidates = [editor(1, CGRect(x: 300, y: -400, width: 600, height: 100)),
                          editor(2, CGRect(x: 300, y: 780, width: 500, height: 30)),
                          editor(3, CGRect(x: 900, y: 300, width: 280, height: 400), prose: false)]
        XCTAssertEqual(ComposerSelection.select(candidates, window: window, dictateButtons: []), 2)
    }
    func testAmbiguousEditorsRemainRejected() {
        let rect = CGRect(x: 300, y: 780, width: 600, height: 30)
        XCTAssertNil(ComposerSelection.select([editor(1, rect), editor(2, rect)], window: window,
                                              dictateButtons: [CGRect(x: 860, y: 830, width: 28, height: 28)]))
    }
}

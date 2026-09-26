import XCTest
@testable import WhisperCore

final class TalkReleaseTests: XCTestCase {
    func testDelayedHostStatesCannotLoseHeldRelease() {
        for phase: HostPhase in [.ready, .listening, .transcribing, .failed, .unavailable, .targetInactive, .permissionRequired] {
            var gesture = TalkGesture()
            XCTAssertEqual(gesture.touchDown(at: 0), .beginDictation)
            gesture.hostChanged(phase)
            XCTAssertEqual(gesture.state, .touching)
            XCTAssertNil(gesture.touchDown(at: 1), "A move in the same touch must not restart recording")
            XCTAssertEqual(gesture.release(at: 4), .finishDictation)
            XCTAssertNil(gesture.release(at: 5))
        }
    }
    func testStartupReadyDoesNotCancelTapLock() {
        var gesture = TalkGesture()
        _ = gesture.touchDown(at: 0); _ = gesture.release(at: 0.1)
        gesture.hostChanged(.ready)
        XCTAssertEqual(gesture.state, .locked)
        gesture.hostChanged(.listening); gesture.hostChanged(.ready)
        XCTAssertEqual(gesture.state, .idle)
    }
    func testRightLockSurvivesNormalListeningButFailureReleasesIt() {
        var gesture = TalkGesture()
        _ = gesture.touchDown(at: 0); _ = gesture.drag(right: 50)
        gesture.hostChanged(.listening)
        XCTAssertNil(gesture.release(at: 4)); XCTAssertEqual(gesture.state, .locked)
        gesture.hostChanged(.failed); XCTAssertEqual(gesture.state, .idle)
    }
    func testRecreatedViewStopsExistingLockedRecordingOnFirstTap() {
        var gesture = TalkGesture()
        gesture.restoreLockedRecording()
        gesture.hostChanged(.listening)
        XCTAssertEqual(gesture.touchDown(at: 50), .finishDictation)
        XCTAssertNil(gesture.release(at: 50.1))
        XCTAssertEqual(gesture.state, .idle)
    }
}

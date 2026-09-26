import XCTest
@testable import MicodexCore

final class BackgroundAndScrollTests: XCTestCase {
    func testScreenOffKeepsOnlyLockedRecordingAlive() {
        XCTAssertEqual(RecordingVisibility.onHide(locked: true, recording: true, stopping: false), .stayActive)
        XCTAssertEqual(RecordingVisibility.onHide(locked: false, recording: true, stopping: false), .finishAndSuspend)
        XCTAssertEqual(RecordingVisibility.onHide(locked: true, recording: false, stopping: false), .disconnect)
        XCTAssertEqual(RecordingVisibility.onHide(locked: false, recording: false, stopping: true), .finishAndSuspend)
    }
    func testRepeatedHideDuringFinishNeverResumesLockedCapture() {
        for recording in [true, false] {
            for locked in [true, false] {
                // watchOS delivers inactive and background separately, including
                // while the final audio and stop acknowledgement are in flight.
                for _ in 0..<2 {
                    XCTAssertEqual(RecordingVisibility.onHide(locked: locked, recording: recording, stopping: true), .finishAndSuspend)
                }
            }
        }
    }
    func testScrollBurstPreservesDistanceAndSettlesWithinTenFrames() {
        var motion = ScrollMotion(); motion.add(160); motion.add(240)
        var sum = 0, frames = 0
        while motion.pending != 0 && frames < 20 { sum += Int(motion.next()); frames += 1 }
        XCTAssertEqual(sum, 400); XCTAssertLessThanOrEqual(frames, 10)
        XCTAssertEqual(motion.next(), 0)
    }
    func testReverseAndStopCannotLeaveOldInertia() {
        var motion = ScrollMotion(); motion.add(500); _ = motion.next()
        motion.add(-20)
        XCTAssertLessThan(motion.next(), 0)
        motion.reset(); XCTAssertEqual(motion.next(), 0)
    }
    func testScrollQueueRemainsBoundedAndSmallMotionSurvives() {
        var motion = ScrollMotion()
        for _ in 0..<1000 { motion.add(600) }
        XCTAssertEqual(motion.pending, 600)
        motion.reset(); motion.add(1); XCTAssertEqual(motion.next(), 1)
    }
}

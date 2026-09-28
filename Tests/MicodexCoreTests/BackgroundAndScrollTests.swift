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

    private func turnDistance(interval: Double, direction: Double = 1) -> Int {
        var crown = CrownAccumulator()
        return (0..<60).reduce(0) { total, index in
            total + Int(crown.add(direction * 0.1, at: Double(index) * interval))
        }
    }

    func testSameRotationTravelsFurtherWhenTurnedFasterInBothDirections() {
        let slow = turnDistance(interval: 0.2)
        let medium = turnDistance(interval: 0.025)
        let fast = turnDistance(interval: 0.01)
        XCTAssertGreaterThan(slow, 0)
        XCTAssertGreaterThan(medium, slow * 2)
        XCTAssertGreaterThan(fast, medium * 2)
        for interval in [0.2, 0.025, 0.01] {
            XCTAssertEqual(turnDistance(interval: interval, direction: -1), -turnDistance(interval: interval))
        }
    }

    func testDecelerationPauseAndReversalRestorePrecision() {
        var crown = CrownAccumulator()
        for index in 0..<30 { _ = crown.add(0.1, at: Double(index) * 0.01) }
        XCTAssertLessThanOrEqual(crown.add(0.01, at: 0.31), 1)
        XCTAssertEqual(crown.add(-0.1, at: 0.32), -1)
        XCTAssertEqual(crown.add(0.1, at: 1), 1)
        crown.reset()
        XCTAssertEqual(crown.add(0.1, at: 1.01), 1)
    }

    func testSubpixelTurnsAccumulateButDoNotLeakAcrossReversals() {
        var crown = CrownAccumulator()
        let sum = (0..<100).reduce(0) { $0 + Int(crown.add(0.01, at: Double($1) * 0.02)) }
        XCTAssertEqual(Double(sum), 12, accuracy: 1)
        crown.reset()
        XCTAssertEqual(crown.add(0.08, at: 0), 0)
        XCTAssertEqual(crown.add(-0.09, at: 0.02), -1)
    }

    func testAccelerationIsStableAcrossCallbackRates() {
        func distance(rate: Int) -> Int {
            var crown = CrownAccumulator()
            return (0..<rate).reduce(0) { $0 + Int(crown.add(5 / Double(rate), at: Double($1) / Double(rate))) }
        }
        let reference = distance(rate: 60)
        XCTAssertEqual(Double(distance(rate: 30)), Double(reference), accuracy: Double(reference) * 0.1)
        XCTAssertEqual(Double(distance(rate: 120)), Double(reference), accuracy: Double(reference) * 0.1)
    }

    func testInvalidClockWrapAndExtremeSpeedCannotLeaveAcceleratedMotion() {
        var crown = CrownAccumulator()
        XCTAssertEqual(crown.add(0.1, at: .nan), 0)
        _ = crown.add(0.1, at: 1)
        XCTAssertEqual(crown.add(0.1, at: 1), 1)
        XCTAssertEqual(crown.add(0.1, at: 0), 1)
        XCTAssertEqual(crown.add(99, at: 0.001), 600)
        XCTAssertEqual(crown.add(-20000, at: 0.002), 0)
        XCTAssertEqual(crown.add(0.1, at: 0.003), 1)
    }

    func testAcceleratedScrollStillSettlesAndReversesWithoutInertia() {
        var crown = CrownAccumulator(), motion = ScrollMotion()
        for index in 0..<30 { motion.add(Int(crown.add(0.1, at: Double(index) * 0.01))) }
        motion.add(Int(crown.add(-0.1, at: 0.3)))
        XCTAssertEqual(motion.next(), -1)
        XCTAssertEqual(motion.next(), 0)
        motion.add(600)
        for _ in 0..<10 { _ = motion.next() }
        XCTAssertEqual(motion.pending, 0)
    }

    func testTransportBacklogCannotSwallowSmallReverseAfterFastTurn() {
        XCTAssertEqual(ScrollMotion.coalescing(500, with: -1), -1)
        XCTAssertEqual(ScrollMotion.coalescing(-500, with: 1), 1)
        XCTAssertEqual(ScrollMotion.coalescing(500, with: 200), 600)
        XCTAssertEqual(ScrollMotion.coalescing(-500, with: -200), -600)
        XCTAssertEqual(ScrollMotion.coalescing(10, with: 20), 30)
        XCTAssertEqual(ScrollMotion.coalescing(10, with: 0), 10)
    }
}

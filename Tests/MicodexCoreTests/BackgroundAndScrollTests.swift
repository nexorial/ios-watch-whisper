import XCTest
@testable import MicodexCore

final class BackgroundAndScrollTests: XCTestCase {
    func testScreenOffKeepsTapRecordingAliveWithoutAGestureLock() {
        XCTAssertEqual(RecordingVisibility.onHide(recording: true, stopping: false), .stayActive)
        XCTAssertEqual(RecordingVisibility.onHide(recording: false, stopping: false), .disconnect)
    }
    func testRepeatedHideDuringFinishNeverResumesCapture() {
        for recording in [true, false] {
            // watchOS delivers inactive and background separately, including
            // while final audio and the stop acknowledgement are in flight.
            for _ in 0..<2 {
                XCTAssertEqual(RecordingVisibility.onHide(recording: recording, stopping: true), .finishAndSuspend)
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

    private func turnDistance(velocity: Double, direction: Double = 1, samples: Int = 60) -> Int {
        var crown = CrownAccumulator()
        return (0..<samples).reduce(0) { total, _ in
            total + Int(crown.add(direction / Double(samples), velocity: direction * velocity))
        }
    }

    func testFastTurnMovesScreensInsteadOfOnlyAFewPixels() {
        let slow = turnDistance(velocity: 0.2)
        let medium = turnDistance(velocity: 2)
        let fast = turnDistance(velocity: 4)
        XCTAssertEqual(Double(slow), 240, accuracy: 1)
        XCTAssertGreaterThan(medium, 1000)
        XCTAssertGreaterThan(fast, 2800)
        XCTAssertGreaterThan(fast, slow * 10)
        for velocity in [0.2, 2, 4] {
            XCTAssertEqual(turnDistance(velocity: velocity, direction: -1), -turnDistance(velocity: velocity))
        }
    }

    func testNativeVelocityRespondsOnFirstEventAndImmediatelyDecelerates() {
        var crown = CrownAccumulator()
        XCTAssertGreaterThan(crown.add(0.05, velocity: 4), 100)
        XCTAssertEqual(crown.add(0.01, velocity: 0.2), 2)
        XCTAssertEqual(crown.add(-0.01, velocity: -0.2), -2)
        crown.reset()
        XCTAssertEqual(crown.add(0.01, velocity: 0.2), 2)
    }

    func testContinuousSubpixelTurnsAccumulateAndReversePrecisely() {
        var crown = CrownAccumulator()
        let sum = (0..<100).reduce(0) { total, _ in total + Int(crown.add(0.0005, velocity: 0.2)) }
        XCTAssertEqual(Double(sum), 12, accuracy: 1)
        crown.reset()
        XCTAssertEqual(crown.add(0.004, velocity: 0.2), 0)
        XCTAssertEqual(crown.add(-0.005, velocity: -0.2), -1)
    }

    func testNativeSpeedIsIndependentOfCallbackBatching() {
        let reference = turnDistance(velocity: 2)
        for samples in [15, 30, 120] {
            XCTAssertEqual(Double(turnDistance(velocity: 2, samples: samples)), Double(reference), accuracy: 1)
        }
    }

    func testInvalidVelocityWrapAndExtremeSpeedRemainBounded() {
        var crown = CrownAccumulator()
        XCTAssertEqual(crown.add(0.1, velocity: .nan), 0)
        XCTAssertEqual(crown.add(0.1, velocity: .infinity), 0)
        XCTAssertEqual(crown.add(99, velocity: 1000), 600)
        XCTAssertEqual(crown.add(-20000, velocity: 2), 0)
        XCTAssertEqual(crown.add(0.01, velocity: 0.2), 2)
    }

    func testAcceleratedScrollStillSettlesAndReversesWithoutInertia() {
        var crown = CrownAccumulator(), motion = ScrollMotion()
        for _ in 0..<30 { motion.add(Int(crown.add(0.05, velocity: 4))) }
        motion.add(Int(crown.add(-0.005, velocity: -0.2)))
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

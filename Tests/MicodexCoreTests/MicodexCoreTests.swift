import XCTest
@testable import MicodexCore

final class MicodexCoreTests: XCTestCase {
    private let key = Data(repeating: 0x41, count: 32)
    private let nonce = Data(repeating: 0x71, count: 16)

    func testEveryCommandFitsMinimumBluetoothMTUAndRoundTrips() throws {
        for action in [RemoteAction.heartbeat, .beginDictation, .finishDictation, .scroll, .enter, .cancelDictation, .finishReceivedAudio] {
            let command = Command(action, sequence: 1, value: action == .scroll ? -231 : 0)
            let bytes = try Wire.encode(command, key: key, challenge: nonce)
            XCTAssertEqual(bytes.count, 20)
            XCTAssertEqual(try Wire.decode(bytes, key: key, challenge: nonce), command)
        }
    }
    func testBoundarySequenceAndScrollValuesRoundTrip() throws {
        for seq: UInt32 in [1, 255, 256, 65535, UInt32.max] {
            for value: Int16 in [-600, 0, 600] {
                let c = Command(.scroll, sequence: seq, value: value)
                XCTAssertEqual(try Wire.decode(Wire.encode(c, key: key, challenge: nonce), key: key, challenge: nonce), c)
            }
        }
    }
    func testEveryByteTamperingIsRejected() throws {
        let bytes = try Wire.encode(Command(.enter, sequence: 3), key: key, challenge: nonce)
        for i in 0..<bytes.count {
            var altered = bytes; altered[i] ^= 1
            XCTAssertThrowsError(try Wire.decode(altered, key: key, challenge: nonce), "Byte \(i)")
        }
    }
    func testOldConnectionAndWrongDeviceKeysCannotAuthenticate() throws {
        let bytes = try Wire.encode(Command(.beginDictation, sequence: 1), key: key, challenge: nonce)
        XCTAssertThrowsError(try Wire.decode(bytes, key: key, challenge: Data(repeating: 2, count: 16)))
        XCTAssertThrowsError(try Wire.decode(bytes, key: Data(repeating: 1, count: 32), challenge: nonce))
    }
    func testMalformedPacketsAndInvalidActionsHaveNoCommand() throws {
        for length in [0, 1, 8, 19, 21, 200] { XCTAssertThrowsError(try Wire.decode(Data(repeating: 1, count: length), key: key, challenge: nonce)) }
        XCTAssertThrowsError(try Wire.encode(Command(.enter, sequence: 1), key: Data(), challenge: nonce))
        let zero = try Wire.encode(Command(.enter, sequence: 0), key: key, challenge: nonce)
        XCTAssertThrowsError(try Wire.decode(zero, key: key, challenge: nonce))
        let outOfRange = try Wire.encode(Command(.scroll, sequence: 1, value: 601), key: key, challenge: nonce)
        XCTAssertThrowsError(try Wire.decode(outOfRange, key: key, challenge: nonce))
        let invalidValue = try Wire.encode(Command(.enter, sequence: 1, value: 1), key: key, challenge: nonce)
        XCTAssertThrowsError(try Wire.decode(invalidValue, key: key, challenge: nonce))
    }
    func testStatusCannotBeReflectedAsCommand() throws {
        let data = try Wire.status(.listening, sequence: 4, key: key, challenge: nonce)
        XCTAssertEqual(data.count, 20)
        let (phase, seq) = try Wire.decodeStatus(data, key: key, challenge: nonce)
        XCTAssertEqual(phase, .listening); XCTAssertEqual(seq, 4)
        XCTAssertThrowsError(try Wire.decode(data, key: key, challenge: nonce))
        let command = try Wire.encode(Command(.enter, sequence: 4), key: key, challenge: nonce)
        XCTAssertThrowsError(try Wire.decodeStatus(command, key: key, challenge: nonce))
    }
    func testAllFailureStatesSurviveTransport() throws {
        for raw: UInt8 in 0...6 {
            let phase = HostPhase(rawValue: raw)!
            let encoded = try Wire.status(phase, sequence: 0x01020304, key: key, challenge: nonce)
            let decoded = try Wire.decodeStatus(encoded, key: key, challenge: nonce)
            XCTAssertEqual(decoded.0, phase); XCTAssertEqual(decoded.1, 0x01020304)
        }
    }
    func testEnterIsNeverExecutedTwiceEvenWithDelayedDuplicate() throws {
        var gate = ReplayGate()
        try gate.accept(Command(.enter, sequence: 10))
        XCTAssertThrowsError(try gate.accept(Command(.enter, sequence: 10)))
        XCTAssertThrowsError(try gate.accept(Command(.enter, sequence: 9)))
        try gate.accept(Command(.heartbeat, sequence: 11))
        XCTAssertThrowsError(try gate.accept(Command(.enter, sequence: 10)))
    }
    func testCrownAccumulatesSmallMovesAndRejectsWrapAndInvalidInput() {
        var crown = CrownAccumulator()
        XCTAssertEqual(crown.add(0.001, velocity: 0.2), 0)
        XCTAssertEqual(crown.add(0.004, velocity: 0.2), 1)
        XCTAssertEqual(crown.add(1, velocity: 0.2), 240)
        XCTAssertEqual(crown.add(-2, velocity: -0.2), -480)
        XCTAssertEqual(crown.add(20000, velocity: 1), 0)
        XCTAssertEqual(crown.add(.nan, velocity: 1), 0)
        XCTAssertEqual(crown.add(.infinity, velocity: 1), 0)
    }
    func testDisconnectLeaseAndAbsoluteRecordingLimit() {
        var lease = RecordingLease()
        XCTAssertFalse(lease.expired(at: 200))
        lease.begin(at: 10)
        XCTAssertFalse(lease.expired(at: 14))
        XCTAssertTrue(lease.expired(at: 16))
        lease.renew(at: 16); XCTAssertFalse(lease.expired(at: 17))
        lease.renew(at: 130); XCTAssertTrue(lease.expired(at: 131))
        lease.finish(); XCTAssertFalse(lease.expired(at: 1000))
    }
    func testFastCrownTurnDoesNotQueueStaleMotionAfterReversing() {
        var crown = CrownAccumulator()
        XCTAssertEqual(crown.add(99, velocity: 4), 600)
        XCTAssertEqual(crown.add(-0.01, velocity: -0.2), -2)
    }
    func testDictationLabelsCannotMatchVoiceChatOrSend() {
        for text in ["Start voice chat", "Stop", "Transcribe and send", "转录并发送", "停止任务"] {
            XCTAssertFalse(AgentLabels.dictate.contains(text))
            XCTAssertFalse(AgentLabels.stop.contains(text))
            XCTAssertFalse(AgentLabels.cancel.contains(text))
        }
        XCTAssertTrue(AgentLabels.dictate.contains("听写"))
        XCTAssertTrue(AgentLabels.stop.contains("停止听写"))
    }
}

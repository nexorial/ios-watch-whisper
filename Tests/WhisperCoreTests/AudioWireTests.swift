import XCTest
@testable import WhisperCore

final class AudioWireTests: XCTestCase {
    let key = Data(repeating: 0x71, count: 32), nonce = Data(repeating: 0x39, count: 16)
    func encode(_ samples: [Int16], stream: UInt32 = 4, sequence: UInt32 = 1, offset: UInt32 = 0, ended: Bool = false) throws -> Data {
        try AudioWire.encode(samples: samples, stream: stream, sequence: sequence, offset: offset, ended: ended, key: key, challenge: nonce)
    }
    func decode(_ packet: Data) throws -> AudioWire.Frame { try AudioWire.decode(packet, key: key, challenge: nonce) }
    func testBluetoothSizesAndSpeechBandSignalQuality() throws {
        for mtu in [64, 185, 512] {
            let count = min(512, (mtu - AudioWire.overhead) * 2)
            let samples = (0..<count).map { i in Int16(12000 * sin(Double(i) * 2 * .pi * 440 / 16000)) }
            let packet = try encode(samples)
            XCTAssertLessThanOrEqual(packet.count, mtu)
            let decoded = try decode(packet).samples
            XCTAssertEqual(decoded.count, samples.count)
            XCTAssertEqual(decoded[0], samples[0])
            let error = zip(samples, decoded).map { pow(Double($0.0) - Double($0.1), 2) }.reduce(0,+)
            let energy = samples.map { pow(Double($0), 2) }.reduce(0,+)
            XCTAssertLessThan(error / energy, 0.02, "Keep speech-band quantization noise bounded")
        }
    }
    func testShortOddEvenAndClippedBlocks() throws {
        for samples: [Int16] in [[0], [0,1], [Int16.min, 0, Int16.max], [1,2,3,4,5], [0,0,0,0]] {
            XCTAssertEqual(try decode(encode(samples)).samples.count, samples.count)
        }
        XCTAssertThrowsError(try encode([]))
        XCTAssertThrowsError(try encode([1], ended: true))
    }
    func testEveryAudioByteIsAuthenticatedAndOtherConnectionsAreRejected() throws {
        let packet = try encode([0, 1000, -1000, 4000])
        for i in packet.indices {
            var corrupt = packet; corrupt[i] ^= 1
            XCTAssertThrowsError(try decode(corrupt))
        }
        XCTAssertThrowsError(try AudioWire.decode(packet, key: key, challenge: Data(repeating: 1, count: 16)))
        XCTAssertThrowsError(try Wire.decode(packet, key: key, challenge: nonce))
    }
    func testMissingFrameDoesNotCorruptNextBlockAndCannotReplayAcrossRecordings() throws {
        var gate = AudioGate(stream: 4)
        XCTAssertEqual(try gate.accept(decode(encode([100,200,300]))), 0)
        let next = try decode(encode([1000,1100], sequence: 3, offset: 8))
        XCTAssertEqual(try gate.accept(next), 5)
        XCTAssertEqual(next.samples.first, 1000)
        XCTAssertThrowsError(try gate.accept(next))
        XCTAssertThrowsError(try gate.accept(decode(encode([1], stream: 5, sequence: 4, offset: 10))))
        XCTAssertThrowsError(try gate.accept(decode(encode([1], sequence: 4, offset: 9))))
        XCTAssertEqual(try gate.accept(decode(encode([], sequence: 4, offset: 12, ended: true))), 2)
        XCTAssertTrue(gate.ended)
        XCTAssertThrowsError(try gate.accept(decode(encode([1], sequence: 5, offset: 12))))
    }
    func testStallAndRecordingLimitFailClosed() throws {
        var gate = AudioGate(stream: 4)
        XCTAssertThrowsError(try gate.accept(decode(encode([1], offset: 8001))))
        XCTAssertThrowsError(try gate.accept(decode(encode([1], offset: UInt32.max))))
    }
}

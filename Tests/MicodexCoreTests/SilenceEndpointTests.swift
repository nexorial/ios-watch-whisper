import XCTest
@testable import MicodexCore

final class SilenceEndpointTests: XCTestCase {
    func testStopsAfterTwoSecondsAndOnlyOnce() {
        var endpoint = SilenceEndpoint()
        XCTAssertNil(endpoint.consume(Array(repeating: 2000, count: 1600)))
        XCTAssertNil(endpoint.consume(Array(repeating: 0, count: 31999)))
        XCTAssertEqual(endpoint.consume([0]), .quietAfterSound)
        XCTAssertNil(endpoint.consume(Array(repeating: 0, count: 32000)))
    }
    func testSpeakingAgainResetsQuietCountdown() {
        var endpoint = SilenceEndpoint()
        _ = endpoint.consume(Array(repeating: 1000, count: 1600))
        XCTAssertNil(endpoint.consume(Array(repeating: 0, count: 30400)))
        XCTAssertNil(endpoint.consume(Array(repeating: 150, count: 1600)))
        XCTAssertNil(endpoint.consume(Array(repeating: 0, count: 31680)))
        XCTAssertEqual(endpoint.consume(Array(repeating: 0, count: 320)), .quietAfterSound)
    }
    func testQuietStartupAllowsTimeToBeginAndDoesNotWaitForever() {
        var endpoint = SilenceEndpoint()
        XCTAssertNil(endpoint.consume(Array(repeating: 8, count: 127999)))
        XCTAssertEqual(endpoint.consume([8]), .noSound)
    }
    func testPacketFragmentationDoesNotChangeEndpoint() {
        let samples = Array(repeating: Int16(1000), count: 1600) + Array(repeating: Int16(0), count: 32000)
        for size in [1, 320, 512, 1600] {
            var endpoint = SilenceEndpoint(), reasons: [SilenceEndpoint.Reason] = []
            for start in stride(from: 0, to: samples.count, by: size) {
                if let reason = endpoint.consume(Array(samples[start..<min(samples.count, start + size)])) { reasons.append(reason) }
            }
            XCTAssertEqual(reasons, [.quietAfterSound])
        }
    }
    func testBriefClickDoesNotArmSpeechAndLowSpeechContinues() {
        var click = SilenceEndpoint()
        XCTAssertNil(click.consume(Array(repeating: 20000, count: 320)))
        XCTAssertNil(click.consume(Array(repeating: 0, count: 32000)))
        var speech = SilenceEndpoint()
        _ = speech.consume(Array(repeating: 200, count: 1600))
        XCTAssertNil(speech.consume(Array(repeating: 75, count: 64000)))
    }
    func testQuietRoomNoiseAfterSpeechStillEnds() {
        var endpoint = SilenceEndpoint()
        _ = endpoint.consume(Array(repeating: 2000, count: 1600))
        XCTAssertEqual(endpoint.consume(Array(repeating: 120, count: 32000)), .quietAfterSound)
    }
}

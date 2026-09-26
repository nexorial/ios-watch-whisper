import AVFoundation
import XCTest
@testable import MicodexCore

final class MicrophoneSamplesTests: XCTestCase {
    func testRealConverterPreservesSpeechLevelAtSupportedInputRates() throws {
        for rate in [16000.0, 24000.0, 44100.0, 48000.0] {
            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
            let converter = try MicrophoneSamples(source: format)
            var level = AudioLevel()
            for block in 0..<10 {
                let frames = Int(rate / 10)
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
                buffer.frameLength = AVAudioFrameCount(frames)
                for i in 0..<frames { buffer.floatChannelData![0][i] = Float(0.02 * sin(Double(block * frames + i) * 2 * .pi * 440 / rate)) }
                level.append(try converter.convert(buffer))
            }
            XCTAssertGreaterThan(level.sampleCount, 15000)
            XCTAssertLessThanOrEqual(level.sampleCount, 16000)
            XCTAssertEqual(Double(level.peak), 655, accuracy: 5)
            XCTAssertGreaterThan(level.rmsDecibels ?? -100, -40)
        }
    }
    func testSilenceAndQuietSignalAreDistinct() {
        var silence = AudioLevel(); silence.append([0, 0, 0])
        XCTAssertEqual(silence.nonzeroCount, 0); XCTAssertNil(silence.rmsDecibels)
        var quiet = AudioLevel(); quiet.append([1, -1, 0])
        XCTAssertEqual(quiet.peak, 1); XCTAssertEqual(quiet.nonzeroCount, 2)
        XCTAssertNotNil(quiet.peakDecibels)
        XCTAssertTrue(quiet.diagnostic.contains("1/32768"))
    }
    func testFullScaleNegativeDoesNotOverflowAndMetricsAccumulate() {
        var level = AudioLevel(); level.append([Int16.min, Int16.max]); level.append([0, 1])
        XCTAssertEqual(level.peak, 32768); XCTAssertEqual(level.sampleCount, 4)
        XCTAssertEqual(level.nonzeroCount, 3); XCTAssertEqual(level.peakDecibels, 0)
    }
    func testEmptyInputDoesNotInventSound() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let converter = try MicrophoneSamples(source: format)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)!
        XCTAssertTrue(try converter.convert(buffer).isEmpty)
        XCTAssertEqual(AudioLevel().caption, "尚未检测到声音")
    }
}

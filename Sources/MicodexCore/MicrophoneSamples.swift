import AVFoundation

/// Shared so tests exercise the exact Watch resampling path without opening a mic.
public final class MicrophoneSamples {
    private let converter: AVAudioConverter
    private let source: AVAudioFormat
    private let target: AVAudioFormat
    public init(source: AVAudioFormat) throws {
        guard source.sampleRate > 0, source.channelCount > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: target) else { throw Failure.invalidFormat }
        self.source = source; self.target = target; self.converter = converter
    }
    public func convert(_ buffer: AVAudioPCMBuffer) throws -> [Int16] {
        guard buffer.format == source else { throw Failure.changedFormat }
        guard buffer.frameLength > 0 else { return [] }
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16_000 / source.sampleRate) + 32)
        guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { throw Failure.invalidFormat }
        var consumed = false, error: NSError?
        let result = converter.convert(to: converted, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true; status.pointee = .haveData; return buffer
        }
        if let error { throw error }
        guard result != .error else { throw Failure.conversion }
        guard converted.frameLength > 0 else { return [] }
        guard let channel = converted.int16ChannelData?[0] else { throw Failure.conversion }
        return Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
    }
    public enum Failure: Error { case invalidFormat, changedFormat, conversion }
}

import Foundation

/// Aggregate signal measurements only. Does not retain or serialize audio samples.
public struct AudioLevel: Sendable {
    public private(set) var sampleCount = 0
    public private(set) var nonzeroCount = 0
    public private(set) var peak = 0
    private var sumSquares = 0.0
    public init() {}
    public mutating func append(_ samples: [Int16]) {
        sampleCount += samples.count
        for sample in samples {
            let magnitude = abs(Int(sample))
            peak = max(peak, magnitude)
            if magnitude > 0 { nonzeroCount += 1 }
            sumSquares += Double(sample) * Double(sample)
        }
    }
    public var peakDecibels: Double? { peak > 0 ? 20 * log10(Double(peak) / 32768) : nil }
    public var rmsDecibels: Double? {
        guard sampleCount > 0, sumSquares > 0 else { return nil }
        return 10 * log10(sumSquares / Double(sampleCount) / (32768 * 32768))
    }
    public var caption: String {
        guard let rmsDecibels else { return "尚未检测到声音" }
        return rmsDecibels < -50 ? "输入音量很低，请靠近手表说话" : "已检测到输入音量"
    }
    public var diagnostic: String {
        let rms = rmsDecibels.map { String(format: "%.1f dBFS", $0) } ?? "静音"
        return String(format: "%.1f 秒", Double(sampleCount) / 16000)
            + " · 峰值 \(peak)/32768 · RMS \(rms) · 非零 \(nonzeroCount)"
    }
}

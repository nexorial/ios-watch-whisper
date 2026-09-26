import Foundation

/// Local energy-based endpointing of 16 kHz PCM. Stores counters/energy only.
/// Fixed 20 ms windows keep the result independent of transport packet sizes.
public struct SilenceEndpoint {
    public enum Reason: Equatable { case quietAfterSound, noSound }
    private var windowCount = 0
    private var energy = 0.0
    private var totalSamples = 0
    private var soundSamples = 0
    private var quietSamples = 0
    private var heardSound = false
    private var speechEnergy = 0.0
    private var ended = false
    public init() {}
    public mutating func consume(_ samples: [Int16]) -> Reason? {
        guard !ended else { return nil }
        for sample in samples {
            energy += Double(sample) * Double(sample); windowCount += 1; totalSamples += 1
            guard windowCount == 320 else { continue }
            let meanEnergy = energy / 320
            // Follow the spoken level enough to treat quiet room noise as
            // silence, while preserving soft voices. This is energy endpointing,
            // not a claim to recognize speech amid arbitrary background noise.
            let base = pow(10, (heardSound ? -56.0 : -50.0) / 10) * 32768 * 32768
            let ceiling = pow(10, -42.0 / 10) * 32768 * 32768
            let threshold = heardSound ? max(base, min(ceiling, speechEnergy / 100)) : base
            if meanEnergy >= threshold {
                soundSamples += 320; quietSamples = 0
                if soundSamples >= 960 { heardSound = true; speechEnergy = max(speechEnergy, meanEnergy) }
            } else {
                soundSamples = 0
                if heardSound { quietSamples += 320 }
            }
            windowCount = 0; energy = 0
            if heardSound && quietSamples >= 32_000 { ended = true; return .quietAfterSound }
            if !heardSound && totalSamples >= 128_000 { ended = true; return .noSound }
        }
        return nil
    }
}

import Foundation

/// Run only with the explicitly selected BlackHole input. Uses the production
/// output class; sends a one-second test signal to the virtual device, not speakers.
@main
struct VirtualMicrophoneSmoke {
    @MainActor static func main() async throws {
        let output = WatchAudioOutput()
        try output.start()
        defer { output.stop() }
        for block in 0..<50 {
            let samples = (0..<320).map { frame in
                Int16(4000 * sin(Double(block * 320 + frame) * 2 * .pi * 440 / 16000))
            }
            try output.enqueue(samples)
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try await output.drain()
        guard output.receivedSamples == 16000 else { throw WatchAudioOutput.AudioFailure("Sample count mismatch") }
        print("PASS: 16000 mono samples routed to BlackHole and playback queue drained")
    }
}

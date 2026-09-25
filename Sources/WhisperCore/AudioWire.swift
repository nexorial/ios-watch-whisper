import Foundation
import CryptoKit

/// Independent IMA ADPCM blocks: lost packets cannot corrupt later decoding.
/// 16 kHz mono, authenticated separately from control messages.
public enum AudioWire {
    public static let characteristic = "A7094506-557B-46BE-8DCC-C02A86C64821"
    public static let sampleRate = 16_000
    public static let overhead = 31
    public struct Frame {
        public let stream: UInt32
        public let sequence: UInt32
        public let offset: UInt32
        public let samples: [Int16]
        public let ended: Bool
    }
    private static let steps = [7,8,9,10,11,12,13,14,16,17,19,21,23,25,28,31,34,37,41,45,50,55,60,66,73,80,88,97,107,118,130,143,157,173,190,209,230,253,279,307,337,371,408,449,494,544,598,658,724,796,876,963,1060,1166,1282,1411,1552,1707,1878,2066,2272,2499,2749,3024,3327,3660,4026,4428,4871,5358,5894,6484,7132,7845,8630,9493,10442,11487,12635,13899,15289,16818,18500,20350,22385,24623,27086,29794,32767]
    private static let adjustments = [-1,-1,-1,-1,2,4,6,8]
    private static func advance(_ nibble: Int, predictor: inout Int, index: inout Int) {
        let step = steps[index]
        let delta = (step >> 3) + ((nibble & 1) != 0 ? step >> 2 : 0)
            + ((nibble & 2) != 0 ? step >> 1 : 0) + ((nibble & 4) != 0 ? step : 0)
        predictor = max(-32768, min(32767, predictor + ((nibble & 8) != 0 ? -delta : delta)))
        index = max(0, min(88, index + adjustments[nibble & 7]))
    }
    public static func encode(samples: [Int16], stream: UInt32, sequence: UInt32, offset: UInt32,
                              ended: Bool = false, key: Data, challenge: Data) throws -> Data {
        guard key.count == 32, challenge.count == 16 else { throw WireError.invalidKey }
        guard stream > 0, sequence > 0, samples.count <= 960,
              ended ? samples.isEmpty : !samples.isEmpty else { throw WireError.malformed }
        var bytes: [UInt8] = [2, ended ? 0x41 : 0x40]
        for value in [stream, sequence, offset] {
            bytes += [UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
                      UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
        }
        let first = UInt16(bitPattern: samples.first ?? 0)
        let initialDelta = zip(samples.prefix(16), samples.dropFirst().prefix(16))
            .map { abs(Int($0.0) - Int($0.1)) }.max() ?? 0
        let initialIndex = steps.firstIndex(where: { $0 >= max(7, initialDelta / 2) }) ?? 88
        bytes += [UInt8(samples.count >> 8), UInt8(truncatingIfNeeded: samples.count),
                  UInt8(first >> 8), UInt8(truncatingIfNeeded: first), UInt8(initialIndex)]
        var predictor = Int(samples.first ?? 0), index = initialIndex, pending: Int?
        for sample in samples.dropFirst() {
            let difference = Int(sample) - predictor
            var magnitude = abs(difference), nibble = difference < 0 ? 8 : 0
            let step = steps[index]
            if magnitude >= step { nibble |= 4; magnitude -= step }
            if magnitude >= step >> 1 { nibble |= 2; magnitude -= step >> 1 }
            if magnitude >= step >> 2 { nibble |= 1 }
            advance(nibble, predictor: &predictor, index: &index)
            if let low = pending { bytes.append(UInt8(low | (nibble << 4))); pending = nil }
            else { pending = nibble }
        }
        if let pending { bytes.append(UInt8(pending)) }
        let body = Data(bytes)
        return body + Data(HMAC<SHA256>.authenticationCode(for: challenge + body, using: SymmetricKey(data: key)).prefix(12))
    }
    public static func decode(_ data: Data, key: Data, challenge: Data) throws -> Frame {
        guard key.count == 32, challenge.count == 16 else { throw WireError.invalidKey }
        guard data.count >= overhead, data.count <= overhead + 480 else { throw WireError.malformed }
        let b = Array(data), body = data.dropLast(12)
        let tag = Array(HMAC<SHA256>.authenticationCode(for: challenge + body, using: SymmetricKey(data: key)).prefix(12))
        var difference: UInt8 = 0
        for i in 0..<12 { difference |= tag[i] ^ b[b.count - 12 + i] }
        guard difference == 0 else { throw WireError.unauthenticated }
        guard b[0] == 2, [0x40, 0x41].contains(b[1]), b[18] <= 88 else { throw WireError.malformed }
        func integer(_ at: Int) -> UInt32 { UInt32(b[at]) << 24 | UInt32(b[at+1]) << 16 | UInt32(b[at+2]) << 8 | UInt32(b[at+3]) }
        let stream = integer(2), sequence = integer(6), offset = integer(10)
        let count = Int(b[14]) << 8 | Int(b[15]), ended = b[1] == 0x41
        guard stream > 0, sequence > 0, count <= 960,
              ended ? count == 0 : count > 0,
              data.count == overhead + count / 2 else { throw WireError.malformed }
        var predictor = Int(Int16(bitPattern: UInt16(b[16]) << 8 | UInt16(b[17]))), index = Int(b[18])
        var samples: [Int16] = count > 0 ? [Int16(predictor)] : []
        for i in 0..<max(0, count - 1) {
            let nibble = Int(b[19+i/2] >> (i % 2 == 0 ? 0 : 4)) & 15
            advance(nibble, predictor: &predictor, index: &index)
            samples.append(Int16(predictor))
        }
        return Frame(stream: stream, sequence: sequence, offset: offset, samples: samples, ended: ended)
    }
}

/// Bound to the authenticated begin command's sequence; reused/stale sessions fail closed.
public struct AudioGate {
    public private(set) var stream: UInt32
    public private(set) var nextOffset: UInt32 = 0
    public private(set) var sequence: UInt32 = 0
    public private(set) var ended = false
    public init(stream: UInt32) { self.stream = stream }
    public mutating func accept(_ frame: AudioWire.Frame) throws -> Int {
        guard !ended, frame.stream == stream, frame.sequence > sequence,
              frame.offset >= nextOffset else { throw WireError.replay }
        let gap = frame.offset - nextOffset
        // Stop instead of concealing a stalled link or unbounded recording.
        guard gap <= 8_000, UInt64(frame.offset) + UInt64(frame.samples.count) <= 1_920_000 else { throw WireError.malformed }
        sequence = frame.sequence; nextOffset = frame.offset + UInt32(frame.samples.count); ended = frame.ended
        return Int(gap)
    }
}

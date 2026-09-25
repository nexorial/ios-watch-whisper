import Foundation
import CryptoKit

public enum RemoteAction: UInt8, Sendable {
    case heartbeat = 0, beginDictation, finishDictation, scroll, enter, cancelDictation
}

public enum HostPhase: UInt8, Sendable {
    case ready = 0, listening, transcribing, permissionRequired, targetInactive, unavailable, failed

    public var caption: String {
        switch self {
        case .ready: return "准备好了"
        case .listening: return "Mac 正在听"
        case .transcribing: return "正在转写…"
        case .permissionRequired: return "请在 Mac 允许辅助功能"
        case .targetInactive: return "请在 Mac 打开目标任务"
        case .unavailable: return "未找到听写或输入框"
        case .failed: return "操作未完成，请查看 Mac"
        }
    }
}

public struct Command: Equatable, Sendable {
    public let action: RemoteAction
    public let sequence: UInt32
    public let value: Int16
    public init(_ action: RemoteAction, sequence: UInt32, value: Int16 = 0) {
        self.action = action; self.sequence = sequence; self.value = value
    }
}

public enum WireError: Error, Equatable {
    case malformed, unauthenticated, replay, invalidKey
}

/// One ATT payload, including at the Bluetooth LE minimum MTU of 23.
/// Header: version, opcode, big-endian sequence (4), signed value (2), HMAC (12).
public enum Wire {
    public static let service = "A7094501-557B-46BE-8DCC-C02A86C64821"
    public static let pairing = "A7094502-557B-46BE-8DCC-C02A86C64821"
    public static let challenge = "A7094503-557B-46BE-8DCC-C02A86C64821"
    public static let command = "A7094504-557B-46BE-8DCC-C02A86C64821"
    public static let status = "A7094505-557B-46BE-8DCC-C02A86C64821"

    public static func encode(_ command: Command, key: Data, challenge: Data) throws -> Data {
        try packet(type: command.action.rawValue, sequence: command.sequence,
                   value: command.value, key: key, challenge: challenge)
    }
    public static func decode(_ data: Data, key: Data, challenge: Data) throws -> Command {
        let p = try unpack(data, key: key, challenge: challenge)
        guard let action = RemoteAction(rawValue: p.0), p.1 > 0 else { throw WireError.malformed }
        guard action == .scroll || p.2 == 0,
              action != .scroll || (-600...600).contains(Int(p.2)) else { throw WireError.malformed }
        return Command(action, sequence: p.1, value: p.2)
    }
    public static func status(_ phase: HostPhase, sequence: UInt32, key: Data, challenge: Data) throws -> Data {
        try packet(type: 0x80 | phase.rawValue, sequence: sequence, value: 0, key: key, challenge: challenge)
    }
    public static func decodeStatus(_ data: Data, key: Data, challenge: Data) throws -> (HostPhase, UInt32) {
        let p = try unpack(data, key: key, challenge: challenge)
        guard p.0 & 0x80 != 0, let phase = HostPhase(rawValue: p.0 & 0x7f), p.2 == 0 else { throw WireError.malformed }
        return (phase, p.1)
    }
    private static func packet(type: UInt8, sequence: UInt32, value: Int16, key: Data, challenge: Data) throws -> Data {
        guard key.count == 32, challenge.count == 16 else { throw WireError.invalidKey }
        let v = UInt16(bitPattern: value)
        let bytes: [UInt8] = [1, type, UInt8(truncatingIfNeeded: sequence >> 24),
            UInt8(truncatingIfNeeded: sequence >> 16), UInt8(truncatingIfNeeded: sequence >> 8),
            UInt8(truncatingIfNeeded: sequence), UInt8(v >> 8), UInt8(truncatingIfNeeded: v)]
        let header = Data(bytes)
        return header + Data(HMAC<SHA256>.authenticationCode(for: challenge + header,
                              using: SymmetricKey(data: key)).prefix(12))
    }
    private static func unpack(_ data: Data, key: Data, challenge: Data) throws -> (UInt8, UInt32, Int16) {
        guard data.count == 20, data.first == 1 else { throw WireError.malformed }
        guard key.count == 32, challenge.count == 16 else { throw WireError.invalidKey }
        let b = Array(data)
        let tag = Array(HMAC<SHA256>.authenticationCode(for: challenge + data.prefix(8), using: SymmetricKey(data: key)).prefix(12))
        var difference: UInt8 = 0
        for i in 0..<12 { difference |= tag[i] ^ b[8 + i] }
        guard difference == 0 else { throw WireError.unauthenticated }
        let seq = UInt32(b[2]) << 24 | UInt32(b[3]) << 16 | UInt32(b[4]) << 8 | UInt32(b[5])
        return (b[1], seq, Int16(bitPattern: UInt16(b[6]) << 8 | UInt16(b[7])))
    }
}

/// Per connection; rotate challenge before resetting this gate. Commands are never retried automatically.
public struct ReplayGate {
    public private(set) var sequence: UInt32 = 0
    public init() {}
    public mutating func accept(_ command: Command) throws {
        guard command.sequence > sequence else { throw WireError.replay }
        sequence = command.sequence
    }
}

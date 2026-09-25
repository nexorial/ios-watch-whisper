import Foundation

public struct HTTPEnvelope: Sendable {
    public let method: String
    public let path: String
    public let body: Data
    public let close: Bool
}
public struct HTTPEnvelopeDecoder {
    private var bytes = Data()
    public init() {}
    public mutating func append(_ data: Data) throws {
        guard bytes.count + data.count <= 65_536 else { throw Error.tooLarge }
        bytes.append(data)
    }
    public mutating func next() throws -> HTTPEnvelope? {
        guard let boundary = bytes.range(of: Data("\r\n\r\n".utf8)) else {
            guard bytes.count <= 8192 else { throw Error.tooLarge }; return nil
        }
        guard boundary.lowerBound <= 8192,
              let header = String(data: bytes[..<boundary.lowerBound], encoding: .utf8) else { throw Error.invalid }
        let lines = header.components(separatedBy: "\r\n")
        let start = lines[0].split(separator: " ")
        guard start.count == 3, ["GET", "POST"].contains(start[0]), start[2] == "HTTP/1.1", start[1].hasPrefix("/") else { throw Error.invalid }
        var headers: [String:String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("\t") else { throw Error.invalid }
            let key = line[..<colon].lowercased()
            guard headers[key] == nil else { throw Error.invalid }
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil, let count = Int(headers["content-length"] ?? "0"), count >= 0, count <= 32_768 else { throw Error.invalid }
        let end = boundary.upperBound + count
        guard bytes.count >= end else { return nil }
        let result = HTTPEnvelope(method: String(start[0]), path: String(start[1]),
                                  body: Data(bytes[boundary.upperBound..<end]), close: headers["connection"]?.lowercased() == "close")
        bytes = Data(bytes.dropFirst(end))
        return result
    }
    public enum Error: Swift.Error { case invalid, tooLarge }
}

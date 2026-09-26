import XCTest
@testable import MicodexCore

final class WiFiWireTests: XCTestCase {
    func testHTTPFragmentsAndPipelinedUTF8Bodies() throws {
        let body = Data("{\"text\":\"你好\"}".utf8)
        let header = Data("POST /v1/pair HTTP/1.1\r\nHost: localhost\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
        var decoder = HTTPEnvelopeDecoder()
        for byte in header.dropLast() { try decoder.append(Data([byte])); XCTAssertNil(try decoder.next()) }
        try decoder.append(Data(header.suffix(1)) + body.prefix(2)); XCTAssertNil(try decoder.next())
        try decoder.append(body.dropFirst(2) + Data("GET /v1/hello HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8))
        XCTAssertEqual(try decoder.next()?.body, body)
        XCTAssertEqual(try decoder.next()?.path, "/v1/hello")
        XCTAssertNil(try decoder.next())
    }
    func testAmbiguousFramingAndOversizedRequestsAreRejected() throws {
        for headers in ["Content-Length: 1\r\ncontent-length: 2", "Transfer-Encoding: chunked", "Content-Length: -1", "Content-Length: 32769"] {
            var decoder = HTTPEnvelopeDecoder()
            try decoder.append(Data("POST /v1/command HTTP/1.1\r\n\(headers)\r\n\r\n".utf8))
            XCTAssertThrowsError(try decoder.next())
        }
        var header = HTTPEnvelopeDecoder(); try header.append(Data(repeating: 65, count: 8193))
        XCTAssertThrowsError(try header.next())
        var body = HTTPEnvelopeDecoder()
        XCTAssertThrowsError(try body.append(Data(repeating: 65, count: 65537)))
    }
    func testSessionProofIsBoundToDeviceNonceAndKey() {
        let key = Data(repeating: 1, count: 32), nonce = Data(repeating: 2, count: 16)
        let id = UUID().uuidString, proof = WiFiWire.sessionProof(id: id, nonce: nonce, key: key)
        XCTAssertTrue(WiFiWire.validProof(proof, id: id, nonce: nonce, key: key))
        XCTAssertFalse(WiFiWire.validProof(proof, id: UUID().uuidString, nonce: nonce, key: key))
        XCTAssertFalse(WiFiWire.validProof(proof, id: id, nonce: Data(repeating: 3, count: 16), key: key))
        XCTAssertFalse(WiFiWire.validProof(proof, id: id, nonce: nonce, key: Data(repeating: 4, count: 32)))
        XCTAssertFalse(WiFiWire.validProof(Data(), id: id, nonce: nonce, key: key))
    }
    func testPinnedClientRejectsMissingPinAndURLInjection() {
        XCTAssertThrowsError(try PinnedHTTPSClient(host: "127.0.0.1", fingerprint: ""))
        XCTAssertThrowsError(try PinnedHTTPSClient(host: "127.0.0.1/path", fingerprint: String(repeating: "0", count: 64)))
        XCTAssertThrowsError(try PinnedHTTPSClient(host: "user@127.0.0.1", fingerprint: String(repeating: "0", count: 64)))
    }
}

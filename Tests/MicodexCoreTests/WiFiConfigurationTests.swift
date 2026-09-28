import XCTest
@testable import MicodexCore

final class WiFiConfigurationTests: XCTestCase {
    private let pin = String(repeating: "aB", count: 32)

    func testCodePreservesTheEntirePinAndCanonicalizesAddress() throws {
        let configuration = try XCTUnwrap(WiFiConfiguration(connectionCode: " \nmicodex:192.168.001.20:\(pin)\n"))
        XCTAssertEqual(configuration.host, "192.168.1.20")
        XCTAssertEqual(configuration.fingerprint, pin.lowercased())
        XCTAssertEqual(WiFiConfiguration(connectionCode: configuration.connectionCode), configuration)
    }

    func testRejectsIncompletePinsAndAmbiguousEndpoints() {
        for code in ["", "micodex:192.168.1.20", "micodex:192.168.1.20:123456",
                     "micodex:192.168.1.20:\(pin):extra", "https://192.168.1.20:\(pin)",
                     "micodex:127.0.0.1:\(pin)", "micodex:user@192.168.1.20:\(pin)",
                     "micodex:192.168.1.20:\(String(repeating: "g", count: 64))"] {
            XCTAssertNil(WiFiConfiguration(connectionCode: code), code)
        }
    }

    func testMovingMacKeepsIdentityButChangingMacChangesIdentity() throws {
        let original = try XCTUnwrap(WiFiConfiguration(host: "10.0.0.2", fingerprint: pin))
        let moved = try XCTUnwrap(WiFiConfiguration(host: "10.0.0.3", fingerprint: pin))
        XCTAssertEqual(original.fingerprint, moved.fingerprint)
        XCTAssertNotEqual(original, moved)
        XCTAssertNotEqual(original.fingerprint, WiFiConfiguration(host: original.host, fingerprint: String(repeating: "0", count: 64))?.fingerprint)
    }
}

import XCTest
@testable import MicodexCore

final class MacAddressTests: XCTestCase {
    func testAddressFromMacCanBePastedAndCanonicalized() {
        XCTAssertEqual(MacAddress.ipv4(" 192.168.031.99\n"), "192.168.31.99")
        XCTAssertEqual(MacAddress.ipv4("10.0.0.2"), "10.0.0.2")
    }
    func testRejectsURLsPortsIncompleteAndUnroutableAddresses() {
        for input in ["", "192.168.1", "192..1.2", "https://192.168.1.2", "192.168.1.2:8766", "256.1.1.1", "-1.2.3.4", "１２７.0.0.1", "127.0.0.1", "0.0.0.0", "224.0.0.1"] {
            XCTAssertNil(MacAddress.ipv4(input), input)
        }
    }
}

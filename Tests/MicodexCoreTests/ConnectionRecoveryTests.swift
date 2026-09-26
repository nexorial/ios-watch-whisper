import XCTest
@testable import MicodexCore

final class ConnectionRecoveryTests: XCTestCase {
    func testUnreachableCachedMacFallsBackToFreshDiscovery() {
        let mac = UUID()
        var recovery = ConnectionRecovery()
        XCTAssertEqual(recovery.takeCachedID(mac), mac)
        recovery.begin(mac)
        XCTAssertTrue(recovery.failed(mac))
        XCTAssertNil(recovery.takeCachedID(mac))
        // After discovering the Mac again, a verified session permits caching.
        recovery.begin(mac); recovery.authenticated()
        XCTAssertEqual(recovery.takeCachedID(mac), mac)
    }
    func testLateFailureFromForgottenMacCannotClearNewAttempt() {
        let oldMac = UUID(), newMac = UUID()
        var recovery = ConnectionRecovery()
        recovery.begin(oldMac); recovery.forget(); recovery.begin(newMac)
        XCTAssertFalse(recovery.failed(oldMac))
        XCTAssertTrue(recovery.accepts(newMac))
        XCTAssertNil(recovery.takeCachedID(oldMac))
    }
    func testForgetIgnoresCancelledAttemptEvenBeforeNewSelection() {
        let mac = UUID()
        var recovery = ConnectionRecovery()
        recovery.begin(mac); recovery.forget()
        XCTAssertFalse(recovery.accepts(mac))
        XCTAssertFalse(recovery.failed(mac))
        XCTAssertNil(recovery.takeCachedID(mac))
    }
}

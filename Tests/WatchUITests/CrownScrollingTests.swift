import XCTest

final class CrownScrollingTests: XCTestCase {
    func testRealCrownEventsMakeFastTurnsTravelScreensWhileSlowTurnsStayPrecise() throws {
        func turn(velocity: CGFloat) throws -> (pixels: Double, units: Double, velocity: Double) {
            let app = XCUIApplication()
            app.launchArguments = ["--demo", "--crown-diagnostics"]
            app.launch()
            let footer = app.staticTexts["remote.footer"]
            XCTAssertTrue(footer.waitForExistence(timeout: 10))
            XCUIDevice.shared.rotateDigitalCrown(delta: 0.5, velocity: XCUIGestureVelocity(velocity))
            let value = try XCTUnwrap(footer.value as? String)
            let fields = Dictionary(uniqueKeysWithValues: value.split(separator: ";").map {
                let pair = $0.split(separator: "=")
                return (String(pair[0]), Double(pair[1]) ?? 0)
            })
            print("CROWN CALIBRATION speed=\(velocity) \(value)")
            app.terminate()
            return (abs(fields["pixels"] ?? 0), abs(fields["units"] ?? 0), fields["velocity"] ?? 0)
        }
        let slow = try turn(velocity: 0.2)
        let fast = try turn(velocity: 3)
        XCTAssertGreaterThan(slow.pixels, 10)
        XCTAssertGreaterThan(fast.velocity, slow.velocity)
        XCTAssertGreaterThan(fast.pixels, slow.pixels * 3)
        XCTAssertGreaterThan(fast.pixels, 1200, "A quick half turn must traverse more than a desktop screen.")
    }
}

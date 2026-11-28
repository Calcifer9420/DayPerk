import XCTest

final class DayPerkUITests: XCTestCase {
    @MainActor func testIsolatedApplicationLaunch() throws {
        guard let identifier = ProcessInfo.processInfo.environment["DAYPERK_UI_TEST_BUNDLE"], identifier.hasPrefix("app.dayperk.tests.") else { throw XCTSkip("界面测试只能使用独立测试标识") }
        let app = XCUIApplication(bundleIdentifier: identifier)
        app.launch()
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10) || app.state == .runningForeground)
    }
}

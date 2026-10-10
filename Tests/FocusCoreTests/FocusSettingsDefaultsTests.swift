import XCTest
@testable import FocusCore

final class FocusSettingsDefaultsTests: XCTestCase {
    func testDefaultDurationsAreTwentyFiveFiveAndFifteenMinutes() {
        let settings = FocusSettings.defaults

        XCTAssertEqual(settings.focusDuration, 25 * 60)
        XCTAssertEqual(settings.shortBreakDuration, 5 * 60)
        XCTAssertEqual(settings.longBreakDuration, 15 * 60)
    }

    func testNotificationsAreDisabledByDefault() {
        XCTAssertFalse(FocusSettings.defaults.notificationsEnabled)
    }
}

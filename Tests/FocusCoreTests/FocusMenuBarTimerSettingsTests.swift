import XCTest
@testable import FocusCore

final class FocusMenuBarTimerSettingsTests: XCTestCase {
    func testLegacySettingsDefaultMenuBarTimerOffAndValueRoundTrips() throws {
        let legacy = Data(#"{"focusDuration":1500,"shortBreakDuration":300,"longBreakDuration":900,"notificationsEnabled":false}"#.utf8)
        XCTAssertFalse(try JSONDecoder().decode(FocusSettings.self, from: legacy).menuBarTimerEnabled)

        let encoded = try JSONEncoder().encode(FocusSettings(menuBarTimerEnabled: true))
        XCTAssertTrue(try JSONDecoder().decode(FocusSettings.self, from: encoded).menuBarTimerEnabled)
    }
}

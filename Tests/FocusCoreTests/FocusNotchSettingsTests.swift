import Foundation
import XCTest
@testable import FocusCore

final class FocusNotchSettingsTests: XCTestCase {
    func testDefaultSettingsEncodeNotchModeEnabled() throws {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(FocusSettings.defaults)) as? [String: Any]
        XCTAssertEqual(object?["notchModeEnabled"] as? Bool, true)
    }

    func testExplicitFalseSurvivesDecodeAndEncode() throws {
        let data = Data(#"{"focusDuration":1500,"shortBreakDuration":300,"longBreakDuration":900,"notificationsEnabled":true,"soundsEnabled":true,"notchModeEnabled":false}"#.utf8)
        let encoded = try JSONEncoder().encode(JSONDecoder().decode(FocusSettings.self, from: data))
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        XCTAssertEqual(object?["notchModeEnabled"] as? Bool, false)
    }

    func testLegacySettingsKeepValuesAndDefaultNotchModeOn() throws {
        let data = Data(#"{"focusDuration":1200,"shortBreakDuration":240,"longBreakDuration":720,"notificationsEnabled":true,"soundsEnabled":true}"#.utf8)
        let settings = try JSONDecoder().decode(FocusSettings.self, from: data)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
        XCTAssertEqual(settings.focusDuration, 1200)
        XCTAssertEqual(settings.shortBreakDuration, 240)
        XCTAssertEqual(settings.longBreakDuration, 720)
        XCTAssertEqual(settings.notificationsEnabled, true)
        XCTAssertEqual(settings.soundsEnabled, true)
        XCTAssertEqual(object?["notchModeEnabled"] as? Bool, true)
    }

    func testStoreRoundTripsExplicitFalse() throws {
        let suite = "FocusNotchSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let data = Data(#"{"focusDuration":1500,"shortBreakDuration":300,"longBreakDuration":900,"notificationsEnabled":false,"soundsEnabled":false,"notchModeEnabled":false}"#.utf8)
        defaults.set(data, forKey: "focus.settings")
        let loaded = FocusStore(defaults: defaults).loadSettings()
        let encoded = try JSONEncoder().encode(loaded)
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        XCTAssertEqual(object?["notchModeEnabled"] as? Bool, false)
    }
}

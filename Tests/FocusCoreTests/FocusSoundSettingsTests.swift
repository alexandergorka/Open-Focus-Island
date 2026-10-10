import XCTest
@testable import FocusCore

final class FocusSoundSettingsTests: XCTestCase {
    func testDefaultsEncodeSoundsDisabled() throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(FocusSettings.defaults)) as? [String: Any])

        XCTAssertEqual(object["soundsEnabled"] as? Bool, false)
    }

    func testDecodingSoundEnabledSettingsPreservesValue() throws {
        let data = Data(#"{"focusDuration":1500,"shortBreakDuration":300,"longBreakDuration":900,"notificationsEnabled":true,"soundsEnabled":true}"#.utf8)

        let settings = try JSONDecoder().decode(FocusSettings.self, from: data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])

        XCTAssertEqual(settings.focusDuration, 1500)
        XCTAssertEqual(settings.notificationsEnabled, true)
        XCTAssertEqual(object["soundsEnabled"] as? Bool, true)
    }

    func testLegacySettingsKeepDurationsAndNotificationsAndDefaultSoundsOff() throws {
        let data = Data(#"{"focusDuration":1200,"shortBreakDuration":240,"longBreakDuration":720,"notificationsEnabled":true}"#.utf8)

        let settings = try JSONDecoder().decode(FocusSettings.self, from: data)

        XCTAssertEqual(settings.focusDuration, 1200)
        XCTAssertEqual(settings.shortBreakDuration, 240)
        XCTAssertEqual(settings.longBreakDuration, 720)
        XCTAssertTrue(settings.notificationsEnabled)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        XCTAssertEqual(object["soundsEnabled"] as? Bool, false)
    }

    func testMissingRequiredLegacyFieldStillFailsDecoding() {
        let data = Data(#"{"focusDuration":1200,"shortBreakDuration":240,"notificationsEnabled":true}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(FocusSettings.self, from: data))
    }

    func testSoundSettingRoundTripsThroughIsolatedStore() throws {
        let suiteName = "FocusSoundSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FocusStore(defaults: defaults)
        let settings = FocusSettings(soundsEnabled: true)

        try store.saveSettings(settings)

        XCTAssertTrue(store.loadSettings().soundsEnabled)
    }
}

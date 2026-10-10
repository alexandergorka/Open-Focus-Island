import Foundation
import XCTest
@testable import FocusCore

final class FocusLanguageSettingsTests: XCTestCase {
    func testDefaultsAreEnglish() throws {
        XCTAssertEqual(FocusSettings.defaults.language, .english)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(FocusSettings.defaults)) as? [String: Any]
        XCTAssertEqual(object?["language"] as? String, "en")
    }

    func testLegacySettingsWithoutLanguageKeepValuesAndUseEnglish() throws {
        let data = Data(#"{"focusDuration":1200,"shortBreakDuration":240,"longBreakDuration":720,"notificationsEnabled":true,"soundsEnabled":true}"#.utf8)
        let settings = try JSONDecoder().decode(FocusSettings.self, from: data)
        XCTAssertEqual(settings.focusDuration, 1200)
        XCTAssertEqual(settings.shortBreakDuration, 240)
        XCTAssertEqual(settings.longBreakDuration, 720)
        XCTAssertEqual(settings.language, .english)
    }

    func testGermanSurvivesRoundTrip() throws {
        let settings = FocusSettings(language: .german)
        let encoded = try JSONEncoder().encode(settings)
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        XCTAssertEqual(object?["language"] as? String, "de")
        XCTAssertEqual(try JSONDecoder().decode(FocusSettings.self, from: encoded), settings)
    }

    func testUnknownLanguageKeepsOtherSettings() throws {
        let data = Data(#"{"focusDuration":1200,"shortBreakDuration":240,"longBreakDuration":720,"notificationsEnabled":true,"soundsEnabled":true,"language":"fr"}"#.utf8)
        let settings = try JSONDecoder().decode(FocusSettings.self, from: data)
        XCTAssertEqual(settings.focusDuration, 1200)
        XCTAssertEqual(settings.language, .english)

        let suite = "FocusLanguageSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(data, forKey: "focus.settings")
        let loaded = FocusStore(defaults: defaults).loadSettings()
        XCTAssertNotEqual(loaded, .defaults)
        XCTAssertEqual(loaded.focusDuration, 1200)
        XCTAssertEqual(loaded.shortBreakDuration, 240)
        XCTAssertEqual(loaded.longBreakDuration, 720)
        XCTAssertEqual(loaded.language, .english)
    }

    func testTranslatePicksLanguage() {
        XCTAssertEqual(AppLanguage.english.t("Start focus", "Fokus starten"), "Start focus")
        XCTAssertEqual(AppLanguage.german.t("Start focus", "Fokus starten"), "Fokus starten")
    }
}

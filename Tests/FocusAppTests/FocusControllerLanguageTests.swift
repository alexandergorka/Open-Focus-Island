import FocusCore
import XCTest
@testable import OpenFocusIsland

@MainActor
final class FocusControllerLanguageTests: XCTestCase {
    func testSetLanguagePersistsAndRestores() {
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = FocusController(store: store)

        controller.setLanguage(.german)

        XCTAssertEqual(controller.settings.language, .german)
        XCTAssertEqual(store.loadSettings().language, .german)
        XCTAssertEqual(FocusController(store: store).settings.language, .german)
    }

    func testSavingDurationsKeepsLanguage() {
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = FocusController(store: store)
        controller.setLanguage(.german)

        XCTAssertTrue(controller.saveSettings(FocusSettings(focusDuration: 600)))

        XCTAssertEqual(controller.settings.focusDuration, 600)
        XCTAssertEqual(controller.settings.language, .german)
        XCTAssertEqual(store.loadSettings().language, .german)
    }

    func testValidationErrorFollowsLanguage() {
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = FocusController(store: store)

        XCTAssertFalse(controller.saveSettings(FocusSettings(focusDuration: 0)))
        XCTAssertEqual(controller.error, "Please enter values between 1 second and 24 hours for all durations.")

        controller.setLanguage(.german)
        XCTAssertFalse(controller.saveSettings(FocusSettings(focusDuration: 0)))
        XCTAssertEqual(controller.error, "Bitte gib für alle Dauern Werte zwischen 1 Sekunde und 24 Stunden ein.")
    }

    private let suiteName = "FocusControllerLanguageTests.\(UUID().uuidString)"

    private func makeStore() -> (FocusStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (FocusStore(defaults: defaults), defaults)
    }
}

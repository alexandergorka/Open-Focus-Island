import XCTest
@testable import FocusCore

final class FocusStoreTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_000)
    private var suites: [(String, UserDefaults)] = []

    override func tearDown() {
        suites.forEach { $0.1.removePersistentDomain(forName: $0.0) }
        suites.removeAll()
        super.tearDown()
    }

    private func makeStore(_ name: String = UUID().uuidString) -> (FocusStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: name)!
        suites.append((name, defaults))
        defaults.removePersistentDomain(forName: name)
        return (FocusStore(defaults: defaults), defaults)
    }

    func testSettingsRoundTripAndInvalidSaveRetainsPreviousValue() throws {
        let (store, _) = makeStore()
        let settings = FocusSettings(focusDuration: 1, shortBreakDuration: 86_400, longBreakDuration: 9_000, notificationsEnabled: true)
        try store.saveSettings(settings)
        XCTAssertEqual(store.loadSettings(), settings)
        XCTAssertEqual(settings.duration(for: .focus), 1)
        XCTAssertEqual(settings.duration(for: .shortBreak), 86_400)
        XCTAssertEqual(settings.duration(for: .longBreak), 9_000)

        XCTAssertThrowsError(try store.saveSettings(FocusSettings(focusDuration: .infinity)))
        XCTAssertThrowsError(try store.saveSettings(FocusSettings(focusDuration: -1)))
        XCTAssertThrowsError(try store.saveSettings(FocusSettings(focusDuration: 86_401)))
        XCTAssertEqual(store.loadSettings(), settings)
    }

    func testSettingsRejectNonFiniteAndNonPositiveDurations() {
        for duration: TimeInterval in [-1, 0, .nan, .infinity, -Double.infinity, 86_401] {
            XCTAssertFalse(FocusSettings(focusDuration: duration).isValid)
        }
        XCTAssertTrue(FocusSettings(focusDuration: 86_400).isValid)
    }

    func testMissingInvalidAndCorruptSettingsUseDefaults() throws {
        let (store, defaults) = makeStore()
        XCTAssertEqual(store.loadSettings(), .defaults)
        try store.saveSettings(.defaults)
        defaults.set(try JSONEncoder().encode(FocusSettings(focusDuration: 0)), forKey: "focus.settings")
        XCTAssertEqual(store.loadSettings(), .defaults)
        defaults.set(Data("{bad json".utf8), forKey: "focus.settings")
        XCTAssertEqual(store.loadSettings(), .defaults)
    }

    func testRunningAndPausedSessionsRestoreFromStoredDates() throws {
        let (store, _) = makeStore()
        var running = FocusSession()
        XCTAssertTrue(running.start(kind: .focus, duration: 100, at: epoch))
        try store.saveSession(running)
        XCTAssertEqual(store.loadSession(at: epoch.addingTimeInterval(25)).remaining(now: epoch.addingTimeInterval(25)), 75)

        var paused = FocusSession()
        XCTAssertTrue(paused.start(kind: .shortBreak, duration: 100, at: epoch))
        XCTAssertTrue(paused.pause(at: epoch.addingTimeInterval(25)))
        try store.saveSession(paused)
        let restored = store.loadSession(at: epoch.addingTimeInterval(500))
        XCTAssertEqual(restored.state, .paused)
        XCTAssertEqual(restored.remaining(now: epoch.addingTimeInterval(500)), 75)
    }

    func testExpiredSessionIsCountedOnceAndInvalidOrCorruptSessionFallsBack() throws {
        let (store, defaults) = makeStore()
        var expired = FocusSession()
        XCTAssertTrue(expired.start(kind: .focus, duration: 10, at: epoch))
        try store.saveSession(expired)
        let first = store.loadSession(at: epoch.addingTimeInterval(11))
        let second = store.loadSession(at: epoch.addingTimeInterval(12))
        XCTAssertEqual(first.completedFocusCount, 1)
        XCTAssertEqual(second.completedFocusCount, 1)

        XCTAssertEqual(store.loadSession(at: epoch).completedFocusCount, 1)

        var running = FocusSession()
        XCTAssertTrue(running.start(kind: .focus, duration: 10, at: epoch))
        var invalidObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(running)) as? [String: Any])
        invalidObject["targetEnd"] = NSNull()
        let invalidData = try JSONSerialization.data(withJSONObject: invalidObject)
        defaults.set(invalidData, forKey: "focus.session")
        XCTAssertEqual(store.loadSession(at: epoch).state, .idle)

        try store.saveSession(running)
        let previousData = try XCTUnwrap(defaults.data(forKey: "focus.session"))
        XCTAssertThrowsError(try store.saveSession(try JSONDecoder().decode(FocusSession.self, from: invalidData)))
        XCTAssertEqual(defaults.data(forKey: "focus.session"), previousData)
        defaults.set(Data("{bad json".utf8), forKey: "focus.session")
        XCTAssertEqual(store.loadSession(at: epoch).state, .idle)
    }
}

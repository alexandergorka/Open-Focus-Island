import FocusCore
import XCTest
@testable import OpenFocusIsland

@MainActor
final class FocusControllerTests: XCTestCase {
    func testStartPauseAndResumeUsePersistedSessionAndClock() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_000))
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = FocusController(store: store, now: { clock.date })

        controller.start(kind: .focus, taskName: "Draft")
        XCTAssertEqual(controller.session.state, .running)
        XCTAssertEqual(controller.session.taskName, "Draft")
        let originalEnd = try XCTUnwrap(controller.session.targetEnd)
        XCTAssertEqual(originalEnd, clock.date.addingTimeInterval(1_500))

        clock.date = clock.date.addingTimeInterval(100)
        controller.pause()
        XCTAssertEqual(controller.session.state, .paused)
        XCTAssertEqual(controller.session.targetEnd, originalEnd)

        clock.date = clock.date.addingTimeInterval(500)
        controller.resume()
        XCTAssertEqual(controller.session.state, .running)
        XCTAssertEqual(controller.session.targetEnd, originalEnd.addingTimeInterval(500))
        XCTAssertEqual(controller.session.remaining(now: clock.date), 1_400)
    }

    func testFinishAndSkipBreakAreExplicitAndDoNotCountFocus() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 2_000))
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = FocusController(store: store, now: { clock.date })

        controller.start(kind: .focus)
        clock.date = clock.date.addingTimeInterval(10)
        controller.finish()
        XCTAssertEqual(controller.session.state, .completed)
        XCTAssertEqual(controller.session.completedFocusCount, 0)

        controller.skip()
        XCTAssertEqual(controller.session.kind, .shortBreak)
        XCTAssertEqual(controller.session.state, .running)
        XCTAssertEqual(controller.session.completedFocusCount, 0)
    }

    func testSettingsAndRunningSessionRestoreInFreshController() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 3_000))
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = FocusController(store: store, now: { clock.date })
        let settings = FocusSettings(focusDuration: 1_200, shortBreakDuration: 240, longBreakDuration: 720)

        XCTAssertTrue(first.saveSettings(settings))
        first.start(kind: .focus, taskName: "Read")
        clock.date = clock.date.addingTimeInterval(40)
        let restored = FocusController(store: store, now: { clock.date })

        XCTAssertEqual(restored.settings, settings)
        XCTAssertEqual(restored.session.state, .running)
        XCTAssertEqual(restored.session.taskName, "Read")
        XCTAssertEqual(restored.session.remaining(now: clock.date), 1_160)
    }

    func testTickReconcilesAndPersistsExpiryOnlyOnce() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 4_000))
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = FocusController(store: store, now: { clock.date })
        controller.start(kind: .focus)

        clock.date = clock.date.addingTimeInterval(1_500)
        controller.tick()
        XCTAssertEqual(controller.session.state, .completed)
        XCTAssertEqual(controller.session.completedFocusCount, 1)
        controller.tick()
        XCTAssertEqual(controller.session.completedFocusCount, 1)
        XCTAssertEqual(FocusStore(defaults: defaults).loadSession(at: clock.date), controller.session)
    }

    func testSettingsChangesDoNotChangeActiveSessionAndInvalidSaveKeepsValues() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 5_000))
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = FocusController(store: store, now: { clock.date })
        controller.start(kind: .focus)
        let originalEnd = try XCTUnwrap(controller.session.targetEnd)
        let updated = FocusSettings(focusDuration: 900, shortBreakDuration: 180, longBreakDuration: 600)

        XCTAssertTrue(controller.saveSettings(updated))
        XCTAssertEqual(controller.session.targetEnd, originalEnd)
        XCTAssertFalse(controller.saveSettings(FocusSettings(focusDuration: .nan)))
        XCTAssertEqual(controller.settings, updated)
        XCTAssertEqual(FocusStore(defaults: defaults).loadSettings(), updated)
        XCTAssertNotNil(controller.error)
    }

    private let suiteName = "FocusAppTests.\(UUID().uuidString)"

    private func makeStore() -> (FocusStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (FocusStore(defaults: defaults), defaults)
    }
}

@MainActor
private final class TestClock {
    var date: Date
    init(_ date: Date) { self.date = date }
}

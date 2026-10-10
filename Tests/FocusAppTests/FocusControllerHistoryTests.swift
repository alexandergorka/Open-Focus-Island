import FocusCore
import XCTest
@testable import OpenFocusIsland

@MainActor
final class FocusControllerHistoryTests: XCTestCase {
    func testNaturalExpiryRecordsFocusButManualFinishAndBreaksDoNot() throws {
        let clock = HistoryTestClock(Date(timeIntervalSince1970: 100_000))
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try store.saveSettings(FocusSettings(focusDuration: 40))
        let controller = FocusController(store: store, now: { clock.date })

        controller.start(kind: .focus, taskName: "Entwurf")
        let startedAt = controller.session.startedAt
        let id = controller.session.id
        clock.date = clock.date.addingTimeInterval(40)
        controller.tick()

        XCTAssertEqual(controller.history.count, 1)
        XCTAssertEqual(controller.history.first?.id, id)
        XCTAssertEqual(controller.history.first?.taskName, "Entwurf")
        XCTAssertEqual(controller.history.first?.startedAt, startedAt)
        XCTAssertEqual(controller.history.first?.plannedDuration, 40)

        controller.start(kind: .shortBreak)
        clock.date = clock.date.addingTimeInterval(300)
        controller.tick()
        XCTAssertEqual(controller.history.count, 1)

        controller.start(kind: .focus, taskName: "Manuell")
        clock.date = clock.date.addingTimeInterval(5)
        controller.finish()
        XCTAssertEqual(controller.history.count, 1)
    }

    func testExpiredFocusWhileAppWasQuitIsRecordedOnceAcrossRestarts() throws {
        let start = Date(timeIntervalSince1970: 110_000)
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var expiredSession = FocusSession()
        XCTAssertTrue(expiredSession.start(kind: .focus, duration: 25, taskName: "Lesen", at: start))
        try store.saveSession(expiredSession)

        let restored = FocusController(store: store, now: { start.addingTimeInterval(26) })

        XCTAssertTrue(restored.session.didFullyElapse)
        XCTAssertEqual(restored.history.count, 1)
        XCTAssertEqual(restored.history.first?.id, expiredSession.id)
        restored.tick()
        let restartedAgain = FocusController(store: store, now: { start.addingTimeInterval(27) })
        XCTAssertEqual(restartedAgain.history.count, 1)
        XCTAssertEqual(restartedAgain.history.first?.id, expiredSession.id)
    }

    func testActionAtExpiryRecordsOldFocusBeforeStartingNextSession() throws {
        let clock = HistoryTestClock(Date(timeIntervalSince1970: 120_000))
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try store.saveSettings(FocusSettings(focusDuration: 30))
        let controller = FocusController(store: store, now: { clock.date })
        controller.start(kind: .focus, taskName: "Alt")
        let completedID = controller.session.id

        clock.date = clock.date.addingTimeInterval(30)
        controller.start(kind: .focus, taskName: "Neu")

        XCTAssertEqual(controller.session.state, .running)
        XCTAssertEqual(controller.session.taskName, "Neu")
        XCTAssertEqual(controller.history.map(\.id), [completedID])
    }

    func testCorruptHistoryRemainsVisibleAndDoesNotBlockSessionActions() throws {
        let clock = HistoryTestClock(Date(timeIntervalSince1970: 130_000))
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let corruptData = Data("{bad history".utf8)
        defaults.set(corruptData, forKey: "focus.history")
        try store.saveSettings(FocusSettings(focusDuration: 30))
        let controller = FocusController(store: store, now: { clock.date })

        XCTAssertTrue(controller.history.isEmpty)
        XCTAssertNotNil(controller.error)
        controller.start(kind: .focus)
        clock.date = clock.date.addingTimeInterval(5)
        controller.pause()

        XCTAssertEqual(controller.session.state, .paused)
        XCTAssertNotNil(controller.error)
        XCTAssertEqual(defaults.data(forKey: "focus.history"), corruptData)
    }

    private let suiteName = "FocusAppHistoryTests.\(UUID().uuidString)"

    private func makeStore() -> (FocusStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (FocusStore(defaults: defaults), defaults)
    }
}

@MainActor
private final class HistoryTestClock {
    var date: Date
    init(_ date: Date) { self.date = date }
}

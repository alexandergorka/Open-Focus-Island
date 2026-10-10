import Foundation
import XCTest
@testable import FocusCore

final class FocusHistoryTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 10_000)
    private var suites: [(String, UserDefaults)] = []

    override func tearDown() {
        suites.forEach { $0.1.removePersistentDomain(forName: $0.0) }
        suites.removeAll()
        super.tearDown()
    }

    func testCompletedFocusSessionProducesValidatedHistoryEntry() throws {
        let session = completedFocus(at: epoch, taskName: "  Write code  ")
        let entry = try XCTUnwrap(FocusHistoryEntry(session: session))

        XCTAssertEqual(entry.id, session.id)
        XCTAssertEqual(entry.taskName, "Write code")
        XCTAssertEqual(entry.startedAt, epoch)
        XCTAssertEqual(entry.completedAt, epoch.addingTimeInterval(60))
        XCTAssertEqual(entry.plannedDuration, 60)
    }

    func testManualFinishAndCompletedBreakAreIgnored() throws {
        let (store, _) = makeStore()
        var paused = FocusSession()
        XCTAssertTrue(paused.start(kind: .focus, duration: 60, at: epoch))
        XCTAssertTrue(paused.pause(at: epoch.addingTimeInterval(10)))
        XCTAssertTrue(paused.finish(at: epoch.addingTimeInterval(60)))
        XCTAssertFalse(paused.didFullyElapse)
        try store.recordCompletedFocus(paused)

        let breakSession = completedSession(kind: .shortBreak, at: epoch.addingTimeInterval(100), duration: 30)
        XCTAssertTrue(breakSession.didFullyElapse)
        try store.recordCompletedFocus(breakSession)
        XCTAssertTrue(try store.loadHistory().isEmpty)
    }

    func testFullyElapsedFocusIsStoredOnceAcrossStoreInstances() throws {
        let (store, defaults) = makeStore()
        let session = completedFocus(at: epoch)
        try store.recordCompletedFocus(session)
        try FocusStore(defaults: defaults).recordCompletedFocus(session)

        let entries = try store.loadHistory()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.id, session.id)
    }

    func testHistoryIsNewestFirst() throws {
        let (store, _) = makeStore()
        let older = completedFocus(at: epoch)
        let newer = completedFocus(at: epoch.addingTimeInterval(200))
        try store.recordCompletedFocus(older)
        try store.recordCompletedFocus(newer)

        XCTAssertEqual(try store.loadHistory().map(\.id), [newer.id, older.id])
    }

    func testMissingHistoryReturnsEmptyArray() throws {
        let (store, _) = makeStore()
        XCTAssertTrue(try store.loadHistory().isEmpty)
    }

    func testCorruptHistoryThrowsAndRejectedAppendPreservesRawData() throws {
        let (store, defaults) = makeStore()
        let raw = Data("{broken".utf8)
        defaults.set(raw, forKey: "focus.history")

        XCTAssertThrowsError(try store.loadHistory())
        XCTAssertThrowsError(try store.recordCompletedFocus(completedFocus(at: epoch)))
        XCTAssertEqual(defaults.data(forKey: "focus.history"), raw)
    }

    func testWrongTypeHistoryThrowsAndRejectedAppendPreservesValue() throws {
        let (store, defaults) = makeStore()
        defaults.set("unexpected value", forKey: "focus.history")

        XCTAssertThrowsError(try store.loadHistory())
        XCTAssertThrowsError(try store.recordCompletedFocus(completedFocus(at: epoch)))
        XCTAssertEqual(defaults.string(forKey: "focus.history"), "unexpected value")
    }

    func testInvalidStoredEntryThrowsAndRejectedAppendPreservesRawData() throws {
        let (store, defaults) = makeStore()
        let entry = try XCTUnwrap(FocusHistoryEntry(session: completedFocus(at: epoch, taskName: "Task")))
        let valid = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode([entry])) as? [[String: Any]])[0]

        for mutation in 0..<3 {
            var invalid = valid
            switch mutation {
            case 0: invalid["plannedDuration"] = 0
            case 1: invalid["completedAt"] = invalid["startedAt"]
            default: invalid["taskName"] = "  Task  "
            }
            let raw = try JSONSerialization.data(withJSONObject: [invalid])
            defaults.set(raw, forKey: "focus.history")

            XCTAssertThrowsError(try store.loadHistory())
            XCTAssertThrowsError(try store.recordCompletedFocus(completedFocus(at: epoch.addingTimeInterval(100))))
            XCTAssertEqual(defaults.data(forKey: "focus.history"), raw)
        }
    }

    private func makeStore() -> (FocusStore, UserDefaults) {
        let name = "FocusHistoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        suites.append((name, defaults))
        return (FocusStore(defaults: defaults), defaults)
    }

    private func completedFocus(at date: Date, taskName: String? = nil) -> FocusSession {
        completedSession(kind: .focus, at: date, duration: 60, taskName: taskName)
    }

    private func completedSession(kind: FocusSession.Kind, at date: Date, duration: TimeInterval, taskName: String? = nil) -> FocusSession {
        var session = FocusSession()
        XCTAssertTrue(session.start(kind: kind, duration: duration, taskName: taskName, at: date))
        XCTAssertTrue(session.reconcile(at: date.addingTimeInterval(duration)))
        return session
    }
}

import XCTest
@testable import FocusCore

final class FocusSessionValidationTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_000)

    func testIdleAndOrdinaryLifecycleSnapshotsAreValid() throws {
        XCTAssertTrue(FocusSession().isValid)

        var running = FocusSession()
        XCTAssertTrue(running.start(kind: .focus, duration: 60, taskName: "Task", at: epoch))
        XCTAssertTrue(running.isValid)

        XCTAssertTrue(running.pause(at: epoch.addingTimeInterval(10)))
        XCTAssertTrue(running.isValid)
        XCTAssertTrue(running.finish(at: epoch.addingTimeInterval(100)))
        XCTAssertTrue(running.isValid)

        var completed = FocusSession()
        XCTAssertTrue(completed.start(kind: .shortBreak, duration: 30, at: epoch))
        XCTAssertTrue(completed.reconcile(at: epoch.addingTimeInterval(30)))
        XCTAssertTrue(completed.isValid)
    }

    func testMalformedEncodedSessionSnapshotsAreRejected() throws {
        var running = FocusSession()
        XCTAssertTrue(running.start(kind: .focus, duration: 60, at: epoch))

        let mutations: [(inout [String: Any]) -> Void] = [
            { object in object["state"] = "idle"; object["startedAt"] = 1.0 },
            { object in object["targetEnd"] = NSNull() },
            { object in object["plannedDuration"] = 86_401.0 },
            { object in object["completedAt"] = 1_010.0 },
            { object in object["completedFocusCount"] = -1 },
            { object in object["completedFocusCount"] = Int.max },
            { object in object["longBreakStartedAtCount"] = 1 }
        ]

        for mutate in mutations {
            XCTAssertFalse(try decode(running, mutate: mutate).isValid)
        }

        XCTAssertTrue(running.pause(at: epoch.addingTimeInterval(10)))
        XCTAssertFalse(try decode(running) { $0["pausedAt"] = $0["targetEnd"] }.isValid)

        XCTAssertTrue(running.finish(at: epoch.addingTimeInterval(20)))
        XCTAssertFalse(try decode(running) { $0["completedAt"] = NSNull() }.isValid)
    }

    func testStartRejectsInvalidDurationAndDateWithoutChangingIdleSession() {
        for duration in [-1, 0, .nan, .infinity, 86_401] {
            var session = FocusSession()
            XCTAssertFalse(session.start(kind: .focus, duration: duration, at: epoch))
            XCTAssertTrue(session.isValid)
        }

        var session = FocusSession()
        XCTAssertFalse(session.start(kind: .focus, duration: 60, at: Date(timeIntervalSince1970: .infinity)))
        XCTAssertTrue(session.isValid)

        XCTAssertTrue(session.start(kind: .focus, duration: 86_400, at: epoch))
        XCTAssertTrue(session.isValid)
    }

    func testReconcileAtMaximumDecodedCountDoesNotOverflow() throws {
        var running = FocusSession()
        XCTAssertTrue(running.start(kind: .focus, duration: 10, at: epoch))
        var maximum = try decode(running) { $0["completedFocusCount"] = Int.max }
        XCTAssertFalse(maximum.isValid)
        XCTAssertTrue(maximum.reconcile(at: epoch.addingTimeInterval(10)))
        XCTAssertEqual(maximum.completedFocusCount, Int.max)
    }

    func testPauseRejectsBackwardAndNonFiniteTimestampsWithoutMutation() {
        var session = FocusSession()
        XCTAssertTrue(session.start(kind: .focus, duration: 60, at: epoch))

        for date in [epoch.addingTimeInterval(-1), Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: .infinity)] {
            let before = session
            XCTAssertFalse(session.pause(at: date))
            XCTAssertEqual(session, before)
            XCTAssertTrue(session.isValid)
        }
    }

    func testResumeRejectsBackwardAndNonFiniteTimestampsWithoutMutation() {
        var session = FocusSession()
        XCTAssertTrue(session.start(kind: .focus, duration: 60, at: epoch))
        XCTAssertTrue(session.pause(at: epoch.addingTimeInterval(10)))

        for date in [epoch.addingTimeInterval(9), Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: .infinity)] {
            let before = session
            XCTAssertFalse(session.resume(at: date))
            XCTAssertEqual(session, before)
            XCTAssertTrue(session.isValid)
        }
    }

    func testFinishRejectsBackwardAndNonFiniteTimestampsWithoutMutation() {
        var session = FocusSession()
        XCTAssertTrue(session.start(kind: .focus, duration: 60, at: epoch))

        for date in [epoch.addingTimeInterval(-1), Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: .infinity)] {
            let before = session
            XCTAssertFalse(session.finish(at: date))
            XCTAssertEqual(session, before)
            XCTAssertTrue(session.isValid)
        }

        XCTAssertTrue(session.pause(at: epoch.addingTimeInterval(10)))
        let before = session
        XCTAssertFalse(session.finish(at: epoch.addingTimeInterval(9)))
        XCTAssertEqual(session, before)
        XCTAssertTrue(session.isValid)
    }

    func testSkipRejectsBackwardAndNonFiniteTimestampsWithoutMutation() {
        var session = FocusSession()
        XCTAssertTrue(session.start(kind: .focus, duration: 60, at: epoch))

        for date in [epoch.addingTimeInterval(-1), Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: .infinity)] {
            let before = session
            XCTAssertFalse(session.skipToBreak(shortDuration: 5, longDuration: 15, at: date))
            XCTAssertEqual(session, before)
            XCTAssertTrue(session.isValid)
        }

        XCTAssertTrue(session.pause(at: epoch.addingTimeInterval(10)))
        let before = session
        XCTAssertFalse(session.skipToBreak(shortDuration: 5, longDuration: 15, at: epoch.addingTimeInterval(9)))
        XCTAssertEqual(session, before)
        XCTAssertTrue(session.isValid)
    }

    func testReconcileIgnoresNonFiniteTimestampWithoutMutation() {
        var session = FocusSession()
        XCTAssertTrue(session.start(kind: .focus, duration: 10, at: epoch))
        let before = session
        XCTAssertFalse(session.reconcile(at: Date(timeIntervalSince1970: .infinity)))
        XCTAssertEqual(session, before)
        XCTAssertTrue(session.isValid)
    }

    private func decode(_ session: FocusSession, mutate: ((inout [String: Any]) -> Void)? = nil) throws -> FocusSession {
        let data = try JSONEncoder().encode(session)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        mutate?(&object)
        return try JSONDecoder().decode(FocusSession.self, from: JSONSerialization.data(withJSONObject: object))
    }
}

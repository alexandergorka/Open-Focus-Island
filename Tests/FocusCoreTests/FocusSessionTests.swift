import XCTest
@testable import FocusCore

final class FocusSessionTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_000)

    func testPauseResumePreservesRemainingTimeAndExcludesPause() {
        var session = FocusSession()
        XCTAssertTrue(session.start(kind: .focus, duration: 100, taskName: "  Write tests  ", at: epoch))
        XCTAssertTrue(session.pause(at: epoch.addingTimeInterval(30)))
        XCTAssertEqual(session.remaining(now: epoch.addingTimeInterval(90)), 70)
        XCTAssertTrue(session.resume(at: epoch.addingTimeInterval(90)))
        XCTAssertEqual(session.targetEnd, epoch.addingTimeInterval(160))
        XCTAssertEqual(session.taskName, "Write tests")
    }

    func testRunningRemainingClampsAtExpiry() {
        var session = FocusSession()
        XCTAssertTrue(session.start(kind: .focus, duration: 10, at: epoch))
        XCTAssertEqual(session.remaining(now: epoch), 10)
        XCTAssertEqual(session.remaining(now: epoch.addingTimeInterval(10)), 0)
        XCTAssertEqual(session.remaining(now: epoch.addingTimeInterval(11)), 0)
    }

    func testFinishAndSkipDoNotCountFocusButExpiryCountsExactlyOnce() {
        var finished = FocusSession()
        XCTAssertTrue(finished.start(kind: .focus, duration: 10, at: epoch))
        XCTAssertTrue(finished.finish(at: epoch.addingTimeInterval(2)))
        XCTAssertEqual(finished.completedFocusCount, 0)

        var finishedLate = FocusSession()
        XCTAssertTrue(finishedLate.start(kind: .focus, duration: 10, at: epoch))
        XCTAssertFalse(finishedLate.finish(at: epoch.addingTimeInterval(10)))
        XCTAssertEqual(finishedLate.completedFocusCount, 1)

        var skipped = FocusSession()
        XCTAssertTrue(skipped.start(kind: .focus, duration: 10, at: epoch))
        XCTAssertTrue(skipped.skipToBreak(shortDuration: 5, longDuration: 15, at: epoch.addingTimeInterval(2)))
        XCTAssertEqual(skipped.kind, .shortBreak)
        XCTAssertEqual(skipped.completedFocusCount, 0)

        var expired = FocusSession()
        XCTAssertTrue(expired.start(kind: .focus, duration: 10, at: epoch))
        XCTAssertTrue(expired.reconcile(at: epoch.addingTimeInterval(10)))
        XCTAssertFalse(expired.reconcile(at: epoch.addingTimeInterval(20)))
        XCTAssertEqual(expired.completedFocusCount, 1)
        XCTAssertEqual(expired.recommendedBreak, .shortBreak)
    }

    func testPauseAfterExpiryReconcilesInsteadOfPausing() {
        var session = FocusSession()
        XCTAssertTrue(session.start(kind: .focus, duration: 10, at: epoch))
        XCTAssertFalse(session.pause(at: epoch.addingTimeInterval(10)))
        XCTAssertEqual(session.state, .completed)
        XCTAssertEqual(session.completedFocusCount, 1)
    }

    func testFourthFocusRecommendsLongBreakUntilItStarts() {
        var session = FocusSession()
        for _ in 0..<4 {
            XCTAssertTrue(session.start(kind: .focus, duration: 1, at: epoch))
            XCTAssertTrue(session.reconcile(at: epoch.addingTimeInterval(1)))
        }
        XCTAssertEqual(session.recommendedBreak, .longBreak)
        XCTAssertTrue(session.skipToBreak(shortDuration: 5, longDuration: 15, at: epoch.addingTimeInterval(10)))
        XCTAssertEqual(session.kind, .longBreak)
        XCTAssertEqual(session.recommendedBreak, .shortBreak)
    }

    func testInvalidDurationAndStartingWhileRunningAreNoOps() {
        var session = FocusSession()
        for duration in [-1, 0, .nan, .infinity] {
            XCTAssertFalse(session.start(kind: .focus, duration: duration, at: epoch))
            XCTAssertEqual(session.state, .idle)
        }
        XCTAssertTrue(session.start(kind: .focus, duration: 10, at: epoch))
        let original = session
        XCTAssertFalse(session.start(kind: .shortBreak, duration: 5, at: epoch))
        XCTAssertEqual(session, original)
    }

    func testPausedFinishAndSkipAreExplicitWithoutCountingFocus() {
        var finished = FocusSession()
        XCTAssertTrue(finished.start(kind: .focus, duration: 10, at: epoch))
        XCTAssertTrue(finished.pause(at: epoch.addingTimeInterval(2)))
        XCTAssertTrue(finished.finish(at: epoch.addingTimeInterval(100)))
        XCTAssertEqual(finished.completedFocusCount, 0)

        var skipped = FocusSession()
        XCTAssertTrue(skipped.start(kind: .focus, duration: 10, at: epoch))
        XCTAssertTrue(skipped.pause(at: epoch.addingTimeInterval(2)))
        XCTAssertTrue(skipped.skipToBreak(shortDuration: 5, longDuration: 15, at: epoch.addingTimeInterval(100)))
        XCTAssertEqual(skipped.kind, .shortBreak)
        XCTAssertEqual(skipped.completedFocusCount, 0)
    }

    func testExpiringBreaksDoNotIncrementFocusCount() {
        for kind in [FocusSession.Kind.shortBreak, .longBreak] {
            var session = FocusSession()
            XCTAssertTrue(session.start(kind: kind, duration: 5, at: epoch))
            XCTAssertTrue(session.reconcile(at: epoch.addingTimeInterval(5)))
            XCTAssertEqual(session.completedFocusCount, 0)
        }
    }

    func testFullyElapsedCompletionDiffersFromPausedManualFinishAtTargetTime() {
        var naturallyCompleted = FocusSession()
        XCTAssertTrue(naturallyCompleted.start(kind: .focus, duration: 10, at: epoch))
        XCTAssertTrue(naturallyCompleted.reconcile(at: epoch.addingTimeInterval(10)))
        XCTAssertTrue(naturallyCompleted.didFullyElapse)

        var manuallyFinished = FocusSession()
        XCTAssertTrue(manuallyFinished.start(kind: .focus, duration: 10, at: epoch))
        XCTAssertTrue(manuallyFinished.pause(at: epoch.addingTimeInterval(2)))
        XCTAssertTrue(manuallyFinished.finish(at: epoch.addingTimeInterval(10)))
        XCTAssertFalse(manuallyFinished.didFullyElapse)
    }

    func testInvalidSkipDurationDoesNotMutatePausedFocus() {
        var session = FocusSession()
        XCTAssertTrue(session.start(kind: .focus, duration: 10, at: epoch))
        XCTAssertTrue(session.pause(at: epoch.addingTimeInterval(2)))
        let original = session
        XCTAssertFalse(session.skipToBreak(shortDuration: .nan, longDuration: .infinity, at: epoch.addingTimeInterval(3)))
        XCTAssertEqual(session, original)
    }
}

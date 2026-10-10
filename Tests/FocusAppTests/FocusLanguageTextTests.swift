import FocusCore
import XCTest
@testable import OpenFocusIsland

final class FocusLanguageTextTests: XCTestCase {
    func testStatusTextsInBothLanguages() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        func session(_ kind: FocusSession.Kind, _ duration: TimeInterval, task: String? = nil, pauseAfter: TimeInterval? = nil, complete: Bool = false) -> FocusSession {
            var s = FocusSession()
            XCTAssertTrue(s.start(kind: kind, duration: duration, taskName: task, at: t0))
            if let pauseAfter { XCTAssertTrue(s.pause(at: t0.addingTimeInterval(pauseAfter))) }
            if complete { XCTAssertTrue(s.reconcile(at: t0.addingTimeInterval(duration))) }
            return s
        }
        let idle = FocusSession()
        let focus = session(.focus, 1500)
        let focusTask = session(.focus, 1500, task: "Write")
        let shortPaused = session(.shortBreak, 300, pauseAfter: 10)
        let longPausedTask = session(.longBreak, 900, task: "Read", pauseAfter: 10)
        let completed = session(.focus, 1500, complete: true)
        let early = t0.addingTimeInterval(10) // 1490 s left
        let lastMinute = t0.addingTimeInterval(1440) // exactly 60 s left
        let end = t0.addingTimeInterval(1500)

        // (session, now, english description, english notch, german description, german notch)
        let cases: [(FocusSession, Date, String, String, String, String)] = [
            (idle, t0, "Ready for a session", "Ready for a session", "Bereit für eine Sitzung", "Bereit für eine Sitzung"),
            (focus, early, "Focus running", "Focus running", "Fokus läuft", "Fokus läuft"),
            (focusTask, early, "Focus · Write", "Focus running", "Fokus · Write", "Fokus läuft"),
            (focus, lastMinute, "Focus running", "Focus almost done", "Fokus läuft", "Fokus bald fertig"),
            (shortPaused, end, "Short break paused", "Short break paused", "Kurze Pause pausiert", "Kurze Pause pausiert"),
            (longPausedTask, end, "Long break paused · Read", "Long break paused", "Lange Pause pausiert · Read", "Lange Pause pausiert"),
            (completed, end, "Focus complete", "Focus complete", "Fokus abgeschlossen", "Fokus abgeschlossen"),
        ]
        for (s, now, enDescription, enNotch, deDescription, deNotch) in cases {
            XCTAssertEqual(sessionDescription(s, language: .english), enDescription)
            XCTAssertEqual(notchStatus(s, now: now, language: .english), enNotch)
            XCTAssertEqual(sessionDescription(s, language: .german), deDescription)
            XCTAssertEqual(notchStatus(s, now: now, language: .german), deNotch)
        }
    }

    func testHistoryDetailUsesLanguageLocale() throws {
        var components = DateComponents(year: 2026, month: 10, day: 15, hour: 12)
        components.calendar = Calendar(identifier: .gregorian)
        let start = try XCTUnwrap(components.date)
        var session = FocusSession()
        XCTAssertTrue(session.start(kind: .focus, duration: 1500, at: start))
        XCTAssertTrue(session.reconcile(at: start.addingTimeInterval(1500)))
        let entry = try XCTUnwrap(FocusHistoryEntry(session: session))

        let english = historyDetail(entry, language: .english)
        XCTAssertTrue(english.contains("Oct"), english)
        XCTAssertTrue(english.hasSuffix("25 min"), english)
        let german = historyDetail(entry, language: .german)
        XCTAssertTrue(german.contains("Okt"), german)
        XCTAssertTrue(german.hasSuffix("25 Min."), german)
    }
}

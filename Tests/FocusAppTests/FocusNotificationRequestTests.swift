import XCTest
import UserNotifications
@testable import OpenFocusIsland

@MainActor
final class FocusNotificationRequestTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    func testRequestCarriesContentIdentifierAndSingleDefaultSoundTrigger() throws {
        let request = try SystemFocusNotificationClient.makeRequest(
            identifier: "focus-session",
            title: "Focus done",
            body: "Time for a break",
            at: now.addingTimeInterval(25),
            now: now
        )

        XCTAssertEqual(request.identifier, "focus-session")
        XCTAssertEqual(request.content.title, "Focus done")
        XCTAssertEqual(request.content.body, "Time for a break")
        XCTAssertEqual(request.content.sound, .default)
        let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger.timeInterval, 25, accuracy: 0.001)
        XCTAssertFalse(trigger.repeats)
    }

    func testPastTargetUsesMinimumPositiveOneSecondDelay() throws {
        let request = try SystemFocusNotificationClient.makeRequest(
            identifier: "expired",
            title: "Done",
            body: "Done",
            at: now.addingTimeInterval(-5),
            now: now
        )

        let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger.timeInterval, 1, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(trigger.timeInterval, 1)
    }

    func testNonFiniteDatesFailWithReadableError() {
        for (date, currentTime) in [
            (Date(timeIntervalSince1970: .nan), now),
            (now, Date(timeIntervalSince1970: .infinity)),
            (Date(timeIntervalSince1970: .greatestFiniteMagnitude), Date(timeIntervalSince1970: -.greatestFiniteMagnitude)),
        ] {
            XCTAssertThrowsError(try SystemFocusNotificationClient.makeRequest(
                identifier: "invalid",
                title: "Done",
                body: "Done",
                at: date,
                now: currentTime
            )) { error in
                XCTAssertFalse(error.localizedDescription.isEmpty)
            }
        }
    }
}

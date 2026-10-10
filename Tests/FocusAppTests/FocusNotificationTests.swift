import FocusCore
import XCTest
@testable import OpenFocusIsland

@MainActor
final class FocusNotificationTests: XCTestCase {
    func testExplicitEnableSchedulesOnceThenLifecycleCancelsAndReschedules() throws {
        let clock = NotificationTestClock(Date(timeIntervalSince1970: 10_000))
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = FakeNotificationClient()
        let controller = FocusController(store: store, now: { clock.date }, notifications: client)

        controller.setNotificationsEnabled(true)
        XCTAssertTrue(controller.settings.notificationsEnabled)
        XCTAssertEqual(client.authorizationRequests, 1)
        XCTAssertTrue(controller.saveSettings(FocusSettings(
            focusDuration: 1_500,
            shortBreakDuration: 300,
            longBreakDuration: 900,
            notificationsEnabled: false
        )))
        XCTAssertTrue(controller.settings.notificationsEnabled)
        controller.start(kind: .focus, taskName: "Read")
        let focusID = controller.session.id.uuidString
        XCTAssertEqual(client.scheduled.map(\.identifier), [focusID])
        XCTAssertEqual(client.scheduled.first?.date, clock.date.addingTimeInterval(1_500))

        clock.date = clock.date.addingTimeInterval(1)
        controller.tick()
        XCTAssertEqual(client.scheduled.count, 1)

        controller.pause()
        XCTAssertEqual(client.cancelled, [focusID])
        clock.date = clock.date.addingTimeInterval(30)
        controller.resume()
        XCTAssertEqual(client.scheduled.map(\.identifier), [focusID, focusID])

        controller.skip()
        let breakID = controller.session.id.uuidString
        XCTAssertNotEqual(focusID, breakID)
        XCTAssertEqual(client.scheduled.map(\.identifier), [focusID, focusID, breakID])
        XCTAssertTrue(client.cancelled.contains(focusID))
        controller.finish()
        XCTAssertTrue(client.cancelled.contains(breakID))
    }

    func testDeniedPermissionKeepsPreferenceOffAndShowsError() throws {
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = FakeNotificationClient()
        client.requestResult = (false, "Berechtigung verweigert")
        let controller = FocusController(store: store, notifications: client)

        controller.setNotificationsEnabled(true)

        XCTAssertFalse(controller.settings.notificationsEnabled)
        XCTAssertFalse(store.loadSettings().notificationsEnabled)
        XCTAssertTrue(controller.error?.contains("Berechtigung verweigert") == true)
        XCTAssertTrue(client.scheduled.isEmpty)
        XCTAssertEqual(client.authorizationRequests, 1)
    }

    func testLaunchReconcilesSavedPreferenceWithoutPrompting() throws {
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try store.saveSettings(FocusSettings(notificationsEnabled: true))
        var session = FocusSession()
        let now = Date(timeIntervalSince1970: 20_000)
        XCTAssertTrue(session.start(kind: .focus, duration: 600, at: now))
        try store.saveSession(session)
        let client = FakeNotificationClient()
        client.authorization = .authorized
        let controller = FocusController(store: store, now: { now }, notifications: client)

        controller.reconcileNotificationAuthorization()

        XCTAssertTrue(controller.settings.notificationsEnabled)
        XCTAssertEqual(client.authorizationQueries, 1)
        XCTAssertEqual(client.authorizationRequests, 0)
        XCTAssertEqual(client.scheduled.map(\.identifier), [session.id.uuidString])
    }

    func testUndeterminedSavedPreferenceIsDisabledWithoutLaunchPrompt() throws {
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try store.saveSettings(FocusSettings(notificationsEnabled: true))
        let client = FakeNotificationClient()
        client.authorization = .notDetermined
        let controller = FocusController(store: store, notifications: client)

        controller.reconcileNotificationAuthorization()

        XCTAssertFalse(controller.settings.notificationsEnabled)
        XCTAssertFalse(store.loadSettings().notificationsEnabled)
        XCTAssertEqual(client.authorizationRequests, 0)
        XCTAssertNotNil(controller.error)
    }

    func testLaunchCancelsNotificationForRestoredPausedSession() throws {
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try store.saveSettings(FocusSettings(notificationsEnabled: true))
        let now = Date(timeIntervalSince1970: 25_000)
        var session = FocusSession()
        XCTAssertTrue(session.start(kind: .focus, duration: 600, at: now))
        XCTAssertTrue(session.pause(at: now.addingTimeInterval(30)))
        try store.saveSession(session)
        let client = FakeNotificationClient()
        client.authorization = .authorized
        let controller = FocusController(store: store, now: { now.addingTimeInterval(60) }, notifications: client)

        controller.reconcileNotificationAuthorization()

        XCTAssertEqual(client.cancelled, [session.id.uuidString])
        XCTAssertTrue(client.scheduled.isEmpty)
    }

    func testNaturalExpiryLeavesScheduledAlertForTheOperatingSystem() throws {
        let clock = NotificationTestClock(Date(timeIntervalSince1970: 40_000))
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = FakeNotificationClient()
        let controller = FocusController(store: store, now: { clock.date }, notifications: client)
        controller.setNotificationsEnabled(true)
        controller.start(kind: .focus)
        let identifier = controller.session.id.uuidString

        clock.date = clock.date.addingTimeInterval(1_500)
        controller.tick()

        XCTAssertTrue(controller.session.didFullyElapse)
        XCTAssertFalse(client.cancelled.contains(identifier))
        XCTAssertEqual(client.scheduled.map(\.identifier), [identifier])
    }

    func testSkippingAtNaturalExpiryKeepsCompletedFocusAlertAndSchedulesBreak() throws {
        let clock = NotificationTestClock(Date(timeIntervalSince1970: 50_000))
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = FakeNotificationClient()
        let controller = FocusController(store: store, now: { clock.date }, notifications: client)
        controller.setNotificationsEnabled(true)
        controller.start(kind: .focus)
        let focusID = controller.session.id.uuidString

        clock.date = clock.date.addingTimeInterval(1_500)
        controller.skip()

        XCTAssertFalse(client.cancelled.contains(focusID))
        XCTAssertEqual(client.scheduled.map(\.identifier).count, 2)
        XCTAssertEqual(client.scheduled.last?.identifier, controller.session.id.uuidString)
    }

    func testRestoredNaturalCompletionKeepsItsPendingAlert() throws {
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try store.saveSettings(FocusSettings(notificationsEnabled: true))
        let start = Date(timeIntervalSince1970: 60_000)
        var session = FocusSession()
        XCTAssertTrue(session.start(kind: .focus, duration: 10, at: start))
        XCTAssertTrue(session.reconcile(at: start.addingTimeInterval(10)))
        try store.saveSession(session)
        let client = FakeNotificationClient()
        client.authorization = .authorized
        let controller = FocusController(store: store, now: { start.addingTimeInterval(11) }, notifications: client)

        controller.reconcileNotificationAuthorization()

        XCTAssertTrue(controller.session.didFullyElapse)
        XCTAssertFalse(client.cancelled.contains(session.id.uuidString))
    }

    func testLateScheduleFailureAfterPauseDoesNotReplaceCurrentErrorState() throws {
        let clock = NotificationTestClock(Date(timeIntervalSince1970: 70_000))
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = FakeNotificationClient()
        client.holdScheduleCompletion = true
        let controller = FocusController(store: store, now: { clock.date }, notifications: client)
        controller.setNotificationsEnabled(true)
        controller.start(kind: .focus)
        let identifier = controller.session.id.uuidString

        controller.pause()
        client.failPendingSchedule("late OS failure")

        XCTAssertTrue(client.cancelled.contains(identifier))
        XCTAssertNil(controller.error)
    }

    func testPermissionResultAfterOptOutCannotTurnNotificationsBackOn() throws {
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = FakeNotificationClient()
        client.holdAuthorizationRequest = true
        let controller = FocusController(store: store, notifications: client)

        controller.setNotificationsEnabled(true)
        controller.setNotificationsEnabled(false)
        client.completeAuthorizationRequest(granted: true)

        XCTAssertFalse(controller.settings.notificationsEnabled)
        XCTAssertFalse(store.loadSettings().notificationsEnabled)
        XCTAssertTrue(client.scheduled.isEmpty)
    }

    func testSchedulingFailureIsVisibleToTheUser() throws {
        let clock = NotificationTestClock(Date(timeIntervalSince1970: 30_000))
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = FakeNotificationClient()
        client.scheduleFailure = "OS rejected request"
        let controller = FocusController(store: store, now: { clock.date }, notifications: client)

        controller.setNotificationsEnabled(true)
        controller.start(kind: .focus)

        XCTAssertTrue(controller.error?.contains("OS rejected request") == true)
        XCTAssertEqual(client.scheduled.count, 1)
    }

    func testNotificationTextFollowsLanguage() throws {
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = FakeNotificationClient()
        let controller = FocusController(store: store, notifications: client)
        controller.setNotificationsEnabled(true)

        controller.start(kind: .focus)
        XCTAssertEqual(client.scheduled.last?.title, "Focus complete")
        XCTAssertEqual(client.scheduled.last?.body, "Your session has ended.")
        controller.finish()
        controller.start(kind: .shortBreak)
        XCTAssertEqual(client.scheduled.last?.title, "Break complete")
        controller.finish()

        controller.setLanguage(.german)
        controller.start(kind: .focus)
        XCTAssertEqual(client.scheduled.last?.title, "Fokus abgeschlossen")
        XCTAssertEqual(client.scheduled.last?.body, "Deine Sitzung ist beendet.")
        controller.finish()
        controller.start(kind: .shortBreak, taskName: "Read")
        XCTAssertEqual(client.scheduled.last?.title, "Pause abgeschlossen")
        XCTAssertEqual(client.scheduled.last?.body, "Read")
    }

    func testLanguageChangeReschedulesRunningNotification() throws {
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = FakeNotificationClient()
        let controller = FocusController(store: store, notifications: client)
        controller.setNotificationsEnabled(true)
        controller.start(kind: .focus)
        let identifier = controller.session.id.uuidString
        XCTAssertEqual(client.scheduled.last?.title, "Focus complete")
        let date = client.scheduled.last?.date

        controller.setLanguage(.german)
        XCTAssertEqual(client.scheduled.count, 2)
        XCTAssertEqual(client.cancelled, [identifier])
        XCTAssertEqual(client.scheduled.last?.identifier, identifier)
        XCTAssertEqual(client.scheduled.last?.date, date)
        XCTAssertEqual(client.scheduled.last?.title, "Fokus abgeschlossen")
        XCTAssertEqual(client.scheduled.last?.body, "Deine Sitzung ist beendet.")

        controller.setLanguage(.german)
        XCTAssertEqual(client.scheduled.count, 2)

        controller.pause()
        controller.setLanguage(.english)
        XCTAssertEqual(client.scheduled.count, 2)
    }

    private let suiteName = "FocusNotificationTests.\(UUID().uuidString)"

    private func makeStore() -> (FocusStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (FocusStore(defaults: defaults), defaults)
    }
}

@MainActor
private final class NotificationTestClock {
    var date: Date
    init(_ date: Date) { self.date = date }
}

@MainActor
private final class FakeNotificationClient: FocusNotificationClient {
    struct Scheduled {
        let identifier: String
        let title: String
        let body: String
        let date: Date
    }

    var authorization = FocusNotificationAuthorization.notDetermined
    var requestResult: (Bool, String?) = (true, nil)
    var authorizationQueries = 0
    var authorizationRequests = 0
    var holdAuthorizationRequest = false
    var pendingAuthorizationRequest: (@MainActor @Sendable (Bool, String?) -> Void)?
    var scheduleFailure: String?
    var holdScheduleCompletion = false
    var pendingScheduleCompletions: [@MainActor @Sendable (String?) -> Void] = []
    var scheduled: [Scheduled] = []
    var cancelled: [String] = []

    func authorizationStatus(_ completion: @escaping @MainActor @Sendable (FocusNotificationAuthorization) -> Void) {
        authorizationQueries += 1
        completion(authorization)
    }

    func requestAuthorization(_ completion: @escaping @MainActor @Sendable (Bool, String?) -> Void) {
        authorizationRequests += 1
        if holdAuthorizationRequest { pendingAuthorizationRequest = completion }
        else { completion(requestResult.0, requestResult.1) }
    }

    func schedule(identifier: String, title: String, body: String, at date: Date, completion: @escaping @MainActor @Sendable (String?) -> Void) {
        scheduled.append(Scheduled(identifier: identifier, title: title, body: body, date: date))
        if holdScheduleCompletion { pendingScheduleCompletions.append(completion) }
        else { completion(scheduleFailure) }
    }

    func cancel(identifier: String) { cancelled.append(identifier) }

    func completeAuthorizationRequest(granted: Bool) {
        pendingAuthorizationRequest?(granted, requestResult.1)
        pendingAuthorizationRequest = nil
    }

    func failPendingSchedule(_ message: String) {
        pendingScheduleCompletions.removeFirst()(message)
    }
}

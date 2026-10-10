import FocusCore
import XCTest
@testable import OpenFocusIsland

@MainActor
final class FocusControllerSoundPolicyTests: XCTestCase {
    func testOnlyCompletionThroughFiveSecondsAfterTargetEndPlaysOnce() throws {
        let (controller, clock, player, defaults) = try makeController()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        controller.start(kind: .focus)
        let end = try XCTUnwrap(controller.session.targetEnd)
        clock.date = end
        controller.tick()
        XCTAssertEqual(player.events, [.focusCompleted])
        controller.tick()
        XCTAssertEqual(player.events, [.focusCompleted])

        controller.start(kind: .shortBreak)
        clock.date = try XCTUnwrap(controller.session.targetEnd).addingTimeInterval(5)
        controller.tick()
        XCTAssertEqual(player.events, [.focusCompleted, .breakCompleted])

        controller.start(kind: .focus)
        clock.date = try XCTUnwrap(controller.session.targetEnd).addingTimeInterval(5.001)
        controller.tick()
        XCTAssertEqual(player.events, [.focusCompleted, .breakCompleted])
    }

    func testTwoLiveSessionsPlayOnceEachAndPauseResumeMovesDeadline() throws {
        let (controller, clock, player, defaults) = try makeController()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        controller.start(kind: .focus)
        clock.date = try XCTUnwrap(controller.session.targetEnd)
        controller.tick()
        controller.start(kind: .shortBreak)
        clock.date = try XCTUnwrap(controller.session.targetEnd)
        controller.tick()
        XCTAssertEqual(player.events, [.focusCompleted, .breakCompleted])

        controller.start(kind: .focus)
        clock.date = clock.date.addingTimeInterval(0.5)
        controller.pause()
        let oldEnd = try XCTUnwrap(controller.session.targetEnd)
        let pausedAt = try XCTUnwrap(controller.session.pausedAt)
        clock.date = oldEnd.addingTimeInterval(1)
        controller.tick()
        XCTAssertEqual(controller.session.state, .paused)
        XCTAssertEqual(player.events.count, 2)
        controller.resume()
        let shiftedEnd = try XCTUnwrap(controller.session.targetEnd)
        XCTAssertEqual(shiftedEnd.timeIntervalSince(oldEnd), clock.date.timeIntervalSince(pausedAt), accuracy: 0.0001)
        clock.date = shiftedEnd
        controller.tick()
        XCTAssertEqual(player.events, [.focusCompleted, .breakCompleted, .focusCompleted])
    }

    func testRestoreOnlyPlaysForStillRunningSessionAtLiveCompletion() throws {
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try store.saveSettings(FocusSettings(focusDuration: 1, soundsEnabled: true))
        let start = Date(timeIntervalSince1970: 50_000)
        let clock = SoundPolicyClock(start)
        let original = FocusController(store: store, now: { clock.date })
        original.start(kind: .focus)
        let player = FakePolicyPlayer()
        clock.date = start.addingTimeInterval(0.5)
        let restored = FocusController(store: store, now: { clock.date }, sounds: player)
        clock.date = try XCTUnwrap(restored.session.targetEnd)
        restored.tick()
        XCTAssertEqual(player.events, [.focusCompleted])

        clock.date = clock.date.addingTimeInterval(1)
        let completed = FocusController(store: store, now: { clock.date }, sounds: player)
        XCTAssertEqual(completed.session.state, .completed)
        XCTAssertEqual(player.events, [.focusCompleted])

        let expiredDefaults = UserDefaults(suiteName: "\(suiteName).expired")!
        defer { expiredDefaults.removePersistentDomain(forName: "\(suiteName).expired") }
        let expiredStore = FocusStore(defaults: expiredDefaults)
        let expiredClock = SoundPolicyClock(start)
        let expiring = FocusController(store: expiredStore, now: { expiredClock.date })
        expiring.start(kind: .focus)
        expiredClock.date = try XCTUnwrap(expiring.session.targetEnd).addingTimeInterval(8)
        let expiredPlayer = FakePolicyPlayer()
        let expired = FocusController(store: expiredStore, now: { expiredClock.date }, sounds: expiredPlayer)
        XCTAssertEqual(expired.session.state, .completed)
        XCTAssertTrue(expiredPlayer.events.isEmpty)
    }

    func testNotificationsSuppressAppPlayerAndDisabledNotificationsAllowIt() throws {
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try store.saveSettings(FocusSettings(focusDuration: 1, notificationsEnabled: true, soundsEnabled: true))
        let clock = SoundPolicyClock(Date(timeIntervalSince1970: 60_000))
        let player = FakePolicyPlayer()
        let controller = FocusController(store: store, now: { clock.date }, sounds: player)
        controller.start(kind: .focus)
        clock.date = try XCTUnwrap(controller.session.targetEnd)
        controller.tick()
        XCTAssertTrue(player.events.isEmpty)

        controller.setNotificationsEnabled(false)
        controller.start(kind: .focus)
        clock.date = try XCTUnwrap(controller.session.targetEnd)
        controller.tick()
        XCTAssertEqual(player.events, [.focusCompleted])
    }

    func testNaturalPauseKindsMapToBreakAndManualTransitionsStaySilent() throws {
        let (controller, clock, player, defaults) = try makeController()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        controller.start(kind: .focus)
        controller.pause()
        controller.resume()
        controller.finish()
        controller.skip()
        XCTAssertTrue(player.events.isEmpty)

        controller.start(kind: .shortBreak)
        clock.date = try XCTUnwrap(controller.session.targetEnd)
        controller.tick()
        controller.start(kind: .longBreak)
        clock.date = try XCTUnwrap(controller.session.targetEnd)
        controller.tick()
        XCTAssertEqual(player.events, [.breakCompleted, .breakCompleted])
    }

    func testPlaybackFailureIsNotRetriedOnRepeatedTicks() throws {
        let (controller, clock, player, defaults) = try makeController(player: FakePolicyPlayer(fails: true))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        controller.start(kind: .focus)
        clock.date = try XCTUnwrap(controller.session.targetEnd)
        controller.tick()
        controller.tick()
        XCTAssertEqual(player.events, [.focusCompleted])
        XCTAssertEqual(controller.session.state, .completed)
        XCTAssertNotNil(controller.error)
    }

    private let suiteName = "FocusControllerSoundPolicyTests.\(UUID().uuidString)"

    private func makeStore() -> (FocusStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (FocusStore(defaults: defaults), defaults)
    }

    private func makeController(player: FakePolicyPlayer = FakePolicyPlayer()) throws -> (FocusController, SoundPolicyClock, FakePolicyPlayer, UserDefaults) {
        let (store, defaults) = makeStore()
        try store.saveSettings(FocusSettings(focusDuration: 1, shortBreakDuration: 1, longBreakDuration: 1, soundsEnabled: true))
        let clock = SoundPolicyClock(Date(timeIntervalSince1970: 40_000))
        return (FocusController(store: store, now: { clock.date }, sounds: player), clock, player, defaults)
    }
}

@MainActor
private final class FakePolicyPlayer: SessionSoundPlaying {
    private(set) var events: [SessionSoundEvent] = []
    private let fails: Bool

    init(fails: Bool = false) { self.fails = fails }

    func play(_ event: SessionSoundEvent, enabled: Bool) throws {
        events.append(event)
        if fails { throw PolicySoundError.failed }
    }
}

private enum PolicySoundError: Error { case failed }

@MainActor
private final class SoundPolicyClock {
    var date: Date
    init(_ date: Date) { self.date = date }
}

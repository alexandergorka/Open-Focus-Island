import FocusCore
import XCTest
@testable import OpenFocusIsland

@MainActor
final class FocusControllerSoundTests: XCTestCase {
    func testSavingDurationsPreservesStoredSoundPreference() throws {
        let suite = "FocusControllerSoundTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FocusStore(defaults: defaults)
        try store.saveSettings(FocusSettings(soundsEnabled: true))
        let controller = FocusController(store: store)

        XCTAssertTrue(controller.settings.soundsEnabled)
        XCTAssertTrue(controller.saveSettings(FocusSettings(focusDuration: 1_200)))

        XCTAssertTrue(store.loadSettings().soundsEnabled)
    }

    func testNaturalFocusAndBreakCompletionPlayTheirEvents() throws {
        let clock = SoundTestClock(Date(timeIntervalSince1970: 10_000))
        let (store, defaults) = try makeStore(soundsEnabled: true)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let player = FakeSessionSoundPlayer()
        let controller = FocusController(store: store, now: { clock.date }, sounds: player)

        controller.start(kind: .focus)
        clock.date = clock.date.addingTimeInterval(controller.settings.focusDuration)
        controller.tick()
        controller.start(kind: .shortBreak)
        clock.date = clock.date.addingTimeInterval(controller.settings.shortBreakDuration)
        controller.tick()

        XCTAssertEqual(player.events, [.focusCompleted, .breakCompleted])
        XCTAssertEqual(controller.session.state, .completed)
        XCTAssertEqual(controller.history.count, 1)
    }

    func testOptOutAndPlaybackFailureDoNotPreventCompletionOrHistory() throws {
        let clock = SoundTestClock(Date(timeIntervalSince1970: 20_000))
        let (store, defaults) = try makeStore(soundsEnabled: false)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let player = FakeSessionSoundPlayer(failure: TestSoundError.failed)
        let controller = FocusController(store: store, now: { clock.date }, sounds: player)
        controller.start(kind: .focus)
        clock.date = clock.date.addingTimeInterval(controller.settings.focusDuration)
        controller.tick()
        XCTAssertTrue(player.events.isEmpty)

        controller.setSoundsEnabled(true)
        controller.start(kind: .focus)
        clock.date = clock.date.addingTimeInterval(controller.settings.focusDuration)
        controller.tick()

        XCTAssertEqual(player.events, [.focusCompleted])
        XCTAssertEqual(controller.session.state, .completed)
        XCTAssertEqual(controller.history.count, 2)
        XCTAssertNotNil(controller.error)
        XCTAssertTrue(store.loadSettings().soundsEnabled)
    }

    private let suiteName = "FocusControllerSoundTests.\(UUID().uuidString)"

    private func makeStore(soundsEnabled: Bool) throws -> (FocusStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = FocusStore(defaults: defaults)
        try store.saveSettings(FocusSettings(soundsEnabled: soundsEnabled))
        return (store, defaults)
    }
}

@MainActor
private final class FakeSessionSoundPlayer: SessionSoundPlaying {
    private(set) var events: [SessionSoundEvent] = []
    private let failure: Error?

    init(failure: Error? = nil) { self.failure = failure }

    func play(_ event: SessionSoundEvent, enabled: Bool) throws {
        events.append(event)
        if let failure { throw failure }
    }
}

private enum TestSoundError: Error { case failed }

@MainActor
private final class SoundTestClock {
    var date: Date
    init(_ date: Date) { self.date = date }
}

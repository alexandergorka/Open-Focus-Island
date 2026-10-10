import AppKit
import FocusCore
import XCTest
@testable import OpenFocusIsland

@MainActor
final class FocusCompletionAcknowledgementTests: XCTestCase {
    private var suiteName = ""
    private var clock = AckClock(Date(timeIntervalSince1970: 70_000))

    override func setUp() {
        suiteName = "FocusCompletionAcknowledgementTests.\(UUID())"
        clock = AckClock(Date(timeIntervalSince1970: 70_000))
    }

    override func tearDown() { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

    private func makeStore() throws -> FocusStore {
        let store = FocusStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        try store.saveSettings(FocusSettings(focusDuration: 1, shortBreakDuration: 1, longBreakDuration: 1))
        return store
    }

    private func makeController() throws -> FocusController {
        FocusController(store: try makeStore(), now: { [clock] in clock.date })
    }

    private func complete(_ controller: FocusController, after extra: TimeInterval = 0) throws {
        clock.date = try XCTUnwrap(controller.session.targetEnd).addingTimeInterval(extra)
        controller.tick()
    }

    func testNaturalFocusCompletionAwaitsAcknowledgement() throws {
        let controller = try makeController()
        controller.start(kind: .focus)
        XCTAssertNil(controller.awaitingAcknowledgement)
        try complete(controller)
        XCTAssertEqual(controller.awaitingAcknowledgement, .focus)
        controller.acknowledgeCompletion()
        XCTAssertNil(controller.awaitingAcknowledgement)
    }

    func testBreakCompletionAwaitsAcknowledgementWithBreakKind() throws {
        let controller = try makeController()
        controller.start(kind: .shortBreak)
        try complete(controller)
        XCTAssertEqual(controller.awaitingAcknowledgement, .shortBreak)
    }

    func testLateDetectionStillAwaitsAcknowledgement() throws {
        let controller = try makeController()
        controller.start(kind: .focus)
        try complete(controller, after: 600)
        XCTAssertEqual(controller.awaitingAcknowledgement, .focus)
    }

    func testManualFinishAndSkipDoNotRequireAcknowledgement() throws {
        let controller = try makeController()
        controller.start(kind: .focus)
        controller.finish()
        XCTAssertNil(controller.awaitingAcknowledgement)
        controller.start(kind: .focus)
        controller.skip()
        XCTAssertNil(controller.awaitingAcknowledgement)
    }

    func testStartingNextPhaseClearsAcknowledgement() throws {
        let controller = try makeController()
        controller.start(kind: .focus)
        try complete(controller)
        controller.start(kind: .shortBreak)
        XCTAssertNil(controller.awaitingAcknowledgement)
        try complete(controller)
        XCTAssertEqual(controller.awaitingAcknowledgement, .shortBreak)
        controller.start(kind: .focus)
        try complete(controller)
        controller.skip()
        XCTAssertNil(controller.awaitingAcknowledgement)
    }

    func testRestoredCompletionAtLaunchDoesNotRequireAcknowledgement() throws {
        let store = try makeStore()
        let original = FocusController(store: store, now: { [clock] in clock.date })
        original.start(kind: .focus)
        clock.date = try XCTUnwrap(original.session.targetEnd).addingTimeInterval(30)
        let restored = FocusController(store: store, now: { [clock] in clock.date })
        XCTAssertEqual(restored.session.state, .completed)
        XCTAssertNil(restored.awaitingAcknowledgement)
    }

    func testPanelStaysVisibleWhileAwaitingAcknowledgement() throws {
        _ = NSApplication.shared
        let controller = try makeController()
        let panel = FocusPanel(controller: controller, screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), screenID: 1)
        defer { panel.orderOut(nil) }
        panel.hidesWhenIdle = true
        controller.start(kind: .focus)
        try complete(controller)
        XCTAssertEqual(controller.session.state, .completed)
        panel.updateVisibility()
        XCTAssertTrue(panel.isVisible)
        controller.acknowledgeCompletion()
        panel.updateVisibility()
        XCTAssertFalse(panel.isVisible)
    }

    /// Regression: Phasenende klappt das Panel über den AppDelegate-Sink auf; zuvor kämpfte NSHostingView.updateAnimatedWindowSize
    /// gegen setFrame (Update-Constraints-Exception). Die Exception trat nur im echten Lauf auf, dort sichert /tmp/ofi-qa/repro.sh ab.
    func testNaturalCompletionOpensControlsThroughAppDelegateWithoutCrashing() throws {
        let policy = NSApplication.shared.activationPolicy()
        defer { NSApp.setActivationPolicy(policy) } // applicationDidFinishLaunching stellt .accessory ein
        let controller = try makeController()
        let delegate = AppDelegate(controller: controller)
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        let panel = try XCTUnwrap(delegate.panel)
        defer { panel.orderOut(nil) }
        controller.start(kind: .focus)
        try complete(controller)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.presentation, .controls)
        controller.acknowledgeCompletion()
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        XCTAssertEqual(panel.presentation, .compact)
    }

    func testAcknowledgementCardButtonsAcknowledgeAndStartBreak() throws {
        _ = NSApplication.shared
        let controller = try makeController()
        let panel = FocusPanel(controller: controller, screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), screenID: 1)
        defer { panel.orderOut(nil) }
        controller.start(kind: .focus)
        try complete(controller)
        panel.openControls()
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.3))
        XCTAssertEqual(panel.presentation, .controls)
        let text = try recognizedText(in: try XCTUnwrap(panel.contentView)).map(\.text).joined(separator: "\n")
        XCTAssertTrue(text.contains("Focus complete"), text)
        XCTAssertTrue(text.contains("Got it"), text)
        XCTAssertTrue(text.contains("Start break"), text)
        XCTAssertFalse(text.contains("Start focus"), text)

        // SwiftUI-Buttons sind im Test nicht per Accessibility erreichbar; die Aktionen der Buttons laufen direkt über den Controller.
        controller.acknowledgeCompletion()
        XCTAssertNil(controller.awaitingAcknowledgement)

        controller.start(kind: .focus)
        try complete(controller)
        controller.start(kind: controller.session.recommendedBreak)
        XCTAssertNil(controller.awaitingAcknowledgement)
        XCTAssertEqual(controller.session.state, .running)
        XCTAssertEqual(controller.session.kind, .shortBreak)
    }
}

private final class AckClock: @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
}

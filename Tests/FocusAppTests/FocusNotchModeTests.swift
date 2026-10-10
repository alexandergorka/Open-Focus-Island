import AppKit
import FocusCore
import XCTest
@testable import OpenFocusIsland

@MainActor
final class FocusNotchModeTests: XCTestCase {
    func testDurationSavePreservesDisabledNotchPreference() throws {
        let (store, defaults, suite) = try makeStore(enabled: false)
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = FocusController(store: store)
        XCTAssertTrue(controller.saveSettings(FocusSettings(focusDuration: 1200)))
        XCTAssertFalse(store.loadSettings().notchModeEnabled)
        XCTAssertEqual(controller.settings.focusDuration, 1200)
    }

    func testDisabledNotchUsesLegacyAtLaunchAndAfterDisplayChanges() throws {
        _ = NSApplication.shared
        let screen = try notchScreen()
        let (store, defaults, suite) = try makeStore(enabled: false)
        defer { defaults.removePersistentDomain(forName: suite) }
        let activeScreen = NotchTestScreen(screen)
        let panel = FocusPanel(controller: FocusController(store: store), applicationScreen: { activeScreen.screen })
        defer { panel.orderOut(nil) }
        settle(panel)
        XCTAssertEqual(panel.frame.height, 64, accuracy: 1)
        XCTAssertLessThanOrEqual(panel.frame.maxY, screen.visibleFrame.maxY)
        panel.setExpanded(true)
        settle(panel)
        XCTAssertEqual(panel.presentation, .controls)
        if let other = NSScreen.screens.first(where: { $0 !== screen }) {
            activeScreen.screen = other
            panel.refreshPosition()
            activeScreen.screen = screen
            panel.refreshPosition()
            settle(panel)
            XCTAssertEqual(panel.frame.height, 64, accuracy: 1)
            XCTAssertLessThanOrEqual(panel.frame.maxY, screen.visibleFrame.maxY)
            panel.setExpanded(true)
            settle(panel)
            XCTAssertEqual(panel.presentation, .controls)
        }
    }

    func testVisibleNotchToggleUpdatesLivePanelPersistsAndKeepsSettingsOpen() throws {
        _ = NSApplication.shared
        let screen = try notchScreen()
        let (store, defaults, suite) = try makeStore(enabled: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = FocusController(store: store)
        let initialSession = controller.session
        let panel = FocusPanel(controller: controller, applicationScreen: { screen })
        defer { panel.orderOut(nil) }
        panel.makeKeyAndOrderFront(nil)
        panel.openControls()
        let menu = makeSettingsMenu(controller)
        defer { menu.orderOut(nil) }
        try settingsMenuButton("Show settings", in: menu).performClick(nil)
        settleSettingsMenu(menu)
        settle(panel)
        XCTAssertEqual(panel.frame.maxY, screen.frame.maxY, accuracy: 1)

        try clickNotchToggle(in: menu)
        settleSettingsMenu(menu)
        settle(panel)
        XCTAssertFalse(controller.settings.notchModeEnabled)
        XCTAssertFalse(store.loadSettings().notchModeEnabled)
        XCTAssertEqual(panel.presentation, .controls)
        XCTAssertLessThanOrEqual(panel.frame.maxY, screen.visibleFrame.maxY)
        XCTAssertEqual(notchSwitches(in: menu).count, 1, "Settings must remain open")

        try clickNotchToggle(in: menu)
        settleSettingsMenu(menu)
        settle(panel)
        XCTAssertTrue(store.loadSettings().notchModeEnabled)
        XCTAssertEqual(panel.presentation, .controls)
        XCTAssertEqual(panel.frame.maxY, screen.frame.maxY, accuracy: 1)
        XCTAssertEqual(controller.session, initialSession)
        XCTAssertFalse(controller.settings.soundsEnabled)
        XCTAssertFalse(controller.settings.notificationsEnabled)
        XCTAssertTrue(FocusController(store: store).settings.notchModeEnabled)
    }

    private func clickNotchToggle(in panel: NSPanel) throws {
        let button = try XCTUnwrap(notchSwitches(in: panel).first, "The visible Notch-Modus switch must exist")
        let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        NSApp.postEvent(up, atStart: false) // NSSwitch tracks mouseDown synchronously until mouseUp.
        NSApp.sendEvent(down)

    }

    private func notchSwitches(in panel: NSPanel) -> [NSSwitch] {
        descendants(panel.contentView).compactMap { $0 as? NSSwitch }
    }

    private func descendants(_ view: NSView?) -> [NSView] {
        guard let view else { return [] }
        return [view] + view.subviews.flatMap { descendants($0) }
    }

    private func settle(_ panel: FocusPanel) {
        for _ in 0..<5 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            panel.contentView?.layoutSubtreeIfNeeded()
        }
    }

    private func notchScreen() throws -> NSScreen {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) else {
            throw XCTSkip("Native Notch-Umschaltung benötigt einen Bildschirm mit Notch")
        }
        return screen
    }

    private func makeStore(enabled: Bool) throws -> (FocusStore, UserDefaults, String) {
        let suite = "FocusNotchModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = FocusStore(defaults: defaults)
        try store.saveSettings(FocusSettings(notchModeEnabled: enabled))
        return (store, defaults, suite)
    }
}

@MainActor
private final class NotchTestScreen {
    var screen: NSScreen
    init(_ screen: NSScreen) { self.screen = screen }
}

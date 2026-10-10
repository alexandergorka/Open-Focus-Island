import AppKit
import FocusCore
import XCTest
@testable import OpenFocusIsland

@MainActor
final class FocusSoundSettingsPanelTests: XCTestCase {
    func testVisibleSoundToggleImmediatelyPersistsPreference() throws {
        _ = NSApplication.shared
        let suite = "FocusSoundSettingsPanelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = FocusStore(defaults: defaults)
        let controller = FocusController(store: store)
        let panel = makeSettingsMenu(controller)
        defer { panel.orderOut(nil); defaults.removePersistentDomain(forName: suite) }
        panel.makeKeyAndOrderFront(nil)
        settle(panel)

        let settings = try XCTUnwrap(descendantViews(of: panel.contentView).compactMap { $0 as? NSButton }
            .first { $0.accessibilityLabel() == "Show settings" })
        settings.performClick(nil)
        settle(panel)
        let checkboxes = descendantViews(of: panel.contentView).compactMap { $0 as? NSButton }
            .filter { String(describing: type(of: $0)).contains("FocusRingNSButton") }
        XCTAssertEqual(checkboxes.count, 3, "The visible settings form must show all preference toggles")
        guard checkboxes.count == 3 else { return }
        let toggle = try XCTUnwrap(checkboxes.last, "The sound toggle follows the notification toggle in the visible form")

        let center = toggle.convert(NSPoint(x: toggle.bounds.midX, y: toggle.bounds.midY), to: nil)
        let screenPoint = panel.convertPoint(toScreen: center)
        NSApp.sendEvent(try mouseEvent(.leftMouseDown, atScreen: screenPoint, in: panel))
        NSApp.sendEvent(try mouseEvent(.leftMouseUp, atScreen: screenPoint, in: panel))
        settle(panel)

        XCTAssertTrue(controller.settings.soundsEnabled)
        XCTAssertTrue(store.loadSettings().soundsEnabled)
    }

    private func settle(_ panel: NSPanel) {
        settleSettingsMenu(panel)
    }

    private func descendantViews(of view: NSView?) -> [NSView] {
        guard let view else { return [] }
        return [view] + view.subviews.flatMap(descendantViews)
    }

    private func mouseEvent(_ type: NSEvent.EventType, atScreen point: NSPoint, in panel: NSPanel) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: panel.convertPoint(fromScreen: point), modifierFlags: [],
                                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                                        context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }
}

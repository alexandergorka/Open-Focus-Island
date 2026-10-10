import AppKit
import FocusCore
import XCTest
@testable import OpenFocusIsland

@MainActor
final class FocusLanguagePanelTests: XCTestCase {
    func testAccessibilityLabelsSwitchLive() throws {
        _ = NSApplication.shared
        let suite = "FocusLanguagePanelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = FocusStore(defaults: defaults)
        try store.saveSettings(FocusSettings(language: .german))
        let controller = FocusController(store: store)
        let panel = FocusPanel(controller: controller, screenFrame: CGRect(x: 0, y: 0, width: 800, height: 800))
        defer { panel.orderOut(nil); defaults.removePersistentDomain(forName: suite) }
        panel.makeKeyAndOrderFront(nil)
        settle(panel)

        func handleLabel() throws -> String? {
            try XCTUnwrap(descendantViews(of: panel.contentView).first { $0.identifier?.rawValue == "panel-drag-handle" }).accessibilityLabel()
        }
        func button(_ label: String) -> NSButton? {
            descendantViews(of: panel.contentView).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == label }
        }

        XCTAssertEqual(try handleLabel(), "Panel verschieben")
        controller.setLanguage(.english)
        settle(panel)
        XCTAssertEqual(try handleLabel(), "Move panel", "Der Griff muss ohne neues Panel die Sprache wechseln")

        panel.setExpanded(true)
        settle(panel)
        XCTAssertNotNil(button("Collapse"))
        let menu = makeSettingsMenu(controller)
        defer { menu.orderOut(nil) }
        XCTAssertEqual(try settingsMenuButton("Show settings", in: menu).accessibilityValue() as? String, "Collapsed")
        XCTAssertEqual(try settingsMenuButton("Show history", in: menu).toolTip, "Show history")

        controller.setLanguage(.german)
        settle(panel)
        XCTAssertNotNil(button("Einklappen"))
        settleSettingsMenu(menu)
        XCTAssertEqual(try settingsMenuButton("Einstellungen anzeigen", in: menu).accessibilityValue() as? String, "Geschlossen")
        XCTAssertEqual(try settingsMenuButton("Verlauf anzeigen", in: menu).toolTip, "Verlauf anzeigen")
        let history = FocusHistoryWindow(controller: controller)
        defer { history.orderOut(nil) }
        XCTAssertEqual(history.title, "Verlauf")
        controller.setLanguage(.english)
        settleSettingsMenu(menu)
        XCTAssertEqual(history.title, "History")
    }

    func testVisibleCardTextFollowsLanguage() throws {
        _ = NSApplication.shared
        let suite = "FocusLanguagePanelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let controller = FocusController(store: FocusStore(defaults: defaults))
        let panel = FocusPanel(controller: controller, screenFrame: CGRect(x: 0, y: 0, width: 800, height: 800))
        defer { panel.orderOut(nil); defaults.removePersistentDomain(forName: suite) }
        panel.makeKeyAndOrderFront(nil)
        panel.setExpanded(true)
        settle(panel)

        func visibleText() throws -> String {
            try recognizedText(in: XCTUnwrap(panel.contentView)).map(\.text).joined(separator: " ")
        }
        var text = try visibleText()
        for expected in ["Start focus", "Short break", "Long break"] {
            XCTAssertTrue(text.contains(expected), "\(expected) fehlt: \(text)")
        }
        let menu = makeSettingsMenu(controller)
        defer { menu.orderOut(nil) }
        try settingsMenuButton("Show settings", in: menu).performClick(nil)
        settleSettingsMenu(menu)
        text = try recognizedText(in: XCTUnwrap(menu.contentView)).map(\.text).joined(separator: " ")
        for expected in ["Notifications", "Save"] {
            XCTAssertTrue(text.contains(expected), "\(expected) fehlt: \(text)")
        }
        controller.setLanguage(.german)
        settle(panel)
        settleSettingsMenu(menu)
        text = try visibleText()
        for expected in ["Fokus starten", "Kurze Pause"] {
            XCTAssertTrue(text.contains(expected), "\(expected) fehlt: \(text)")
        }
        text = try recognizedText(in: XCTUnwrap(menu.contentView)).map(\.text).joined(separator: " ")
        for expected in ["Benachrichtigungen", "Speichern"] {
            XCTAssertTrue(text.contains(expected), "\(expected) fehlt: \(text)")
        }
    }

    func testLanguagePickerSwitchesAndPersists() throws {
        _ = NSApplication.shared
        let suite = "FocusLanguagePanelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let controller = FocusController(store: FocusStore(defaults: defaults))
        let panel = makeSettingsMenu(controller)
        defer { panel.orderOut(nil); defaults.removePersistentDomain(forName: suite) }
        panel.makeKeyAndOrderFront(nil)
        settleSettingsMenu(panel)

        func button(_ label: String) -> NSButton? {
            descendantViews(of: panel.contentView).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == label }
        }
        try XCTUnwrap(button("Show settings")).performClick(nil)
        settleSettingsMenu(panel)

        func click(segment index: Int) throws {
            let picker = try XCTUnwrap(descendantViews(of: panel.contentView).compactMap { $0 as? NSSegmentedControl }.first,
                                       "The settings form must show a segmented language picker")
            let width = picker.bounds.width / CGFloat(picker.segmentCount)
            let center = picker.convert(NSPoint(x: width * (CGFloat(index) + 0.5), y: picker.bounds.midY), to: nil)
            func event(_ type: NSEvent.EventType) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: center, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                                                 context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            }
            NSApp.postEvent(try event(.leftMouseUp), atStart: false) // NSSegmentedControl tracks mouseDown synchronously until mouseUp.
            NSApp.sendEvent(try event(.leftMouseDown))
            settleSettingsMenu(panel)
        }

        try click(segment: 1)
        XCTAssertEqual(controller.settings.language, .german)
        XCTAssertEqual(FocusStore(defaults: defaults).loadSettings().language, .german)
        XCTAssertNotNil(button("Einstellungen ausblenden"), "The menu must switch language live")

        try click(segment: 0)
        XCTAssertEqual(controller.settings.language, .english)
        XCTAssertEqual(FocusStore(defaults: defaults).loadSettings().language, .english)
    }

    private func settle(_ panel: FocusPanel) {
        for _ in 0..<4 {
            panel.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
    }
}

import AppKit
import FocusCore
import SwiftUI
import Vision
import XCTest
@testable import OpenFocusIsland

@MainActor
final class FocusControlLayoutTests: XCTestCase {
    func testPanelContainsOnlySessionControlsWithoutDisclosureGaps() throws {
        let (controller, defaults, suite) = try isolatedController()
        let panel = makePanel(controller)
        defer { panel.orderOut(nil); defaults.removePersistentDomain(forName: suite) }
        for language in [AppLanguage.english, .german] {
            controller.setLanguage(language)
            settle(panel)
            let labels = descendants(panel.contentView).compactMap { $0 as? NSButton }.compactMap { $0.accessibilityLabel() }
            for absent in ["Settings", "History", "Einstellungen", "Verlauf"] {
                XCTAssertFalse(labels.contains(absent), "Das Timerpanel enthält keine Formular- oder Verlaufsschaltfläche")
            }
            XCTAssertEqual(descendants(panel.contentView).compactMap { $0 as? NSSwitch }.count, 0)
            XCTAssertEqual(descendants(panel.contentView).compactMap { $0 as? NSTextField }.filter { $0.isEditable }.count, 1)
            let lastAction = try text(language.t("Short break", "Kurze Pause"), in: panel)
            XCTAssertLessThan(panel.frame.height, 350, "Nach dem Entfernen der Sektionen schrumpft die echte Karte")
            XCTAssertLessThan(lastAction.minY, 40, "Unter den letzten Aktionen bleibt nur der normale Kartenabstand")
            try snapshot(panel, name: language == .english ? "panel-session-only-en" : "panel-session-only-de")
        }
    }

    func testMenuSettingsTextAndTrailingRowToggleTheForm() throws {
        let (controller, defaults, suite) = try isolatedController()
        let menu = makeMenu(controller)
        defer { menu.orderOut(nil); defaults.removePersistentDomain(forName: suite) }
        settle(menu)
        XCTAssertEqual(menu.contentView?.fittingSize.width ?? 0, 340, accuracy: 1,
                       "Test und echtes Menü müssen dieselbe natürliche Inhaltsbreite verwenden")
        let collapsedHeight = menu.frame.height
        try snapshot(menu, name: "menu-idle-closed")
        let header = try button("Show settings", in: menu)
        XCTAssertEqual(header.title, "Show settings", "Die Beschriftung erklärt die Aktion ohne Pfeil")
        XCTAssertEqual(header.accessibilityValue() as? String, "Collapsed")
        XCTAssertGreaterThanOrEqual(header.frame.width, 300)
        XCTAssertEqual(header.frame.height, 36, accuracy: 1)
        try clickText("Show settings", in: menu)
        XCTAssertEqual(descendants(menu.contentView).compactMap { $0 as? NSSwitch }.count, 1,
                       "Auch das echte Menü-View muss beim Textklick öffnen")
        let expandedHeader = try button("Hide settings", in: menu)
        XCTAssertEqual(expandedHeader.title, "Hide settings")
        XCTAssertEqual(expandedHeader.accessibilityValue() as? String, "Expanded")
        let notchSwitch = try XCTUnwrap(descendants(menu.contentView).compactMap { $0 as? NSSwitch }.first)
        XCTAssertEqual(notchSwitch.convert(notchSwitch.bounds, to: nil).maxX,
                       expandedHeader.convert(expandedHeader.bounds, to: nil).maxX, accuracy: 6,
                       "Der Switch bleibt rechts mit der Eingabespalte ausgerichtet")
        let headerText = try text("Hide settings", in: menu)
        let fieldText = try text("Focus", in: menu, exact: true)
        XCTAssertEqual(headerText.minX, fieldText.minX, accuracy: 6,
                       "Settingsüberschrift und Formularlabels haben dieselbe linke Kante")
        XCTAssertGreaterThan(menu.frame.height, collapsedHeight + 200,
                             "Das natürliche Menü muss das Formular vollständig aufnehmen")
        try assertSettingsAndFooterVisible(in: menu, save: "Save", quit: "Quit", history: "Show history")
        try snapshot(menu, name: "menu-idle-settings")
        let bounds = expandedHeader.convert(expandedHeader.bounds, to: nil)
        try click(NSPoint(x: bounds.maxX - 2, y: bounds.midY), in: menu)
        XCTAssertEqual(descendants(menu.contentView).compactMap { $0 as? NSSwitch }.count, 0,
                       "Auch die freie Fläche am Zeilenende muss Einstellungen schließen")
        XCTAssertEqual(try button("Show settings", in: menu).accessibilityValue() as? String, "Collapsed")
        XCTAssertEqual(menu.frame.height, collapsedHeight, accuracy: 1, "Nach dem Schließen bleibt keine Formularlücke")
    }

    func testMenuSettingsLabelsAndStateFollowLanguageLive() throws {
        let (controller, defaults, suite) = try isolatedController()
        let menu = makeMenu(controller)
        defer { menu.orderOut(nil); defaults.removePersistentDomain(forName: suite) }
        settle(menu)
        controller.setLanguage(.german)
        settle(menu)
        let header = try button("Einstellungen anzeigen", in: menu)
        XCTAssertEqual(header.title, "Einstellungen anzeigen")
        XCTAssertEqual(header.accessibilityValue() as? String, "Geschlossen")
        XCTAssertGreaterThanOrEqual(header.frame.width, 300)
        XCTAssertEqual(header.frame.height, 36, accuracy: 1)
        let bounds = header.convert(header.bounds, to: nil)
        try click(NSPoint(x: bounds.maxX - 2, y: bounds.midY), in: menu)
        let expanded = try button("Einstellungen ausblenden", in: menu)
        XCTAssertEqual(expanded.title, "Einstellungen ausblenden")
        XCTAssertEqual(expanded.accessibilityValue() as? String, "Geöffnet")
        XCTAssertEqual(descendants(menu.contentView).compactMap { $0 as? NSSwitch }.count, 1)
        try assertSettingsAndFooterVisible(in: menu, save: "Speichern", quit: "Beenden", history: "Verlauf anzeigen")
        try snapshot(menu, name: "menu-settings-de")
        controller.setLanguage(.english)
        settle(menu)
        XCTAssertEqual(try button("Hide settings", in: menu).title, "Hide settings")
        XCTAssertEqual(try button("Hide settings", in: menu).accessibilityValue() as? String, "Expanded")
        XCTAssertEqual(descendants(menu.contentView).compactMap { $0 as? NSSwitch }.count, 1,
                       "Ein Sprachwechsel muss das geöffnete Formular erhalten")
        controller.setLanguage(.german)
        settle(menu)
        try clickText("Einstellungen ausblenden", in: menu)
        XCTAssertEqual(try button("Einstellungen anzeigen", in: menu).title, "Einstellungen anzeigen")
        XCTAssertEqual(descendants(menu.contentView).compactMap { $0 as? NSSwitch }.count, 0)
        try snapshot(menu, name: "menu-closed-de")
    }

    private func assertSettingsAndFooterVisible(in menu: NSWindow, save: String, quit: String, history: String) throws {
        let view = try XCTUnwrap(menu.contentView)
        let bounds = view.convert(view.bounds, to: nil)
        for label in [save, quit] {
            let frame = try text(label, in: menu)
            XCTAssertTrue(bounds.contains(frame), "\(label) muss ohne Abschneiden erreichbar bleiben")
        }
        let historyButton = try button(history, in: menu)
        XCTAssertTrue(bounds.contains(historyButton.convert(historyButton.bounds, to: nil)))
        XCTAssertGreaterThanOrEqual(historyButton.frame.width, 36)
        XCTAssertGreaterThanOrEqual(historyButton.frame.height, 36)
        XCTAssertEqual(descendants(view).compactMap { $0 as? NSSwitch }.count, 1)
        XCTAssertEqual(descendants(view).compactMap { $0 as? NSTextField }.filter { $0.isEditable }.count, 4,
                       "Aufgabe und alle drei Dauerfelder müssen im geöffneten Menü vorhanden sein")
    }

    func testActionTargetsAndAlignmentAcrossSessionStates() throws {
        for surface in ["panel", "menu"] {
            for (state, primary) in [("idle", "Start focus"), ("running", "Pause"), ("paused", "Resume")] {
                let (controller, defaults, suite) = try isolatedController()
                if state != "idle" { controller.start(kind: .focus) }
                if state == "paused" { controller.pause() }
                let window: NSPanel = surface == "panel" ? makePanel(controller) : makeMenu(controller)
                defer { window.orderOut(nil); defaults.removePersistentDomain(forName: suite) }
                settle(window)
                try snapshot(window, name: "\(surface)-\(state)")
                let primaryText = try text(primary, in: window)
                print("UI1 \(surface) \(state) primary rendered frame: \(primaryText)")
                XCTAssertEqual(primaryText.midX, window.frame.width / 2, accuracy: 6,
                               "Die primäre Aktion muss in beiden Oberflächen zentriert sein")
                try click(NSPoint(x: primaryText.midX, y: primaryText.midY + 13), in: window)
                XCTAssertEqual(controller.session.state, state == "running" ? .paused : .running,
                               "Auch 13 Punkte über der Textmitte muss \(primary) noch klickbar sein")
            }
        }
    }

    func testRecommendedLongBreakRemainsVisibleAndCentered() throws {
        let (_, defaults, suite) = try isolatedController()
        defer { defaults.removePersistentDomain(forName: suite) }
        var session = FocusSession()
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        for index in 0..<4 {
            XCTAssertTrue(session.start(kind: .focus, duration: 60, at: start.addingTimeInterval(Double(index) * 60)))
            XCTAssertTrue(session.reconcile(at: start.addingTimeInterval(Double(index + 1) * 60)))
        }
        let store = FocusStore(defaults: defaults)
        try store.saveSession(session)
        let controller = FocusController(store: store, now: { start.addingTimeInterval(240) })
        let panel = makePanel(controller)
        let menu = makeMenu(controller)
        defer { panel.orderOut(nil); menu.orderOut(nil) }
        for window in [panel, menu] {
            settle(window)
            try snapshot(window, name: "\(window === panel ? "panel" : "menu")-long-break")
            let recommended = try text("recommended", in: window)
            XCTAssertGreaterThan(recommended.minX, 20)
            XCTAssertLessThan(recommended.maxX, window.frame.width - 20)
            let primary = try text("Start focus", in: window)
            XCTAssertEqual(primary.midX, window.frame.width / 2, accuracy: 6)
        }
    }

    private func isolatedController() throws -> (FocusController, UserDefaults, String) {
        _ = NSApplication.shared
        let suite = "FocusControlLayoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (FocusController(store: FocusStore(defaults: defaults)), defaults, suite)
    }

    private func makePanel(_ controller: FocusController) -> FocusPanel {
        let panel = FocusPanel(controller: controller, screenFrame: CGRect(x: 100, y: 100, width: 800, height: 900), applicationScreen: { nil })
        panel.makeKeyAndOrderFront(nil)
        panel.setExpanded(true)
        return panel
    }

    private func makeMenu(_ controller: FocusController) -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(x: 1000, y: 100, width: 340, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        let delegate = AppDelegate(controller: controller)
        panel.contentView = NSHostingView(rootView: MenuBarControls(controller: controller, onShowHistory: { delegate.showHistory() })
            .fixedSize()
            .background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.dark))
        if let content = panel.contentView { panel.setContentSize(content.fittingSize) }
        panel.makeKeyAndOrderFront(nil)
        return panel
    }

    private func settle(_ window: NSWindow) {
        for _ in 0..<5 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            if !(window is FocusPanel), let content = window.contentView {
                window.setContentSize(content.fittingSize)
            }
            window.contentView?.layoutSubtreeIfNeeded()
        }
    }

    private func descendants(_ view: NSView?) -> [NSView] {
        guard let view else { return [] }
        return [view] + view.subviews.flatMap(descendants)
    }

    private func button(_ label: String, in window: NSWindow) throws -> NSButton {
        try XCTUnwrap(descendants(window.contentView).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == label })
    }

    private func clickText(_ value: String, in window: NSWindow) throws {
        let bounds = try text(value, in: window)
        try click(NSPoint(x: bounds.midX, y: bounds.midY), in: window)
    }

    private func click(_ point: NSPoint, in window: NSWindow) throws {
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
        }
        NSApp.postEvent(try event(.leftMouseUp), atStart: false)
        NSApp.sendEvent(try event(.leftMouseDown))
        // Native controls consume mouseUp while tracking; SwiftUI gestures need it dispatched separately.
        if let up = NSApp.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true) {
            NSApp.sendEvent(up)
        }
        settle(window)
    }

    private func text(_ value: String, in window: NSWindow, exact: Bool = false) throws -> CGRect {
        try XCTUnwrap(try recognizedText(window).first { exact ? $0.text == value : $0.text.contains(value) }, "Sichtbarer Text fehlt: \(value)").frame
    }

    private func bitmap(_ view: NSView) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private func recognizedText(_ window: NSWindow) throws -> [(text: String, frame: CGRect)] {
        let view = try XCTUnwrap(window.contentView)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let rep = try bitmap(view)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try VNImageRequestHandler(data: png).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let bounds = observation.boundingBox
            let local = CGRect(x: bounds.minX * view.bounds.width, y: (view.isFlipped ? 1 - bounds.maxY : bounds.minY) * view.bounds.height,
                               width: bounds.width * view.bounds.width, height: bounds.height * view.bounds.height)
            return (candidate.string, view.convert(local, to: nil))
        }
    }

    private func snapshot(_ window: NSWindow, name: String) throws {
        let stage = ProcessInfo.processInfo.environment["UI_CONTROLS_STAGE"] ?? "after"
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/ui-controls/\(stage)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try XCTUnwrap(try bitmap(XCTUnwrap(window.contentView)).representation(using: .png, properties: [:]))
        try data.write(to: directory.appendingPathComponent("\(name).png"))
    }

}

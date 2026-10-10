import AppKit
import FocusCore
import XCTest
@testable import OpenFocusIsland

@MainActor
final class FocusPanelCollapseTests: XCTestCase {
    func testInactiveCompactPanelReceivesNativeMouseClick() throws {
        try assertCompactClick(applicationScreen: nil, expectedPresentation: .controls)
    }

    func testInactiveCompactNotchPanelReceivesNativeMouseClick() throws {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) else {
            throw XCTSkip("Der Test benötigt ein Display mit Notch")
        }
        try assertCompactClick(applicationScreen: screen, expectedPresentation: .timer)
    }

    private func assertCompactClick(applicationScreen: NSScreen?, expectedPresentation: PanelPresentation) throws {
        _ = NSApplication.shared
        let suite = "FocusPanelCollapseTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let panel = FocusPanel(controller: FocusController(store: FocusStore(defaults: defaults)),
                               screenFrame: applicationScreen == nil ? CGRect(x: -400, y: 0, width: 800, height: 800) : nil,
                               applicationScreen: { applicationScreen })
        defer {
            panel.orderOut(nil)
            defaults.removePersistentDomain(forName: suite)
        }
        panel.orderFrontRegardless()
        settle(panel)
        XCTAssertFalse(NSApp.isActive, "Der Klick muss ohne vorherige App-Aktivierung funktionieren")
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertFalse(panel.ignoresMouseEvents)

        let content = try XCTUnwrap(panel.contentView)
        let point: NSPoint
        if applicationScreen != nil {
            let button = try XCTUnwrap(descendants(of: content).compactMap { $0 as? NSButton }.first)
            point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        } else {
            point = NSPoint(x: content.bounds.midX + 12, y: content.bounds.midY)
        }
        let down = try mouseEvent(.leftMouseDown, at: point, panel: panel)
        let receiver = try XCTUnwrap(content.hitTest(point), "Die sichtbare Leiste muss eine Klickfläche besitzen")
        XCTAssertTrue(receiver.acceptsFirstMouse(for: down),
                      "Die Leiste muss bereits den ersten Klick aus einem anderen Fenster annehmen")
        NSApp.postEvent(try mouseEvent(.leftMouseUp, at: point, panel: panel), atStart: false)
        NSApp.sendEvent(down)
        settle(panel)
        XCTAssertEqual(panel.presentation, expectedPresentation, "Ein Klick auf die kompakte Leiste muss die Timeransicht öffnen")
    }

    /// Echte Nutzer klicken irgendwo auf die schwarze Leiste, nicht exakt auf die Ziffern der Restzeit.
    func testRunningCompactPanelOpensFromClickBesideTimerText() throws {
        _ = NSApplication.shared
        let suite = "FocusPanelCollapseTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let controller = FocusController(store: FocusStore(defaults: defaults))
        controller.start(kind: .focus)
        defer { defaults.removePersistentDomain(forName: suite) }

        for side in ["left", "right"] {
            let panel = FocusPanel(controller: controller, screenFrame: CGRect(x: -400, y: 0, width: 800, height: 800), applicationScreen: { nil })
            defer { panel.orderOut(nil) }
            panel.orderFrontRegardless()
            settle(panel)
            let content = try XCTUnwrap(panel.contentView)
            let handle = try XCTUnwrap(descendants(of: content).first { $0.identifier?.rawValue == "panel-drag-handle" })
            let pillMinX = handle.convert(handle.bounds, to: nil).minX
            let pillMaxX = content.bounds.width - pillMinX
            // Innenabstand der Leiste: links direkt hinter dem Drag-Punkt, rechts kurz vor dem Rand.
            let point = NSPoint(x: side == "left" ? pillMinX + 28 : pillMaxX - 8, y: content.bounds.height - 8 - 24)
            NSApp.postEvent(try mouseEvent(.leftMouseUp, at: point, panel: panel), atStart: false)
            NSApp.sendEvent(try mouseEvent(.leftMouseDown, at: point, panel: panel))
            settle(panel)
            XCTAssertEqual(panel.presentation, .controls, "Klick auf die Leiste (\(side)) neben der Restzeit muss die Bedienung öffnen")
        }
    }

    /// Der WindowServer reicht Klicks sonst durch die SwiftUI-Fläche an das Fenster darunter weiter (nur nativ sichtbar).
    func testCompactPanelCatchesMouseOnlyOverVisibleBar() throws {
        _ = NSApplication.shared
        let suite = "FocusPanelCollapseTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let panel = FocusPanel(controller: FocusController(store: FocusStore(defaults: defaults)),
                               screenFrame: CGRect(x: -400, y: 0, width: 800, height: 800), applicationScreen: { nil })
        defer { panel.orderOut(nil); defaults.removePersistentDomain(forName: suite) }
        panel.orderFrontRegardless()
        settle(panel)
        let handle = try XCTUnwrap(descendants(of: panel.contentView).first { $0.identifier?.rawValue == "panel-drag-handle" })
        let pillMinX = panel.frame.minX + handle.convert(handle.bounds, to: nil).minX
        let barY = panel.frame.maxY - 8 - 24

        panel.updateMousePassThrough(mouse: NSPoint(x: panel.frame.midX, y: barY))
        XCTAssertFalse(panel.ignoresMouseEvents, "Über der Leiste muss die Insel den Klick annehmen")
        panel.updateMousePassThrough(mouse: NSPoint(x: pillMinX - 4, y: barY))
        XCTAssertTrue(panel.ignoresMouseEvents, "Neben der Leiste müssen Klicks an das Fenster darunter gehen")
        panel.setExpanded(true)
        settle(panel)
        panel.updateMousePassThrough(mouse: NSPoint(x: pillMinX - 4, y: barY))
        XCTAssertFalse(panel.ignoresMouseEvents, "Aufgeklappt nimmt das ganze Panel Klicks an")
    }

    func testExpandedCollapseButtonReceivesNativeMouseClick() throws {
        _ = NSApplication.shared
        let suite = "FocusPanelCollapseTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let panel = FocusPanel(controller: FocusController(store: FocusStore(defaults: defaults)),
                               screenFrame: CGRect(x: -400, y: 0, width: 800, height: 800),
                               applicationScreen: { nil })
        defer { panel.orderOut(nil); defaults.removePersistentDomain(forName: suite) }
        panel.makeKeyAndOrderFront(nil)
        panel.setExpanded(true)
        settle(panel)
        XCTAssertEqual(panel.presentation, .controls)

        let button = try XCTUnwrap(descendants(of: panel.contentView).compactMap { $0 as? NSButton }
            .first { $0.accessibilityLabel() == "Collapse" })
        let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        XCTAssertTrue(panel.contentView?.hitTest(point) === button, "Buttonmitte muss den nativen Button treffen")
        NSApp.postEvent(try mouseEvent(.leftMouseUp, at: point, panel: panel), atStart: false)
        NSApp.sendEvent(try mouseEvent(.leftMouseDown, at: point, panel: panel))
        settle(panel)
        XCTAssertEqual(panel.presentation, .compact, "Ein nativer Mausklick auf Einklappen muss die Controls schließen")
    }

    private func descendants(of view: NSView?) -> [NSView] {
        guard let view else { return [] }
        return [view] + view.subviews.flatMap(descendants(of:))
    }

    private func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint, panel: NSPanel) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }

    private func settle(_ panel: NSPanel) {
        for _ in 0..<4 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            panel.contentView?.layoutSubtreeIfNeeded()
        }
    }
}

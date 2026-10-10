import AppKit
import FocusCore
import XCTest
@testable import OpenFocusIsland

@MainActor
final class FocusPanelTests: XCTestCase {
    func testDisplaySwitchChoosesCorrectPresentation() throws {
        _ = NSApplication.shared
        guard let notchScreen = NSScreen.screens.first(where: { candidate in
            NotchGeometry.detect(screenFrame: candidate.frame, safeAreaTop: candidate.safeAreaInsets.top,
                                 leftArea: candidate.auxiliaryTopLeftArea, rightArea: candidate.auxiliaryTopRightArea) != nil
        }) else { throw XCTSkip("N5 benötigt ein echtes NSScreen-Display mit Notch") }
        guard let nonNotchScreen = NSScreen.screens.first(where: { candidate in
            candidate !== notchScreen && NotchGeometry.detect(screenFrame: candidate.frame, safeAreaTop: candidate.safeAreaInsets.top,
                                                               leftArea: candidate.auxiliaryTopLeftArea, rightArea: candidate.auxiliaryTopRightArea) == nil
        }) else {
            throw XCTSkip("Displaywechsel-Fallback benötigt ein echtes Nicht-Notch-Display")
        }
        let otherNotchScreen = NSScreen.screens.first { candidate in
            candidate !== notchScreen && candidate !== nonNotchScreen
                && NotchGeometry.detect(screenFrame: candidate.frame, safeAreaTop: candidate.safeAreaInsets.top,
                                        leftArea: candidate.auxiliaryTopLeftArea, rightArea: candidate.auxiliaryTopRightArea) != nil
        }
        let activeScreen = PanelTestScreenSelection(notchScreen)
        let suiteName = "FocusPanelTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let controller = FocusController(store: FocusStore(defaults: defaults))
        let initialSession = controller.session
        let initialSettings = controller.settings
        let panel = FocusPanel(controller: controller, applicationScreen: { activeScreen.screen })
        defer { panel.orderOut(nil); defaults.removePersistentDomain(forName: suiteName) }
        panel.makeKeyAndOrderFront(nil)
        panel.setExpanded(true)
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        XCTAssertEqual(panel.presentation, .timer)

        let handle = try XCTUnwrap(descendantViews(of: panel.contentView).first { $0.identifier?.rawValue == "panel-drag-handle" })
        let local = handle.convert(NSPoint(x: handle.bounds.midX, y: handle.bounds.midY), to: nil)
        let start = panel.convertPoint(toScreen: local)
        let mouseDown = NSPoint(x: start.x + 8, y: start.y + 4)
        NSApp.sendEvent(try mouseEvent(.leftMouseDown, atScreen: mouseDown, in: panel))
        NSApp.sendEvent(try mouseEvent(.leftMouseDragged, atScreen: NSPoint(x: mouseDown.x, y: mouseDown.y - 100), in: panel))
        settlePanel(panel)
        let detachedMidX = try XCTUnwrap(descendantViews(of: panel.contentView).first { $0.identifier?.rawValue == "panel-drag-handle" })
        let after = panel.convertPoint(toScreen: detachedMidX.convert(NSPoint(x: detachedMidX.bounds.midX, y: detachedMidX.bounds.midY), to: nil))
        XCTAssertEqual(panel.presentation, .compact, "Dragging the notch handle must detach into the legacy presentation")
        XCTAssertEqual(after.x, start.x, accuracy: 1)
        XCTAssertEqual(after.y, start.y - 100, accuracy: 1, "Detaching must preserve the pointer offset")
        let secondDrag = NSPoint(x: mouseDown.x, y: mouseDown.y - 120)
        NSApp.sendEvent(try mouseEvent(.leftMouseDragged, atScreen: secondDrag, in: panel))
        settlePanel(panel)
        NSApp.sendEvent(try mouseEvent(.leftMouseUp, atScreen: secondDrag, in: panel))
        settlePanel(panel)
        let finalHandle = try XCTUnwrap(descendantViews(of: panel.contentView).first { $0.identifier?.rawValue == "panel-drag-handle" })
        let finalPoint = panel.convertPoint(toScreen: finalHandle.convert(NSPoint(x: finalHandle.bounds.midX, y: finalHandle.bounds.midY), to: nil))
        XCTAssertEqual(finalPoint.x, start.x, accuracy: 1)
        XCTAssertEqual(finalPoint.y, start.y - 120, accuracy: 1, "The second native drag event must continue after the SwiftUI branch changes")

        let buttonPoint = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        NSApp.postEvent(try mouseEvent(.leftMouseUp, atScreen: buttonPoint, in: panel), atStart: false)
        NSApp.sendEvent(try mouseEvent(.leftMouseDown, atScreen: buttonPoint, in: panel))
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        XCTAssertEqual(panel.presentation, .controls, "The legacy expand button must remain usable after detaching")
        panel.cancelOperation(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        XCTAssertEqual(panel.presentation, .compact, "Escape must return to the legacy compact view after detaching")
        let beforeResize = panel.frame
        panel.updateContentSize(CGSize(width: 360, height: 84))
        XCTAssertEqual(panel.frame.midX, beforeResize.midX, accuracy: 1, "Resize on the same display must preserve the manual center")
        XCTAssertEqual(panel.frame.maxY, beforeResize.maxY, accuracy: 1, "Resize on the same display must preserve the manual top edge")
        panel.refreshPosition()
        XCTAssertEqual(panel.frame.midX, beforeResize.midX, accuracy: 1)
        XCTAssertEqual(panel.frame.maxY, beforeResize.maxY, accuracy: 1)

        if let otherNotchScreen {
            activeScreen.screen = otherNotchScreen
            panel.refreshPosition()
            let otherNotch = try XCTUnwrap(NotchGeometry.detect(screenFrame: otherNotchScreen.frame, safeAreaTop: otherNotchScreen.safeAreaInsets.top,
                                                                 leftArea: otherNotchScreen.auxiliaryTopLeftArea, rightArea: otherNotchScreen.auxiliaryTopRightArea))
            XCTAssertEqual(panel.frame.maxY, otherNotchScreen.frame.maxY, accuracy: 1)
            XCTAssertEqual(panel.frame.midX, otherNotch.cutoutFrame.midX, accuracy: 1)
        }

        activeScreen.screen = nonNotchScreen
        panel.refreshPosition()
        XCTAssertEqual(panel.presentation, .compact)
        let legacy = FocusPanelPlacement.frame(screenFrame: nonNotchScreen.frame, visibleFrame: nonNotchScreen.visibleFrame,
                                                safeAreaTop: nonNotchScreen.safeAreaInsets.top, size: panel.frame.size)
        XCTAssertEqual(panel.frame.origin.x, legacy.origin.x, accuracy: 1)
        XCTAssertEqual(panel.frame.origin.y, legacy.origin.y, accuracy: 1)
        activeScreen.screen = notchScreen
        panel.refreshPosition()
        XCTAssertEqual(panel.frame.maxY, notchScreen.frame.maxY, accuracy: 1, "Zurück auf dem Notch-Display dockt das Panel neu an")
        XCTAssertEqual(controller.session, initialSession, "Drag darf den Timerzustand nicht verändern")
        XCTAssertEqual(controller.settings, initialSettings, "Drag darf Einstellungen nicht verändern")
    }

    func testLargeNotchViewConnectsToAnchor() throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first(where: { candidate in
            NotchGeometry.detect(screenFrame: candidate.frame, safeAreaTop: candidate.safeAreaInsets.top,
                                 leftArea: candidate.auxiliaryTopLeftArea, rightArea: candidate.auxiliaryTopRightArea) != nil
        }) else { throw XCTSkip("Der Test benötigt ein echtes NSScreen-Display mit Notch") }
        let notch = try XCTUnwrap(NotchGeometry.detect(screenFrame: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
                                                       leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea))
        let suiteName = "FocusPanelTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let controller = FocusController(store: FocusStore(defaults: defaults))
        let panel = FocusPanel(controller: controller, applicationScreen: { screen })
        defer { panel.orderOut(nil); defaults.removePersistentDomain(forName: suiteName) }
        panel.makeKeyAndOrderFront(nil)
        panel.contentView?.layoutSubtreeIfNeeded()

        let compactExpand = try XCTUnwrap(descendantViews(of: panel.contentView).compactMap { $0 as? NSButton }.first)
        compactExpand.performClick(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        panel.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(panel.presentation, .timer)
        XCTAssertEqual(panel.frame.maxY, screen.frame.maxY, accuracy: 1, "Die große Timeransicht muss an der Hardwarekante bleiben")
        XCTAssertEqual(panel.frame.midX, notch.cutoutFrame.midX, accuracy: 1, "Die Timeransicht muss an der gemessenen Notchmitte zentriert sein")
        XCTAssertLessThan(panel.frame.height, 250, "Die Timeransicht darf keinen großen leeren Bedienungsbereich enthalten")
        print("N4 measured screen=\(screen.frame) notch=\(notch.cutoutFrame) timerPanel=\(panel.frame)")
        let visibleText = try recognizedText(in: XCTUnwrap(panel.contentView)).map(\.text).joined(separator: " ")
        let seconds = Int(controller.session.remaining(now: controller.now).rounded(.up))
        let timerValue = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        XCTAssertTrue(visibleText.contains(timerValue),
                      "Der echte gerenderte Timerwert muss sichtbar sein: \(visibleText)")
        XCTAssertTrue(visibleText.contains("Controls"), "Die Timeransicht muss den Bedienungsbutton sichtbar zeigen")
        let content = try XCTUnwrap(panel.contentView)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(content.bounds.width * 2), pixelsHigh: Int(content.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = content.bounds.size
        content.cacheDisplay(in: content.bounds, to: bitmap)
        try assertNotchBridgePainted(in: panel, content: content, notch: notch, bitmap: bitmap)
        let timerHandle = try XCTUnwrap(descendantViews(of: panel.contentView).first { $0.identifier?.rawValue == "panel-drag-handle" })
        XCTAssertFalse(panel.convertToScreen(timerHandle.convert(timerHandle.bounds, to: nil)).intersects(notch.cutoutFrame))

        let controls = try XCTUnwrap(descendantViews(of: panel.contentView).compactMap { $0 as? NSButton }.first { $0.title == "Controls" },
                                     "Timeransicht muss eine echte Bedienungsschaltfläche haben")
        let timerHeight = panel.frame.height
        controls.performClick(nil)
        for _ in 0..<4 {
            panel.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        }
        XCTAssertEqual(panel.presentation, .controls)
        XCTAssertGreaterThan(panel.frame.height, timerHeight + 100, "Die angeschlossene Bedienungskarte muss auf ihre gemessene Höhe wachsen")
        XCTAssertEqual(panel.frame.maxY, screen.frame.maxY, accuracy: 1)
        let controlsScroll = try XCTUnwrap(descendantViews(of: panel.contentView).compactMap { $0 as? NSScrollView }.first)
        XCTAssertLessThanOrEqual(controlsScroll.documentView?.frame.height ?? .infinity, controlsScroll.contentSize.height,
                                 "Die vollständige Karte soll auf diesem Display ohne Scrollen passen")
        let controlsHeight = panel.frame.height
        let menu = makeSettingsMenu(controller)
        defer { menu.orderOut(nil) }
        let closedMenuHeight = menu.frame.height
        try settingsMenuButton("Show settings", in: menu).performClick(nil)
        settleSettingsMenu(menu)
        let settingsContents = try recognizedText(in: XCTUnwrap(menu.contentView)).map(\.text).joined(separator: " ")
        XCTAssertTrue(settingsContents.contains("Notifications"), "Der echte Menüklick zeigt das Formular: \(settingsContents)")
        XCTAssertGreaterThan(menu.frame.height, closedMenuHeight + 100)
        XCTAssertEqual(panel.frame.height, controlsHeight, accuracy: 1, "Menüeinstellungen verändern die Timerkarte nicht")
        XCTAssertEqual(panel.frame.maxY, screen.frame.maxY, accuracy: 1)
        panel.makeKeyAndOrderFront(nil)

        let back = try XCTUnwrap(descendantViews(of: panel.contentView).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Collapse" })
        back.performClick(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        XCTAssertEqual(panel.presentation, .timer, "Bedienung muss zurück zum Timer führen")
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                    windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        NSApp.sendEvent(escape)
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        XCTAssertEqual(panel.presentation, .compact, "Escape auf dem Timer muss zur kompakten Leiste zurückführen")

        let legacyPanel = FocusPanel(controller: controller, screenFrame: CGRect(x: 0, y: 0, width: 800, height: 800))
        defer { legacyPanel.orderOut(nil) }
        legacyPanel.makeKeyAndOrderFront(nil)
        legacyPanel.setExpanded(true)
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        let legacyContent = try XCTUnwrap(legacyPanel.contentView)
        let legacyBitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(legacyContent.bounds.width * 2), pixelsHigh: Int(legacyContent.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        legacyBitmap.size = legacyContent.bounds.size
        legacyContent.cacheDisplay(in: legacyContent.bounds, to: legacyBitmap)
        let legacyCorner = try XCTUnwrap(legacyBitmap.colorAt(x: 10, y: Int(legacyPanel.frame.height * 2) - 2))
        XCTAssertLessThan(legacyCorner.alphaComponent, 0.1, "Das Nicht-Notch-Panel muss seine transparenten Legacy-Ränder behalten")
    }

    func testLateControlsMeasurementCannotResizeNotchTimer() throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first(where: { candidate in
            NotchGeometry.detect(screenFrame: candidate.frame, safeAreaTop: candidate.safeAreaInsets.top,
                                 leftArea: candidate.auxiliaryTopLeftArea, rightArea: candidate.auxiliaryTopRightArea) != nil
        }) else { throw XCTSkip("Der Race-Test benötigt ein echtes NSScreen-Display mit Notch") }
        let suiteName = "FocusPanelTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let panel = FocusPanel(controller: FocusController(store: FocusStore(defaults: defaults)), applicationScreen: { screen })
        defer { panel.orderOut(nil); defaults.removePersistentDomain(forName: suiteName) }
        func settle() {
            for _ in 0..<4 {
                panel.contentView?.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
            }
        }
        func button(_ label: String) throws -> NSButton {
            try XCTUnwrap(descendantViews(of: panel.contentView).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == label },
                          "Der native \(label)-Button muss vorhanden sein")
        }

        panel.makeKeyAndOrderFront(nil)
        settle()
        try button("Open timer view").performClick(nil)
        settle()
        XCTAssertEqual(panel.presentation, .timer)
        try button("Controls").performClick(nil)
        settle()
        XCTAssertEqual(panel.presentation, .controls)
        try button("Collapse").performClick(nil)
        settle()
        XCTAssertEqual(panel.presentation, .timer)
        let expectedTimerHeight = panel.frame.height

        panel.updateExpandedContentSize(CGSize(width: 360, height: 700))
        settle()
        XCTAssertEqual(panel.presentation, .timer)
        XCTAssertEqual(panel.frame.height, expectedTimerHeight, accuracy: 1,
                       "Ein nachlaufender Controls-Messwert darf die Timerhöhe nicht ersetzen")
    }

    func testCompactNotchControlsAvoidCameraArea() throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first(where: { candidate in
            NotchGeometry.detect(screenFrame: candidate.frame, safeAreaTop: candidate.safeAreaInsets.top,
                                 leftArea: candidate.auxiliaryTopLeftArea, rightArea: candidate.auxiliaryTopRightArea) != nil
        }) else { throw XCTSkip("Der Test benötigt ein echtes NSScreen-Display mit Notch") }
        let notch = try XCTUnwrap(NotchGeometry.detect(screenFrame: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
                                                       leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea))
        let suiteName = "FocusPanelTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let panel = FocusPanel(controller: FocusController(store: FocusStore(defaults: defaults)),
                               applicationScreen: { screen })
        defer { panel.orderOut(nil); defaults.removePersistentDomain(forName: suiteName) }
        panel.makeKeyAndOrderFront(nil)
        panel.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        panel.contentView?.layoutSubtreeIfNeeded()

        print("N3 measured screen=\(screen.frame) notch=\(notch.cutoutFrame) compactPanel=\(panel.frame)")
        XCTAssertEqual(panel.frame.maxY, screen.frame.maxY, accuracy: 1, "Die Leiste muss an der Hardwareoberkante andocken")
        XCTAssertEqual(panel.frame.midX, notch.cutoutFrame.midX, accuracy: 1, "Die Leiste muss in globalen Koordinaten an der Notchmitte zentriert sein")
        XCTAssertEqual(panel.frame.minX, notch.cutoutFrame.minX, accuracy: 1)
        XCTAssertEqual(panel.frame.maxX, notch.cutoutFrame.maxX, accuracy: 1)
        XCTAssertEqual(panel.frame.height, notch.cutoutFrame.height + 28, accuracy: 1)
        let content = try XCTUnwrap(panel.contentView)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(content.bounds.width * 2), pixelsHigh: Int(content.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = content.bounds.size
        content.cacheDisplay(in: content.bounds, to: bitmap)
        try assertNotchBridgePainted(in: panel, content: content, notch: notch, bitmap: bitmap)
        for x in [2, bitmap.pixelsWide - 3] {
            XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: x, y: Int(notch.cutoutFrame.height * 2) + 2)).alphaComponent, 0.9,
                                 "Die oberen Ecken der Statusleiste schließen bündig an die Notch an")
            XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: x, y: bitmap.pixelsHigh - 3)).alphaComponent, 0.1,
                              "Nur die unteren Ecken sind abgerundet")
        }
        let handle = try XCTUnwrap(descendantViews(of: panel.contentView).first { $0.identifier?.rawValue == "panel-drag-handle" })
        let handleFrame = panel.convertToScreen(handle.convert(handle.bounds, to: nil))
        XCTAssertFalse(handleFrame.intersects(notch.cutoutFrame), "Drag-Hitfläche darf nicht unter der Kamera liegen")
        XCTAssertTrue(handle.isAccessibilityElement())
        XCTAssertEqual(handle.accessibilityLabel(), "Move panel")

        let expand = try XCTUnwrap(descendantViews(of: panel.contentView).compactMap { $0 as? NSButton }.first)
        XCTAssertTrue(expand.isAccessibilityElement())
        XCTAssertEqual(expand.accessibilityLabel(), "Open timer view")
        let expandFrame = panel.convertToScreen(expand.convert(expand.bounds, to: nil))
        XCTAssertFalse(expandFrame.intersects(notch.cutoutFrame), "Expand-Hitfläche darf nicht unter der Kamera liegen")
        let expandPoint = expand.convert(NSPoint(x: expand.bounds.midX, y: expand.bounds.midY), to: nil)
        XCTAssertTrue(panel.contentView?.hitTest(expandPoint) === expand, "Der zugängliche Expand-Button muss selbst getroffen werden")
        expand.performClick(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        XCTAssertEqual(panel.presentation, .timer, "Expand muss compact über PanelPresentation zum Timer führen")
        panel.cancelOperation(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        settlePanel(panel)
        XCTAssertEqual(panel.frame.width, notch.cutoutFrame.width, accuracy: 1, "Einklappen stellt die schmale Leiste wieder her")
        XCTAssertEqual(panel.frame.height, notch.cutoutFrame.height + 28, accuracy: 1)
    }

    func testDragHandleMovesPanel() throws {
        _ = NSApplication.shared
        let suiteName = "FocusPanelTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let panel = FocusPanel(controller: FocusController(store: FocusStore(defaults: defaults)),
                               screenFrame: CGRect(x: 0, y: 0, width: 800, height: 800), screenID: 41)
        defer { panel.orderOut(nil); defaults.removePersistentDomain(forName: suiteName) }
        panel.makeKeyAndOrderFront(nil)
        panel.contentView?.layoutSubtreeIfNeeded()
        let handle = try XCTUnwrap(descendantViews(of: panel.contentView).first { $0.identifier?.rawValue == "panel-drag-handle" },
                                   "Der echte kompakte Panel-Drag-Handle muss gerendert sein")
        XCTAssertTrue(handle.isAccessibilityElement())
        let start = panel.frame
        let locationInWindow = handle.convert(NSPoint(x: handle.bounds.midX, y: handle.bounds.midY), to: nil)
        XCTAssertTrue(panel.contentView?.hitTest(locationInWindow) === handle, "Die grüne Punktmitte muss vom nativen Handle getroffen werden")
        let location = panel.convertPoint(toScreen: locationInWindow)
        let down = try mouseEvent(.leftMouseDown, atScreen: location, in: panel)
        NSApp.sendEvent(down)
        NSApp.sendEvent(try mouseEvent(.leftMouseDragged, atScreen: NSPoint(x: location.x + 75, y: location.y - 30), in: panel))
        NSApp.sendEvent(try mouseEvent(.leftMouseDragged, atScreen: NSPoint(x: location.x + 80, y: location.y - 30), in: panel))
        NSApp.sendEvent(try mouseEvent(.leftMouseUp, atScreen: NSPoint(x: location.x + 80, y: location.y - 30), in: panel))
        XCTAssertEqual(panel.frame.origin.x, start.origin.x + 80, accuracy: 1)
        XCTAssertEqual(panel.frame.origin.y, start.origin.y - 30, accuracy: 1)
        XCTAssertEqual(panel.frame.size, start.size)

        panel.refreshPosition(screenFrame: CGRect(x: 0, y: 0, width: 800, height: 800))
        XCTAssertEqual(panel.frame.origin.x, start.origin.x + 80, accuracy: 1)
        XCTAssertEqual(panel.frame.origin.y, start.origin.y - 30, accuracy: 1)
        let manualTop = panel.frame.maxY
        panel.updateContentSize(CGSize(width: 360, height: 320))
        let arrow = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: panel.windowNumber, context: nil, characters: "→", charactersIgnoringModifiers: "→", isARepeat: false, keyCode: 124))
        panel.sendEvent(arrow)
        XCTAssertTrue(panel.firstResponder === handle)
        XCTAssertEqual(panel.frame.origin.x, start.origin.x + 90, accuracy: 1)
        XCTAssertEqual(panel.frame.midX, start.midX + 90, accuracy: 1)
        XCTAssertEqual(panel.frame.maxY, manualTop, accuracy: 1)

        panel.setExpanded(false)
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        let timerArea = NSPoint(x: panel.frame.width / 2, y: panel.frame.height / 2)
        let timerScreenPoint = panel.convertPoint(toScreen: timerArea)
        let click = try mouseEvent(.leftMouseDown, atScreen: timerScreenPoint, in: panel)
        let release = try mouseEvent(.leftMouseUp, atScreen: timerScreenPoint, in: panel)
        NSApp.postEvent(release, atStart: false)
        NSApp.sendEvent(click)
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        XCTAssertGreaterThan(panel.frame.height, 64)
    }

    func testRefreshFollowsActiveApplicationScreenAfterPanelDrag() throws {
        _ = NSApplication.shared
        let screens = NSScreen.screens
        guard screens.count >= 2 else { throw XCTSkip("Monitorwechsel benötigt zwei echte NSScreen-Displays") }
        let screenA = screens[0]
        let screenB = screens[1]
        let activeScreen = PanelTestScreenSelection(screenA)
        let suiteName = "FocusPanelTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let panel = FocusPanel(controller: FocusController(store: FocusStore(defaults: defaults)),
                               applicationScreen: { activeScreen.screen })
        defer { panel.orderOut(nil); defaults.removePersistentDomain(forName: suiteName) }
        panel.makeKeyAndOrderFront(nil)
        panel.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        XCTAssertEqual(displayID(panel.screen), displayID(screenA))

        let handle = try XCTUnwrap(descendantViews(of: panel.contentView).first { $0.identifier?.rawValue == "panel-drag-handle" })
        let pointInWindow = handle.convert(NSPoint(x: handle.bounds.midX, y: handle.bounds.midY), to: nil)
        let pointer = panel.convertPoint(toScreen: pointInWindow)
        NSApp.sendEvent(try mouseEvent(.leftMouseDown, atScreen: pointer, in: panel))
        NSApp.sendEvent(try mouseEvent(.leftMouseDragged, atScreen: NSPoint(x: pointer.x + 25, y: pointer.y - 15), in: panel))
        NSApp.sendEvent(try mouseEvent(.leftMouseUp, atScreen: NSPoint(x: pointer.x + 25, y: pointer.y - 15), in: panel))
        XCTAssertEqual(panel.frame.origin.x, FocusPanelPlacement.frame(screenFrame: screenA.frame, visibleFrame: screenA.visibleFrame,
                                                                        safeAreaTop: screenA.safeAreaInsets.top, size: panel.frame.size).origin.x + 25,
                       accuracy: 1)

        activeScreen.screen = screenB
        panel.refreshPosition()
        if let notch = NotchGeometry.detect(screenFrame: screenB.frame, safeAreaTop: screenB.safeAreaInsets.top,
                                            leftArea: screenB.auxiliaryTopLeftArea, rightArea: screenB.auxiliaryTopRightArea) {
            XCTAssertEqual(panel.frame.maxY, screenB.frame.maxY, accuracy: 1)
            XCTAssertEqual(panel.frame.midX, notch.cutoutFrame.midX, accuracy: 1)
        } else {
            let expected = FocusPanelPlacement.frame(screenFrame: screenB.frame, visibleFrame: screenB.visibleFrame,
                                                     safeAreaTop: screenB.safeAreaInsets.top, size: panel.frame.size)
            XCTAssertEqual(panel.frame.origin.x, expected.origin.x, accuracy: 1)
            XCTAssertEqual(panel.frame.origin.y, expected.origin.y, accuracy: 1)
        }
        XCTAssertEqual(displayID(panel.screen), displayID(screenB))
    }

    private func mouseEvent(_ type: NSEvent.EventType, atScreen point: NSPoint, in panel: NSPanel) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: panel.convertPoint(fromScreen: point), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }

    private func settlePanel(_ panel: NSPanel) {
        for _ in 0..<4 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            panel.contentView?.layoutSubtreeIfNeeded()
        }
    }

    private func displayID(_ screen: NSScreen?) -> UInt32? {
        (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    func testOversizedContentRemainsReachable() throws {
        _ = NSApplication.shared
        let panel = FocusPanel(controller: FocusController(), screenFrame: CGRect(x: 0, y: 0, width: 800, height: 200))
        panel.setExpanded(true)
        defer { panel.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        panel.contentView?.layoutSubtreeIfNeeded()

        let scrollView = try XCTUnwrap(descendantViews(of: panel.contentView).compactMap { $0 as? NSScrollView }.first)
        XCTAssertEqual(panel.frame.height, 200, accuracy: 1)
        XCTAssertGreaterThan(scrollView.documentView?.frame.height ?? 0, scrollView.contentSize.height)
        XCTAssertGreaterThan(scrollView.documentView?.frame.height ?? 0, panel.frame.height)
        XCTAssertTrue(scrollView.hasVerticalScroller)
        XCTAssertEqual(panel.frame.maxY, 200, accuracy: 1)
        let documentView = try XCTUnwrap(scrollView.documentView)
        let beforeScroll = try recognizedText(in: scrollView.contentView)
        XCTAssertFalse(beforeScroll.contains { $0.text.contains("Short break") },
                       "Kurze Pause darf vor dem Scrollen nicht im sichtbaren Viewport erscheinen")
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: documentView.frame.height - scrollView.contentSize.height))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        XCTAssertGreaterThan(scrollView.contentView.bounds.origin.y, 0)
        XCTAssertGreaterThanOrEqual(documentView.visibleRect.maxY, documentView.bounds.maxY - 1,
                                    "Der sichtbare Clip muss nach dem Scrollen das Dokumentende erreichen")
        let afterScroll = try XCTUnwrap(try recognizedText(in: scrollView.contentView).first { $0.text.contains("Short break") },
                                        "Kurze Pause muss nach dem Scrollen sichtbar sein")
        XCTAssertGreaterThan(afterScroll.frame.minX, 0)
        XCTAssertGreaterThan(afterScroll.frame.minY, 0)
        XCTAssertLessThan(afterScroll.frame.maxX, 1)
        XCTAssertLessThan(afterScroll.frame.maxY, 1,
                           "Der Kurze Pause-Text muss vollständig im sichtbaren Viewport liegen")
    }

    func testClippedHeightMeasurementReplacesStaleNaturalHeight() {
        _ = NSApplication.shared
        let panel = FocusPanel(controller: FocusController(), screenFrame: CGRect(x: 0, y: 0, width: 800, height: 540))
        panel.setExpanded(true)
        defer { panel.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        panel.contentView = nil
        panel.updateExpandedContentSize(CGSize(width: 360, height: 640))
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        XCTAssertEqual(panel.frame.height, 540, accuracy: 1)

        panel.updateExpandedContentSize(CGSize(width: 360, height: 64))
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        XCTAssertEqual(panel.frame.height, 540, accuracy: 1)

        panel.updateExpandedContentSize(CGSize(width: 360, height: 540))
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        XCTAssertEqual(panel.frame.height, 540, accuracy: 1)

        panel.refreshPosition(screenFrame: CGRect(x: 0, y: 0, width: 800, height: 800))
        XCTAssertEqual(panel.frame.height, 540, accuracy: 1)
    }

    func testPanelUsesMeasuredContentHeightAndKeepsItsTopEdgeInPlace() {
        _ = NSApplication.shared
        let panel = FocusPanel(controller: FocusController())
        let topEdge = panel.frame.maxY
        panel.contentView = nil // Isolate the panel's measured-size resize path from SwiftUI's initial compact measurement.

        panel.updateContentSize(CGSize(width: 360, height: 320))

        XCTAssertEqual(panel.frame.width, 360)
        XCTAssertEqual(panel.frame.height, 320)
        XCTAssertEqual(panel.frame.maxY, topEdge)
    }

    func testExpandedPanelUsesNaturalCardHeight() {
        _ = NSApplication.shared
        let panel = FocusPanel(controller: FocusController())
        panel.setExpanded(true)
        defer { panel.orderOut(nil) }
        for _ in 0..<3 {
            panel.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        }

        XCTAssertGreaterThan(panel.frame.height, 200)
        XCTAssertNotEqual(panel.frame.height, 420, accuracy: 1)
    }

    func testSettingsGrowMenuWithoutResizingPanel() throws {
        _ = NSApplication.shared
        let suiteName = "FocusPanelSettingsTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let controller = FocusController(store: FocusStore(defaults: defaults))
        let panel = FocusPanel(controller: controller, screenFrame: CGRect(x: 0, y: 0, width: 800, height: 900), applicationScreen: { nil })
        panel.setExpanded(true)
        let menu = makeSettingsMenu(controller)
        defer { menu.orderOut(nil); panel.orderOut(nil); defaults.removePersistentDomain(forName: suiteName) }
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        let panelFrame = panel.frame
        let topEdge = menu.frame.maxY
        let collapsedHeight = menu.frame.height
        try settingsMenuButton("Show settings", in: menu).performClick(nil)
        settleSettingsMenu(menu)
        XCTAssertGreaterThan(menu.frame.height, collapsedHeight + 100)
        XCTAssertEqual(menu.frame.maxY, topEdge, accuracy: 1)
        XCTAssertEqual(menu.contentView?.frame.height ?? 0, menu.frame.height, accuracy: 1)
        XCTAssertEqual(menu.contentView?.fittingSize.height ?? 0, menu.frame.height, accuracy: 1)
        XCTAssertEqual(panel.frame, panelFrame)
        let visible = try recognizedText(in: XCTUnwrap(menu.contentView))
        for label in ["Notifications", "Save", "Quit"] {
            let text = try XCTUnwrap(visible.first { $0.text.contains(label) })
            XCTAssertGreaterThan(text.frame.minY, 0)
            XCTAssertLessThan(text.frame.maxY, 1, "Formular und Fußzeile müssen vollständig erreichbar bleiben")
        }
        XCTAssertEqual(descendantViews(of: menu.contentView).compactMap { $0 as? NSTextField }.filter { $0.isEditable }.count, 4)
        try settingsMenuButton("Hide settings", in: menu).performClick(nil)
        settleSettingsMenu(menu)
        XCTAssertEqual(menu.frame.height, collapsedHeight, accuracy: 1)
        XCTAssertEqual(menu.frame.maxY, topEdge, accuracy: 1)
        XCTAssertEqual(panel.frame, panelFrame)
        panel.setExpanded(false)
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        XCTAssertEqual(panel.frame.height, 64, accuracy: 1)
    }

    private func assertNotchBridgePainted(in panel: NSPanel, content: NSView, notch: NotchGeometry,
                                          bitmap: NSBitmapImageRep, file: StaticString = #filePath, line: UInt = #line) throws {
        let bridge = content.convert(panel.convertFromScreen(notch.cutoutFrame), from: nil)
        let scale: CGFloat = 2
        let joinY = content.isFlipped ? bridge.maxY : content.bounds.maxY - bridge.minY
        let bridgeX = Int((bridge.maxX - content.bounds.minX - 2) * scale)
        let centerX = Int((bridge.midX - content.bounds.minX) * scale)
        let toRasterY: (CGFloat) -> Int = { y in
            Int((content.isFlipped ? y - content.bounds.minY : content.bounds.maxY - y) * scale)
        }
        let bridgeInsideY = toRasterY(bridge.midY)
        let boundaryY = Int(joinY * scale)
        XCTAssertGreaterThan(bridge.width, 0, file: file, line: line)
        for (x, y) in [(bridgeX, boundaryY - 2), (bridgeX, boundaryY + 2), (centerX, bridgeInsideY)] {
            let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y), file: file, line: line)
            XCTAssertGreaterThan(color.alphaComponent, 0.9, "Bridge, its inner area, and adjoining body must be painted", file: file, line: line)
            XCTAssertLessThan(color.redComponent, 0.1, "The notch bridge and joined body must be black", file: file, line: line)
            XCTAssertLessThan(color.greenComponent, 0.1, file: file, line: line)
            XCTAssertLessThan(color.blueComponent, 0.1, file: file, line: line)
        }
        let outsideX = Int((bridge.minX - content.bounds.minX - 2) * scale)
        if outsideX >= 0 {
            let outside = try XCTUnwrap(bitmap.colorAt(x: outsideX, y: bridgeInsideY), file: file, line: line)
            XCTAssertLessThan(outside.alphaComponent, 0.1, "Pixels beside the measured bridge remain transparent", file: file, line: line)
        }
    }

    func testHeightTracksContent() {
        _ = NSApplication.shared
        let panel = FocusPanel(controller: FocusController())
        panel.setExpanded(true)
        defer { panel.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        let topEdge = panel.frame.maxY
        panel.contentView = nil // Keep the real Card measurement from overriding these two explicit resize inputs.

        panel.updateExpandedContentSize(CGSize(width: 360, height: 320))
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        XCTAssertEqual(panel.frame.height, 320, accuracy: 1)
        XCTAssertEqual(panel.frame.maxY, topEdge, accuracy: 1)

        panel.updateExpandedContentSize(CGSize(width: 360, height: 540))
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        XCTAssertEqual(panel.frame.height, 540, accuracy: 1)
        XCTAssertEqual(panel.frame.maxY, topEdge, accuracy: 1)
    }

    func testExpandedSwiftUIContentDoesNotCollapseThePanelViewport() {
        _ = NSApplication.shared
        let panel = FocusPanel(controller: FocusController())
        panel.setExpanded(true)
        defer { panel.orderOut(nil) }
        panel.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        panel.contentView?.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(panel.frame.height, 200)
        XCTAssertEqual(panel.contentView?.frame.height ?? 0, panel.frame.height, accuracy: 1)
    }

    func testEscapeKeyEventCollapsesExpandedPanel() throws {
        _ = NSApplication.shared
        let panel = FocusPanel(controller: FocusController())
        panel.setExpanded(true)
        defer { panel.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))
        XCTAssertGreaterThan(panel.frame.height, 200)

        let escape = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ))
        NSApp.sendEvent(escape)
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.12))

        XCTAssertEqual(panel.frame.height, 64, accuracy: 1)
    }

    func testNotchStatusShowsRunningSoonDonePausedAndDone() throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first(where: { candidate in
            NotchGeometry.detect(screenFrame: candidate.frame, safeAreaTop: candidate.safeAreaInsets.top,
                                 leftArea: candidate.auxiliaryTopLeftArea, rightArea: candidate.auxiliaryTopRightArea) != nil
        }) else { throw XCTSkip("N3b-Notchstatus benötigt ein echtes NSScreen-Display mit Notch") }
        let suiteName = "FocusPanelTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let clock = PanelTestClock(start)
        let controller = FocusController(store: FocusStore(defaults: defaults), now: { clock.date })
        let compact = FocusPanel(controller: controller, applicationScreen: { screen })
        let timer = FocusPanel(controller: controller, applicationScreen: { screen })
        defer { compact.orderOut(nil); timer.orderOut(nil); defaults.removePersistentDomain(forName: suiteName) }
        compact.orderFrontRegardless()
        timer.makeKeyAndOrderFront(nil)
        timer.setExpanded(true)
        settlePanel(compact)
        settlePanel(timer)
        XCTAssertEqual(compact.presentation, .compact)
        XCTAssertEqual(timer.presentation, .timer)

        // Checks the real AX value of the notch drag handle and the OCR of the rendered panel, in both notch views.
        func assertStatus(_ status: String, _ time: String, visible keyword: String, line: UInt = #line) throws {
            for panel in [compact, timer] {
                settlePanel(panel)
                let handle = try XCTUnwrap(descendantViews(of: panel.contentView).first { $0.identifier?.rawValue == "panel-drag-handle" }, line: line)
                XCTAssertEqual(handle.accessibilityValue() as? String, "\(status) · \(time)", "AX in \(panel.presentation)", line: line)
                let visible = try recognizedText(in: XCTUnwrap(panel.contentView)).map(\.text).joined(separator: " ")
                print("N3b \(panel.presentation) AX=\(handle.accessibilityValue() ?? "nil") OCR=\(visible)")
                XCTAssertTrue(visible.contains(keyword), "Sichtbar in \(panel.presentation) fehlt \(keyword): \(visible)", line: line)
                XCTAssertTrue(visible.contains(time), "Sichtbar in \(panel.presentation) fehlt \(time): \(visible)", line: line)
            }
        }

        let duration = controller.settings.focusDuration
        controller.start(kind: .focus)
        try assertStatus("Focus running", "25:00", visible: "Focus")
        clock.date = start.addingTimeInterval(duration - 61)
        controller.tick()
        try assertStatus("Focus running", "01:01", visible: "Focus") // > 60 s left: still running
        clock.date = start.addingTimeInterval(duration - 60)
        controller.tick()
        try assertStatus("Focus almost done", "01:00", visible: "almost done") // exactly 60 s left: soon done

        controller.pause()
        try assertStatus("Focus paused", "01:00", visible: "paused")
        clock.date = clock.date.addingTimeInterval(300)
        controller.tick()
        try assertStatus("Focus paused", "01:00", visible: "paused") // paused stays paused, even in the last minute
        controller.resume()
        try assertStatus("Focus almost done", "01:00", visible: "almost done")

        clock.date = try XCTUnwrap(controller.session.targetEnd)
        controller.tick()
        XCTAssertTrue(controller.session.didFullyElapse, "Natürlicher Abschluss über tick")
        try assertStatus("Focus complete", "00:00", visible: "complete")

        controller.start(kind: .focus, taskName: String(repeating: "Sehr lange Aufgabe ", count: 8))
        try assertStatus("Focus running", "25:00", visible: "25:00") // task name stays out of the short notch status

        controller.setLanguage(.german)
        controller.finish()
        try assertStatus("Fokus abgeschlossen", "00:00", visible: "Fokus abgeschlossen")
        let content = try XCTUnwrap(compact.contentView)
        let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/notch-compact.png"))

        for (kind, status) in [(FocusSession.Kind.shortBreak, "Kurze Pause abgeschlossen"), (.longBreak, "Lange Pause abgeschlossen")] {
            controller.start(kind: kind)
            controller.finish()
            try assertStatus(status, "00:00", visible: status)
        }
    }

    func testCachedScreenMustStillBeAvailable() throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first else { throw XCTSkip("Kein NSScreen vorhanden") }
        func id(_ s: NSScreen?) -> UInt32? { (s?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }

        // Display still present: the current NSScreen with that ID is returned.
        let present = resolvedCachedScreen(screen, in: NSScreen.screens)
        XCTAssertNotNil(id(screen))
        XCTAssertEqual(id(present), id(screen))
        // Display removed (simulated by an empty available set): cache is discarded.
        XCTAssertNil(resolvedCachedScreen(screen, in: []))
        // No cache: nothing to resolve.
        XCTAssertNil(resolvedCachedScreen(nil, in: NSScreen.screens))
        // With a second display, a set that lacks the cached display discards it too.
        if let other = NSScreen.screens.first(where: { id($0) != id(screen) }) {
            XCTAssertNil(resolvedCachedScreen(screen, in: [other]))
        }
    }
}

@MainActor
private final class PanelTestScreenSelection {
    var screen: NSScreen?
    init(_ screen: NSScreen?) { self.screen = screen }
}

private final class PanelTestClock: @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
}

import AppKit
import FocusCore
import SwiftUI
import XCTest
@testable import OpenFocusIsland

@MainActor
final class FocusHistoryWindowTests: XCTestCase {
    func testOpeningMiniaturizedHistoryRestoresTheSameWindow() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let delegate = AppDelegate(controller: fixture.controller)
        let window = delegate.showHistory()
        defer { window.close() }
        settle(window)
        window.miniaturize(nil)
        settle(window)
        XCTAssertTrue(window.isMiniaturized)
        XCTAssertTrue(delegate.showHistory() === window)
        settle(window)
        XCTAssertFalse(window.isMiniaturized)
        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(window.canBecomeKey)
    }

    func testMenuIconAndItsEdgeOpenTheSameIndependentWindow() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let delegate = AppDelegate(controller: fixture.controller)
        let menu = makeMenu(fixture.controller, delegate: delegate)
        defer { menu.close() }
        settle(menu)
        let icon = try historyButton(in: menu, label: "Show history")
        XCTAssertGreaterThanOrEqual(icon.bounds.width, 36)
        XCTAssertGreaterThanOrEqual(icon.bounds.height, 36)
        XCTAssertEqual(icon.toolTip, "Show history")
        let bounds = icon.convert(icon.bounds, to: nil)
        XCTAssertEqual(bounds.maxX, menu.contentView!.bounds.width - 12, accuracy: 1)
        try click(NSPoint(x: bounds.midX, y: bounds.midY), in: menu)
        let window = try XCTUnwrap(NSApp.windows.compactMap { $0 as? FocusHistoryWindow }.first { $0.isVisible })
        defer { window.close() }
        XCTAssertTrue(window.isVisible)
        menu.orderOut(nil)
        XCTAssertTrue(window.isVisible, "History must remain open independently of the menu")
        window.orderOut(nil)
        menu.makeKeyAndOrderFront(nil)
        try click(NSPoint(x: bounds.minX + 2, y: bounds.minY + 2), in: menu)
        XCTAssertTrue(window.isVisible, "Clicking the invisible edge padding must reopen history")
        XCTAssertTrue(delegate.showHistory() === window)
        try snapshot(menu, name: "menu-history-access")
    }

    func testWindowIsReusedAfterCloseAndDoesNotChangeSessionOrStoredData() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.controller.start(kind: .focus, taskName: "Keep running")
        let session = fixture.controller.session
        let stored = fixture.defaults.persistentDomain(forName: fixture.suite) ?? [:]
        let policy = NSApp.activationPolicy()
        let delegate = AppDelegate(controller: fixture.controller)
        let window = delegate.showHistory()
        defer { window.close() }
        settle(window)
        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(window.styleMask.contains([.titled, .closable, .resizable]))
        XCTAssertTrue(window.canBecomeMain)
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertGreaterThanOrEqual(window.minSize.width, 360)
        XCTAssertGreaterThanOrEqual(window.minSize.height, 260)
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(delegate.showHistory() === window)
        window.close()
        XCTAssertFalse(window.isVisible)
        XCTAssertTrue(delegate.showHistory() === window)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(fixture.controller.session, session)
        XCTAssertEqual(NSDictionary(dictionary: fixture.defaults.persistentDomain(forName: fixture.suite) ?? [:]), NSDictionary(dictionary: stored))
        XCTAssertEqual(NSApp.activationPolicy(), policy)
    }

    func testEmptyHistoryAndLanguageChangesUpdateWindowTitleMenuLabelAndTooltip() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let delegate = AppDelegate(controller: fixture.controller)
        let menu = makeMenu(fixture.controller, delegate: delegate)
        let window = delegate.showHistory()
        defer { menu.close(); window.close() }
        settle(window)
        settle(menu)
        XCTAssertEqual(window.title, "History")
        XCTAssertTrue(try rendered(window).contains("No completed focus sessions yet."))
        let englishButton = try historyButton(in: menu, label: "Show history")
        XCTAssertEqual(englishButton.toolTip, "Show history")
        try snapshot(window, name: "history-empty-en")
        fixture.controller.setLanguage(.german)
        settle(window)
        settle(menu)
        XCTAssertEqual(window.title, "Verlauf")
        XCTAssertTrue(try rendered(window).contains("Noch keine abgeschlossenen Fokuszeiten."))
        let germanButton = try historyButton(in: menu, label: "Verlauf anzeigen")
        XCTAssertEqual(germanButton.toolTip, "Verlauf anzeigen")
        try snapshot(window, name: "history-empty-de")
    }

    func testLongHistoryIsScrollableWithNewestFirstAndCompleteLongTaskName() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let longName = "Newest task with a deliberately long name that wraps across several lines and remains fully readable EndOfName"
        for index in 0..<200 {
            var session = FocusSession()
            let start = fixture.clock.date.addingTimeInterval(Double(index) * 120)
            XCTAssertTrue(session.start(kind: .focus, duration: 60, taskName: index == 199 ? longName : "Task \(index)", at: start))
            XCTAssertTrue(session.reconcile(at: start.addingTimeInterval(60)))
            try fixture.store.recordCompletedFocus(session)
        }
        let controller = FocusController(store: fixture.store, now: { fixture.clock.date })
        let delegate = AppDelegate(controller: controller)
        let window = delegate.showHistory()
        defer { window.close() }
        settle(window)
        let top = try rendered(window)
        XCTAssertTrue(top.contains("Newest task"))
        XCTAssertTrue(top.contains("EndOfName"), "Task names must wrap rather than truncate")
        XCTAssertTrue(top.contains("1 min"))
        XCTAssertTrue(top.contains("2026"), "Each completed task must include its date")
        XCTAssertFalse(top.contains("Task 0"))
        let scroll = try XCTUnwrap(descendantViews(of: window.contentView).compactMap { $0 as? NSScrollView }.first)
        XCTAssertGreaterThan(scroll.documentView?.bounds.height ?? 0, scroll.contentView.bounds.height)
        try snapshot(window, name: "history-long-top-en")
        let document = try XCTUnwrap(scroll.documentView)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: document.isFlipped ? document.bounds.height - scroll.contentView.bounds.height : 0))
        scroll.reflectScrolledClipView(scroll.contentView)
        settle(window)
        XCTAssertTrue(try rendered(window).contains("Task 0"), "The oldest entry must be reachable")
        try snapshot(window, name: "history-long-bottom-en")
        controller.setLanguage(.german)
        settle(window)
        XCTAssertTrue(try rendered(window).contains("1 Min."))
        try snapshot(window, name: "history-long-bottom-de")
    }

    func testNaturalCompletionUpdatesAnAlreadyOpenWindow() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let delegate = AppDelegate(controller: fixture.controller)
        let window = delegate.showHistory()
        defer { window.close() }
        settle(window)
        XCTAssertTrue(try rendered(window).contains("No completed"))
        fixture.controller.start(kind: .focus, taskName: "Live completion")
        fixture.clock.date = fixture.clock.date.addingTimeInterval(60)
        fixture.controller.tick()
        settle(window)
        XCTAssertTrue(try rendered(window).contains("Live completion"))
        XCTAssertFalse(try rendered(window).contains("No completed"))
        XCTAssertEqual(fixture.controller.history.count, 1)
        XCTAssertTrue(delegate.showHistory() === window)
        try snapshot(window, name: "history-live")
    }

    func testCorruptHistoryShowsExistingErrorInsteadOfClaimingItIsEmpty() throws {
        let fixture = try Fixture(corruptHistory: true)
        defer { fixture.cleanUp() }
        let saved = fixture.defaults.data(forKey: "focus.history")
        let delegate = AppDelegate(controller: fixture.controller)
        let window = delegate.showHistory()
        defer { window.close() }
        settle(window)
        XCTAssertNotNil(fixture.controller.error)
        XCTAssertTrue(try rendered(window).contains("History could not be loaded"))
        XCTAssertFalse(try rendered(window).contains("No completed"))
        XCTAssertEqual(fixture.defaults.data(forKey: "focus.history"), saved)
        try snapshot(window, name: "history-load-error")
    }

    private func makeMenu(_ controller: FocusController, delegate: AppDelegate) -> NSPanel {
        let menu = NSPanel(contentRect: CGRect(x: 100, y: 100, width: 340, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        menu.isReleasedWhenClosed = false
        menu.contentView = NSHostingView(rootView: MenuBarControls(controller: controller, onShowHistory: { delegate.showHistory() })
            .fixedSize().background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.dark))
        menu.setContentSize(menu.contentView!.fittingSize)
        menu.makeKeyAndOrderFront(nil)
        return menu
    }

    private func historyButton(in menu: NSWindow, label: String) throws -> NSButton {
        try XCTUnwrap(descendantViews(of: menu.contentView).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == label })
    }

    private func settle(_ window: NSWindow) {
        for _ in 0..<5 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.025))
            window.contentView?.layoutSubtreeIfNeeded()
        }
    }

    private func click(_ point: NSPoint, in window: NSWindow) throws {
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
        }
        NSApp.postEvent(try event(.leftMouseUp), atStart: false)
        NSApp.sendEvent(try event(.leftMouseDown))
        if let up = NSApp.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true) { NSApp.sendEvent(up) }
        settle(window)
    }

    private func rendered(_ window: NSWindow) throws -> String {
        try recognizedText(in: XCTUnwrap(window.contentView)).map(\.text).joined(separator: " ")
    }

    private func snapshot(_ window: NSWindow, name: String) throws {
        let view = try XCTUnwrap(window.contentView)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/ui-split/history")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("\(name).png"))
    }
}

@MainActor
private final class Fixture {
    let suite = "FocusHistoryWindowTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let store: FocusStore
    let clock = HistoryWindowClock()
    let controller: FocusController

    init(corruptHistory: Bool = false) throws {
        _ = NSApplication.shared
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        store = FocusStore(defaults: defaults)
        try store.saveSettings(FocusSettings(focusDuration: 60))
        if corruptHistory { defaults.set(Data("{bad history".utf8), forKey: "focus.history") }
        controller = FocusController(store: store, now: { [clock] in clock.date })
    }

    func cleanUp() { defaults.removePersistentDomain(forName: suite) }
}

@MainActor
private final class HistoryWindowClock {
    var date = Date(timeIntervalSinceReferenceDate: 800_000_000)
}

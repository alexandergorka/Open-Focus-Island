import AppKit
import FocusCore
import XCTest
@testable import OpenFocusIsland

@MainActor
final class FocusPanelAnimationTests: XCTestCase {
    func testCollapseKeepsOutgoingCanvasUntilAnimationEnds() throws {
        let panel = try makePanel()
        defer { panel.orderOut(nil) }
        panel.contentView = nil
        panel.updateContentSize(CGSize(width: 360, height: 400))
        let expandedFrame = panel.frame

        panel.updateContentSize(CGSize(width: 360, height: 64), animated: true)
        XCTAssertEqual(panel.frame, expandedFrame, "The shrinking view must not be clipped by its native window")
        panel.refreshPosition()
        XCTAssertEqual(panel.frame, expandedFrame, "The timer's position refresh must not interrupt the transition")
        settle(panel)
        XCTAssertEqual(panel.frame.height, 64)
        XCTAssertEqual(panel.frame.maxY, expandedFrame.maxY)
        XCTAssertEqual(panel.frame.midX, expandedFrame.midX)
    }

    func testRapidReversalCancelsOldResizeCompletion() throws {
        let panel = try makePanel()
        defer { panel.orderOut(nil) }
        panel.contentView = nil
        panel.updateContentSize(CGSize(width: 360, height: 400))
        panel.updateContentSize(CGSize(width: 360, height: 64), animated: true)
        panel.updateContentSize(CGSize(width: 360, height: 300), animated: true)
        settle(panel)
        XCTAssertEqual(panel.frame.height, 300, "A previous collapse must not overwrite the latest size")
        panel.updateContentSize(CGSize(width: 360, height: 64), animated: true)
        panel.refreshPosition(screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 600))
        settle(panel)
        XCTAssertEqual(panel.frame.height, 64)
        XCTAssertEqual(panel.frame.maxY, 600, "Display changes must cancel the old window target")
    }

    func testReduceMotionResizesImmediately() throws {
        let panel = try makePanel(reduceMotion: true)
        defer { panel.orderOut(nil) }
        panel.contentView = nil
        panel.updateContentSize(CGSize(width: 360, height: 400))
        panel.updateContentSize(CGSize(width: 360, height: 64), animated: true)
        XCTAssertEqual(panel.frame.height, 64)
        settle(panel)
        XCTAssertEqual(panel.frame.height, 64)
    }

    func testRenderedExpansionCollapseAndSettingsRemainUsable() throws {
        let suite = "FocusPanelAnimationMenuTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let controller = FocusController(store: FocusStore(defaults: defaults))
        let panel = FocusPanel(controller: controller, screenFrame: CGRect(x: 0, y: 0, width: 800, height: 900), applicationScreen: { nil }, reduceMotion: { false })
        panel.makeKeyAndOrderFront(nil)
        let menu = makeSettingsMenu(controller)
        defer { menu.orderOut(nil); panel.orderOut(nil); defaults.removePersistentDomain(forName: suite) }
        settle(panel)
        let compactHeight = try paintedHeight(snapshot(panel, name: "compact"))
        panel.setExpanded(true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let expandingHeight = try paintedHeight(snapshot(panel, name: "expanding"))
        settle(panel)
        XCTAssertEqual(panel.presentation, .controls)
        let controlsHeight = panel.frame.height
        let renderedControlsHeight = try paintedHeight(snapshot(panel, name: "controls"))
        XCTAssertGreaterThan(expandingHeight, compactHeight)
        XCTAssertLessThan(expandingHeight, renderedControlsHeight, "The visible surface must interpolate, not jump to its final height")
        let closedMenuHeight = menu.frame.height
        try settingsMenuButton("Show settings", in: menu).performClick(nil)
        settleSettingsMenu(menu)
        settle(panel)
        XCTAssertGreaterThan(menu.frame.height, closedMenuHeight + 100)
        XCTAssertEqual(panel.frame.height, controlsHeight, accuracy: 1)
        XCTAssertEqual(descendantViews(of: menu.contentView).compactMap { $0 as? NSSwitch }.count, 1)
        try snapshot(menu, name: "settings")
        try settingsMenuButton("Hide settings", in: menu).performClick(nil)
        settleSettingsMenu(menu)
        XCTAssertEqual(menu.frame.height, closedMenuHeight, accuracy: 1)
        XCTAssertEqual(descendantViews(of: menu.contentView).compactMap { $0 as? NSSwitch }.count, 0)
        XCTAssertEqual(panel.frame.height, controlsHeight, accuracy: 1)
        panel.cancelOperation(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let collapsingHeight = try paintedHeight(snapshot(panel, name: "collapsing"))
        XCTAssertGreaterThan(collapsingHeight, compactHeight)
        XCTAssertLessThan(collapsingHeight, renderedControlsHeight)
        settle(panel)
        XCTAssertEqual(panel.presentation, .compact)
        XCTAssertEqual(panel.frame.height, 64)
        XCTAssertNil(descendantViews(of: panel.contentView).compactMap { $0 as? NSButton }
            .first { $0.accessibilityLabel() == "Collapse" })
        XCTAssertEqual(try paintedHeight(snapshot(panel, name: "collapsed")), compactHeight)
    }

    private func makePanel(reduceMotion: Bool = false) throws -> FocusPanel {
        _ = NSApplication.shared
        let suite = "FocusPanelAnimationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let panel = FocusPanel(controller: FocusController(store: FocusStore(defaults: defaults)),
                               screenFrame: CGRect(x: 0, y: 0, width: 800, height: 900),
                               applicationScreen: { nil }, reduceMotion: { reduceMotion })
        panel.makeKeyAndOrderFront(nil)
        return panel
    }

    private func settle(_ panel: NSPanel) {
        RunLoop.main.run(until: Date().addingTimeInterval(FocusPanel.animationDuration + 0.15))
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    private func paintedHeight(_ bitmap: NSBitmapImageRep) throws -> Int {
        try (0..<bitmap.pixelsHigh).filter {
            try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: $0)).alphaComponent > 0.5
        }.count
    }

    @discardableResult
    private func snapshot(_ panel: NSPanel, name: String) throws -> NSBitmapImageRep {
        let view = try XCTUnwrap(panel.contentView)
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/motion-qa")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("\(name).png"))
        return rep
    }
}

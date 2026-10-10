import AppKit
import FocusCore
import XCTest
@testable import OpenFocusIsland

@MainActor
final class FocusIdleVisibilityTests: XCTestCase {
    func testIslandHiddenWhileIdleAndCollapsed() throws {
        _ = NSApplication.shared
        let suiteName = "FocusIdleVisibilityTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let controller = FocusController(store: FocusStore(defaults: defaults))
        let panel = FocusPanel(controller: controller, screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), screenID: 1)
        defer { panel.orderOut(nil); defaults.removePersistentDomain(forName: suiteName) }

        panel.hidesWhenIdle = true
        panel.updateVisibility()
        XCTAssertFalse(panel.isVisible, "Idle and collapsed: hidden")

        controller.start(kind: .focus)
        panel.updateVisibility()
        XCTAssertTrue(panel.isVisible, "Running: visible")

        controller.pause()
        panel.updateVisibility()
        XCTAssertTrue(panel.isVisible, "Paused: visible")

        panel.setExpanded(true)
        controller.finish()
        panel.updateVisibility()
        XCTAssertTrue(panel.isVisible, "Expanded stays visible after finishing")

        panel.setExpanded(false)
        XCTAssertFalse(panel.isVisible, "Collapsing while idle hides")
    }
}

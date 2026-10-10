import XCTest
@testable import FocusCore

final class PanelPresentationTests: XCTestCase {
    func testNotchPresentationTransitions() {
        var state = PanelPresentation.compact
        state.expand(isNotched: true)
        XCTAssertEqual(state, .timer)
        state.openControls()
        XCTAssertEqual(state, .controls)
        state.collapse(isNotched: true)
        XCTAssertEqual(state, .timer)
        state.collapse(isNotched: true)
        XCTAssertEqual(state, .compact)
    }

    func testNotchPrimaryToggleIsExpandThenCollapse() {
        var state = PanelPresentation.compact
        state.expand(isNotched: true)
        XCTAssertEqual(state, .timer)
        state.collapse(isNotched: true)
        XCTAssertEqual(state, .compact)
    }

    func testWithoutNotchExpandGoesToControlsAndBackToCompact() {
        var state = PanelPresentation.compact
        state.expand(isNotched: false)
        XCTAssertEqual(state, .controls)
        state.collapse(isNotched: false)
        XCTAssertEqual(state, .compact)
    }

    func testWithoutNotchOpenControlsAndBackToCompact() {
        var state = PanelPresentation.compact
        state.openControls()
        XCTAssertEqual(state, .controls)
        state.collapse(isNotched: false)
        XCTAssertEqual(state, .compact)
    }

    func testExpandFromTimerOrControlsChangesNothing() {
        for notched in [true, false] {
            var timer = PanelPresentation.timer
            timer.expand(isNotched: notched)
            XCTAssertEqual(timer, .timer)
            var controls = PanelPresentation.controls
            controls.expand(isNotched: notched)
            XCTAssertEqual(controls, .controls)
        }
    }

    func testCollapseFromCompactStaysCompact() {
        for notched in [true, false] {
            var state = PanelPresentation.compact
            state.collapse(isNotched: notched)
            XCTAssertEqual(state, .compact)
        }
    }

    func testTimerCollapsesToCompactRegardlessOfNotch() {
        for notched in [true, false] {
            var state = PanelPresentation.timer
            state.collapse(isNotched: notched)
            XCTAssertEqual(state, .compact)
        }
    }
}

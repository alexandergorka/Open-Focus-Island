import CoreGraphics
import XCTest
@testable import FocusCore

final class PanelPositionTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1_440, height: 900)
    private let panel = CGRect(x: 540, y: 400, width: 360, height: 64)

    func testNewPositionHasNoDisplayOrAnchor() {
        let position = PanelPosition()
        XCTAssertNil(position.displayID)
        XCTAssertNil(position.manualAnchor)
    }

    func testDragPreservesPointerOffset() {
        let moved = PanelPosition.draggedFrame(from: panel, by: CGSize(width: 200, height: 120), within: bounds)
        XCTAssertEqual(moved, CGRect(x: 740, y: 520, width: 360, height: 64))

        let back = PanelPosition.draggedFrame(from: moved, by: CGSize(width: -200, height: -120), within: bounds)
        XCTAssertEqual(back, panel)

        let still = PanelPosition.draggedFrame(from: panel, by: .zero, within: bounds)
        XCTAssertEqual(still, panel)
    }

    func testDragIsClampedAtEveryEdge() {
        XCTAssertEqual(
            PanelPosition.draggedFrame(from: panel, by: CGSize(width: 5_000, height: 5_000), within: bounds),
            CGRect(x: 1_080, y: 836, width: 360, height: 64)
        )
        XCTAssertEqual(
            PanelPosition.draggedFrame(from: panel, by: CGSize(width: -5_000, height: -5_000), within: bounds),
            CGRect(x: 0, y: 0, width: 360, height: 64)
        )
    }

    func testClampKeepsUnaffectedAxisExact() {
        XCTAssertEqual(
            PanelPosition.draggedFrame(from: panel, by: CGSize(width: 5_000, height: -10), within: bounds),
            CGRect(x: 1_080, y: 390, width: 360, height: 64)
        )
    }

    func testFrameLargerThanBoundsShrinksToBounds() {
        let tooBig = CGRect(x: 10, y: 10, width: 3_000, height: 2_000)
        XCTAssertEqual(PanelPosition.draggedFrame(from: tooBig, by: CGSize(width: 50, height: 50), within: bounds), bounds)
    }

    func testOffsetAndNegativeBoundsLikeDisplayLeftOfMain() {
        let left = CGRect(x: -1_920, y: 100, width: 1_920, height: 1_080)
        let start = CGRect(x: -1_200, y: 1_000, width: 360, height: 64)

        XCTAssertEqual(
            PanelPosition.draggedFrame(from: start, by: CGSize(width: -100, height: 30), within: left),
            CGRect(x: -1_300, y: 1_030, width: 360, height: 64)
        )
        XCTAssertEqual(
            PanelPosition.draggedFrame(from: start, by: CGSize(width: 900, height: 500), within: left),
            CGRect(x: -360, y: 1_116, width: 360, height: 64)
        )
        XCTAssertEqual(
            PanelPosition.draggedFrame(from: start, by: CGSize(width: -900, height: -2_000), within: left),
            CGRect(x: -1_920, y: 100, width: 360, height: 64)
        )
    }

    func testFrameOutsideBoundsIsPulledIn() {
        let outside = CGRect(x: 3_000, y: -200, width: 360, height: 64)
        XCTAssertEqual(
            PanelPosition.draggedFrame(from: outside, by: .zero, within: bounds),
            CGRect(x: 1_080, y: 0, width: 360, height: 64)
        )
    }

    func testNonFiniteDeltaReturnsEmptyRect() {
        for delta in [
            CGSize(width: CGFloat.nan, height: 0), CGSize(width: 0, height: CGFloat.nan),
            CGSize(width: CGFloat.infinity, height: 0), CGSize(width: 0, height: -CGFloat.infinity),
        ] {
            XCTAssertEqual(PanelPosition.draggedFrame(from: panel, by: delta, within: bounds), CGRect(), "\(delta)")
        }
    }

    func testNonFiniteOrNegativeSourceFrameReturnsEmptyRect() {
        for from in [
            CGRect(x: CGFloat.nan, y: 0, width: 360, height: 64),
            CGRect(x: 0, y: CGFloat.infinity, width: 360, height: 64),
            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 64),
            CGRect(x: 0, y: 0, width: 360, height: CGFloat.nan),
            CGRect(x: 0, y: 0, width: -360, height: 64),
        ] {
            XCTAssertEqual(PanelPosition.draggedFrame(from: from, by: .zero, within: bounds), CGRect(), "\(from)")
        }
    }

    func testEmptyNegativeOrNonFiniteBoundsReturnEmptyRect() {
        for invalid in [
            CGRect(),
            CGRect(x: 0, y: 0, width: 0, height: 900),
            CGRect(x: 0, y: 0, width: 1_440, height: -900),
            CGRect(x: CGFloat.nan, y: 0, width: 1_440, height: 900),
            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 900),
            CGRect(x: 0, y: CGFloat.infinity, width: 1_440, height: 900),
            CGRect(x: 0, y: 0, width: 1_440, height: CGFloat.nan),
        ] {
            XCTAssertEqual(PanelPosition.draggedFrame(from: panel, by: CGSize(width: 10, height: 10), within: invalid), CGRect(), "\(invalid)")
        }
    }

    // MARK: - D3: manuelle Position über Größenänderung/Refresh erhalten

    private let compact = CGRect(x: 540, y: 836, width: 360, height: 64)
    private let settings = CGRect(x: 540, y: 360, width: 360, height: 540)

    func testRefreshPreservesManualPosition() {
        var position = PanelPosition()
        position.updateDisplay(id: 1)
        let dragged = PanelPosition.draggedFrame(from: compact, by: CGSize(width: -300, height: -200), within: bounds)
        position.setManualFrame(dragged) // x 240...600, Oberkante 700
        let anchor = CGPoint(x: 420, y: 700)
        XCTAssertEqual(position.manualAnchor, anchor)

        for _ in 0..<3 {
            XCTAssertEqual(position.frame(for: compact, within: bounds), CGRect(x: 240, y: 636, width: 360, height: 64))
            let grown = position.frame(for: settings, within: bounds)
            XCTAssertEqual(grown, CGRect(x: 240, y: 160, width: 360, height: 540))
            XCTAssertEqual(grown.midX, anchor.x)
            XCTAssertEqual(grown.maxY, anchor.y)
            position.updateDisplay(id: 1)
            XCTAssertEqual(position.manualAnchor, anchor)
            XCTAssertEqual(position.displayID, 1)
        }
    }

    func testWithoutAnchorFrameIsClampedDefault() {
        let position = PanelPosition()
        XCTAssertEqual(position.frame(for: compact, within: bounds), compact)
        XCTAssertEqual(
            position.frame(for: CGRect(x: 1_400, y: -50, width: 360, height: 64), within: bounds),
            CGRect(x: 1_080, y: 0, width: 360, height: 64)
        )
        XCTAssertEqual(position.frame(for: CGRect(x: 10, y: 10, width: 3_000, height: 2_000), within: bounds), bounds)
        XCTAssertNil(position.manualAnchor)
    }

    func testAnchorNearEdgeIsClampedKeepingTopAsFarAsPossible() {
        var position = PanelPosition()
        position.setManualFrame(CGRect(x: 1_300, y: 150, width: 360, height: 64)) // Mitte 1480 (außerhalb), Oberkante 214
        XCTAssertEqual(position.frame(for: settings, within: bounds), CGRect(x: 1_080, y: 0, width: 360, height: 540)) // unten bündig

        position.setManualFrame(CGRect(x: 540, y: 100, width: 360, height: 64)) // Oberkante 164
        XCTAssertEqual(position.frame(for: settings, within: bounds), CGRect(x: 540, y: 0, width: 360, height: 540))

        position.setManualFrame(CGRect(x: 540, y: 836, width: 360, height: 64)) // Oberkante = Bounds-Oberkante
        XCTAssertEqual(position.frame(for: settings, within: bounds), CGRect(x: 540, y: 360, width: 360, height: 540))
    }

    func testAnchorIsReadFromActualFrameTopCenter() {
        var position = PanelPosition()
        position.setManualFrame(CGRect(x: 100, y: 200, width: 360, height: 64))
        XCTAssertEqual(position.manualAnchor, CGPoint(x: 280, y: 264))
        position.setManualFrame(CGRect(x: 100, y: 100, width: 200, height: 300))
        XCTAssertEqual(position.manualAnchor, CGPoint(x: 200, y: 400))
    }

    func testInvalidManualFrameKeepsExistingAnchor() {
        var position = PanelPosition()
        position.setManualFrame(CGRect(x: 100, y: 200, width: 360, height: 64))
        let anchor = position.manualAnchor
        XCTAssertNotNil(anchor)
        for invalid in [
            CGRect(x: CGFloat.nan, y: 0, width: 360, height: 64),
            CGRect(x: 0, y: CGFloat.infinity, width: 360, height: 64),
            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 64),
            CGRect(x: 0, y: 0, width: 360, height: CGFloat.nan),
            CGRect(x: 0, y: 0, width: -360, height: 64),
            CGRect(x: 0, y: 0, width: 360, height: -64),
            CGRect(), // leerer Rückgabewert von draggedFrame darf den Anker nicht überschreiben
        ] {
            position.setManualFrame(invalid)
            XCTAssertEqual(position.manualAnchor, anchor, "\(invalid)")
        }

        var fresh = PanelPosition()
        fresh.setManualFrame(CGRect(x: CGFloat.nan, y: 0, width: 360, height: 64))
        XCTAssertNil(fresh.manualAnchor)
    }

    func testFirstUpdateDisplaySetsIdAndSameIdKeepsAnchor() {
        var position = PanelPosition()
        position.updateDisplay(id: 7)
        XCTAssertEqual(position.displayID, 7)
        XCTAssertNil(position.manualAnchor)

        position.setManualFrame(panel)
        position.updateDisplay(id: 7)
        XCTAssertEqual(position.displayID, 7)
        XCTAssertEqual(position.manualAnchor, CGPoint(x: 720, y: 464))
    }

    func testInvalidDefaultOrBoundsReturnEmptyRect() {
        var position = PanelPosition()
        for useAnchor in [false, true] {
            if useAnchor { position.setManualFrame(panel) }
            for invalid in [
                CGRect(x: CGFloat.nan, y: 0, width: 360, height: 64),
                CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 64),
                CGRect(x: 0, y: 0, width: -360, height: 64),
            ] {
                XCTAssertEqual(position.frame(for: invalid, within: bounds), CGRect(), "default \(invalid) anchor \(useAnchor)")
            }
            for invalid in [
                CGRect(),
                CGRect(x: 0, y: 0, width: 1_440, height: -900),
                CGRect(x: CGFloat.nan, y: 0, width: 1_440, height: 900),
                CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 900),
            ] {
                XCTAssertEqual(position.frame(for: compact, within: invalid), CGRect(), "bounds \(invalid) anchor \(useAnchor)")
            }
        }
    }

    func testOffsetAndNegativeBoundsKeepAnchorWhenGrowing() {
        let left = CGRect(x: -1_920, y: 100, width: 1_920, height: 1_080)
        var position = PanelPosition()
        position.setManualFrame(CGRect(x: -1_200, y: 1_000, width: 360, height: 64)) // Mitte -1020, Oberkante 1064
        XCTAssertEqual(position.frame(for: settings, within: left), CGRect(x: -1_200, y: 524, width: 360, height: 540))

        // Anker nahe linker/unterer Kante: Größe wächst nach unten und wird eingeklemmt.
        position.setManualFrame(CGRect(x: -1_950, y: 130, width: 360, height: 64)) // Mitte -1770, Oberkante 194
        XCTAssertEqual(position.frame(for: settings, within: left), CGRect(x: -1_920, y: 100, width: 360, height: 540))

        // Anker außerhalb rechts.
        position.setManualFrame(CGRect(x: 500, y: 1_000, width: 360, height: 64))
        XCTAssertEqual(position.frame(for: settings, within: left), CGRect(x: -360, y: 524, width: 360, height: 540))
    }

    func testFrameQueryDoesNotMutateState() {
        var position = PanelPosition()
        position.updateDisplay(id: 2)
        position.setManualFrame(panel)
        _ = position.frame(for: settings, within: bounds)
        XCTAssertEqual(position.manualAnchor, CGPoint(x: 720, y: 464))
        XCTAssertEqual(position.displayID, 2)
    }

    // MARK: - D4: Displaywechsel löscht die manuelle Position

    private let secondDisplay = CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080)

    func testDisplayChangeResetsPosition() {
        var position = PanelPosition()
        position.updateDisplay(id: 1)
        position.setManualFrame(CGRect(x: 240, y: 636, width: 360, height: 64))
        let anchor = CGPoint(x: 420, y: 700)

        position.updateDisplay(id: 1)
        XCTAssertEqual(position.manualAnchor, anchor)
        XCTAssertEqual(position.displayID, 1)
        XCTAssertEqual(position.frame(for: compact, within: bounds), CGRect(x: 240, y: 636, width: 360, height: 64))

        position.updateDisplay(id: 2)
        XCTAssertNil(position.manualAnchor)
        XCTAssertEqual(position.displayID, 2)
        // Neue Default-Platzierung: Default (540, 836) auf Display 2 (x 1440...3360) geklemmt.
        XCTAssertEqual(position.frame(for: compact, within: secondDisplay), CGRect(x: 1_440, y: 836, width: 360, height: 64))
    }

    func testAnchorSetBeforeFirstAssignmentIsClearedByFirstUpdateDisplay() {
        var position = PanelPosition()
        position.setManualFrame(panel)
        XCTAssertNotNil(position.manualAnchor)
        XCTAssertNil(position.displayID)

        position.updateDisplay(id: 1)
        XCTAssertNil(position.manualAnchor)
        XCTAssertEqual(position.displayID, 1)
        XCTAssertEqual(position.frame(for: compact, within: bounds), compact)
    }

    func testSwitchingBackToOldDisplayDoesNotRestoreAnchor() {
        var position = PanelPosition()
        position.updateDisplay(id: 1)
        position.setManualFrame(panel)
        position.updateDisplay(id: 2)
        position.updateDisplay(id: 1)
        XCTAssertNil(position.manualAnchor)
        XCTAssertEqual(position.displayID, 1)
        XCTAssertEqual(position.frame(for: compact, within: bounds), compact)
    }

    func testNewAnchorAfterResetIsKeptOnSameDisplay() {
        var position = PanelPosition()
        position.updateDisplay(id: 1)
        position.setManualFrame(panel)
        position.updateDisplay(id: 2)

        position.setManualFrame(CGRect(x: 2_000, y: 500, width: 360, height: 64)) // Mitte 2180, Oberkante 564
        position.updateDisplay(id: 2)
        XCTAssertEqual(position.manualAnchor, CGPoint(x: 2_180, y: 564))
        XCTAssertEqual(position.frame(for: compact, within: secondDisplay), CGRect(x: 2_000, y: 500, width: 360, height: 64))
    }
}

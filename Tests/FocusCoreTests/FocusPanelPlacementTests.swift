import CoreGraphics
import XCTest
@testable import FocusCore

final class FocusPanelPlacementTests: XCTestCase {
    func testPrimaryDisplayWithoutNotch() {
        XCTAssertEqual(
            FocusPanelPlacement.frame(
                screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 870),
                safeAreaTop: 24,
                size: CGSize(width: 360, height: 64)
            ),
            CGRect(x: 540, y: 806, width: 360, height: 64)
        )
    }

    func testPrimaryDisplayWithNotchSafeArea() {
        XCTAssertEqual(
            FocusPanelPlacement.frame(
                screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 870),
                safeAreaTop: 50,
                size: CGSize(width: 360, height: 64)
            ),
            CGRect(x: 540, y: 786, width: 360, height: 64)
        )
    }

    func testExternalScreensLeftRightAndAbovePrimaryUseTheirOwnCoordinates() {
        XCTAssertEqual(
            FocusPanelPlacement.frame(
                screenFrame: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
                visibleFrame: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_050),
                safeAreaTop: 24,
                size: CGSize(width: 360, height: 64)
            ),
            CGRect(x: -1_140, y: 986, width: 360, height: 64)
        )
        XCTAssertEqual(
            FocusPanelPlacement.frame(
                screenFrame: CGRect(x: 1_440, y: 200, width: 2_560, height: 1_440),
                visibleFrame: CGRect(x: 1_440, y: 200, width: 2_560, height: 1_410),
                safeAreaTop: 40,
                size: CGSize(width: 360, height: 64)
            ),
            CGRect(x: 2_540, y: 1_536, width: 360, height: 64)
        )
        XCTAssertEqual(
            FocusPanelPlacement.frame(
                screenFrame: CGRect(x: 0, y: 900, width: 2_560, height: 1_440),
                visibleFrame: CGRect(x: 0, y: 900, width: 2_560, height: 1_410),
                safeAreaTop: 24,
                size: CGSize(width: 360, height: 64)
            ),
            CGRect(x: 1_100, y: 2_246, width: 360, height: 64)
        )
    }

    func testPanelSizeIsClampedToSmallDisplayAndFrameRemainsContained() {
        let screen = CGRect(x: -200, y: -100, width: 280, height: 180)
        let visible = CGRect(x: -160, y: -80, width: 240, height: 140)
        let frame = FocusPanelPlacement.frame(
            screenFrame: screen,
            visibleFrame: visible,
            safeAreaTop: 30,
            size: CGSize(width: 360, height: 500)
        )
        XCTAssertEqual(frame, CGRect(x: -160, y: -80, width: 240, height: 130))
        XCTAssertTrue(visible.contains(frame))
    }

    func testExpandedCardUsesScrollableViewportWhenContentExceedsSmallScreen() {
        XCTAssertEqual(FocusPanelViewport.height(contentHeight: 460, availableHeight: 130), 130)
        XCTAssertEqual(FocusPanelViewport.height(contentHeight: 90, availableHeight: 130), 90)
    }
}

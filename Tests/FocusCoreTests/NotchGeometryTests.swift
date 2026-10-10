import CoreGraphics
import XCTest
@testable import FocusCore

final class NotchGeometryTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1_512, height: 982)

    private func cutout(
        screen: CGRect? = nil, safeAreaTop: CGFloat = 32, left: CGRect?, right: CGRect?
    ) -> CGRect? {
        NotchGeometry.detect(screenFrame: screen ?? self.screen, safeAreaTop: safeAreaTop, leftArea: left, rightArea: right)?.cutoutFrame
    }

    func testNotchGeometryUsesScreenCoordinates() {
        // MacBook Pro 14": Lücke aus den Auxiliary-Areas, Höhe aus dem oberen Safe-Inset.
        XCTAssertEqual(
            cutout(left: CGRect(x: 0, y: 950, width: 662, height: 32), right: CGRect(x: 850, y: 950, width: 662, height: 32)),
            CGRect(x: 662, y: 950, width: 188, height: 32)
        )
        // Versetzter Screen links vom Hauptdisplay (negatives x) mit anderer Lückenbreite.
        XCTAssertEqual(
            cutout(
                screen: CGRect(x: -1_728, y: -120, width: 1_728, height: 1_117),
                safeAreaTop: 38,
                left: CGRect(x: -1_728, y: 959, width: 780, height: 38),
                right: CGRect(x: -780, y: 959, width: 780, height: 38)
            ),
            CGRect(x: -948, y: 959, width: 168, height: 38)
        )
        // Keine Notch.
        XCTAssertNil(cutout(safeAreaTop: 0, left: nil, right: nil))
        // Ungültige Daten.
        XCTAssertNil(cutout(safeAreaTop: .nan, left: CGRect(x: 0, y: 950, width: 600, height: 32), right: CGRect(x: 900, y: 950, width: 612, height: 32)))
    }

    func testCutoutWidthIsDerivedFromAreasNotHardwired() {
        let narrow = cutout(left: CGRect(x: 0, y: 950, width: 700, height: 32), right: CGRect(x: 800, y: 950, width: 712, height: 32))
        let wide = cutout(left: CGRect(x: 0, y: 950, width: 600, height: 32), right: CGRect(x: 900, y: 950, width: 612, height: 32))
        XCTAssertEqual(narrow, CGRect(x: 700, y: 950, width: 100, height: 32))
        XCTAssertEqual(wide, CGRect(x: 600, y: 950, width: 300, height: 32))
    }

    func testScreenAbovePrimaryDisplayUsesItsOwnCoordinates() {
        XCTAssertEqual(
            cutout(
                screen: CGRect(x: 300, y: 1_080, width: 1_512, height: 982),
                left: CGRect(x: 300, y: 2_030, width: 662, height: 32),
                right: CGRect(x: 1_150, y: 2_030, width: 662, height: 32)
            ),
            CGRect(x: 962, y: 2_030, width: 188, height: 32)
        )
    }

    func testMissingAreaOrSafeAreaMeansNoNotch() {
        let left = CGRect(x: 0, y: 950, width: 662, height: 32)
        let right = CGRect(x: 850, y: 950, width: 662, height: 32)
        XCTAssertNil(cutout(left: left, right: nil))
        XCTAssertNil(cutout(left: nil, right: right))
        XCTAssertNil(cutout(safeAreaTop: 0, left: left, right: right))
        XCTAssertNil(cutout(safeAreaTop: -4, left: left, right: right))
        XCTAssertNil(cutout(safeAreaTop: .infinity, left: left, right: right))
    }

    func testNonFiniteOrEmptyValuesMeanNoNotch() {
        let left = CGRect(x: 0, y: 950, width: 662, height: 32)
        let right = CGRect(x: 850, y: 950, width: 662, height: 32)
        XCTAssertNil(cutout(left: CGRect(x: CGFloat.nan, y: 950, width: 662, height: 32), right: right))
        XCTAssertNil(cutout(left: left, right: CGRect(x: 850, y: 950, width: CGFloat.infinity, height: 32)))
        XCTAssertNil(cutout(left: CGRect(x: 0, y: 950, width: 0, height: 32), right: right))
        XCTAssertNil(cutout(screen: CGRect(x: 0, y: 0, width: CGFloat.nan, height: 982), left: left, right: right))
        XCTAssertNil(cutout(screen: CGRect(x: 0, y: 0, width: 0, height: 0), left: left, right: right))
        XCTAssertNil(cutout(screen: CGRect(x: 0, y: 0, width: -1_512, height: 982), left: left, right: right))
    }

    func testOverlappingTouchingOrSwappedAreasMeanNoNotch() {
        XCTAssertNil(cutout(left: CGRect(x: 0, y: 950, width: 800, height: 32), right: CGRect(x: 700, y: 950, width: 812, height: 32)))
        XCTAssertNil(cutout(left: CGRect(x: 0, y: 950, width: 756, height: 32), right: CGRect(x: 756, y: 950, width: 756, height: 32)))
        XCTAssertNil(cutout(left: CGRect(x: 850, y: 950, width: 662, height: 32), right: CGRect(x: 0, y: 950, width: 662, height: 32)))
    }

    func testAreasOutsideScreenMeanNoNotch() {
        // Areas eines anderen Displays (Koordinaten des Hauptdisplays bei versetztem Screen).
        XCTAssertNil(cutout(
            screen: CGRect(x: 1_512, y: 0, width: 1_512, height: 982),
            left: CGRect(x: 0, y: 950, width: 662, height: 32),
            right: CGRect(x: 850, y: 950, width: 662, height: 32)
        ))
        XCTAssertNil(cutout(left: CGRect(x: -10, y: 950, width: 672, height: 32), right: CGRect(x: 850, y: 950, width: 662, height: 32)))
        XCTAssertNil(cutout(left: CGRect(x: 0, y: 950, width: 662, height: 32), right: CGRect(x: 850, y: 950, width: 700, height: 32)))
    }

    func testSafeAreaTallerThanScreenMeansNoNotch() {
        XCTAssertNil(cutout(safeAreaTop: 2_000, left: CGRect(x: 0, y: 950, width: 662, height: 32), right: CGRect(x: 850, y: 950, width: 662, height: 32)))
    }
}

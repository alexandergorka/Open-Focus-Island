import CoreGraphics

public struct NotchGeometry: Equatable {
    public let cutoutFrame: CGRect

    public static func detect(screenFrame: CGRect, safeAreaTop: CGFloat, leftArea: CGRect?, rightArea: CGRect?) -> NotchGeometry? {
        guard safeAreaTop.isFinite, safeAreaTop > 0,
              isUsable(screenFrame), screenFrame.height >= safeAreaTop,
              let leftArea, isUsable(leftArea), screenFrame.contains(leftArea),
              let rightArea, isUsable(rightArea), screenFrame.contains(rightArea) else { return nil }

        let gap = rightArea.minX - leftArea.maxX
        guard gap > 0 else { return nil }
        return NotchGeometry(cutoutFrame: CGRect(x: leftArea.maxX, y: screenFrame.maxY - safeAreaTop, width: gap, height: safeAreaTop))
    }

    // Prüft size statt width/height, weil CGRect negative Größen normalisiert.
    private static func isUsable(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height].allSatisfy(\.isFinite)
            && rect.size.width > 0 && rect.size.height > 0
    }
}

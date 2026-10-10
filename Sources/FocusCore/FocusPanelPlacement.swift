import CoreGraphics

public enum FocusPanelPlacement {
    public static func frame(screenFrame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat, size: CGSize) -> CGRect {
        guard screenFrame.minX.isFinite, screenFrame.minY.isFinite,
              screenFrame.width.isFinite, screenFrame.height.isFinite,
              visibleFrame.minX.isFinite, visibleFrame.minY.isFinite,
              visibleFrame.width.isFinite, visibleFrame.height.isFinite,
              screenFrame.width > 0, screenFrame.height > 0,
              visibleFrame.width > 0, visibleFrame.height > 0 else { return CGRect() }

        let safeTop = safeAreaTop.isFinite ? max(0, safeAreaTop) : 0
        let visibleArea = screenFrame.intersection(visibleFrame)
        let top = min(visibleArea.maxY, screenFrame.maxY - safeTop)
        guard !visibleArea.isNull, visibleArea.width > 0, top > visibleArea.minY else { return CGRect() }

        let available = CGRect(x: visibleArea.minX, y: visibleArea.minY, width: visibleArea.width, height: top - visibleArea.minY)
        let width = min(size.width.isFinite ? max(0, size.width) : 0, available.width)
        let height = min(size.height.isFinite ? max(0, size.height) : 0, available.height)
        let x = available.midX - width / 2
        let y = top - height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

public enum FocusPanelViewport {
    public static func height(contentHeight: CGFloat, availableHeight: CGFloat) -> CGFloat {
        let content = contentHeight.isFinite ? max(0, contentHeight) : 0
        let available = availableHeight.isFinite ? max(0, availableHeight) : 0
        return min(content, available)
    }
}

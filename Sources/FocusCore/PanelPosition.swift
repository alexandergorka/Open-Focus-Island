import CoreGraphics

public struct PanelPosition {
    public private(set) var displayID: UInt32?
    public private(set) var manualAnchor: CGPoint? // x = Mitte, y = Oberkante

    public init() {}

    /// Verschiebt `from` um `by` (Mausversatz bleibt erhalten) und begrenzt Größe und Position auf `within`.
    /// Nicht endliche Werte, negative Frame-Größe oder leere `within` ergeben `CGRect()`.
    public static func draggedFrame(from: CGRect, by: CGSize, within: CGRect) -> CGRect {
        guard isValidFrame(from), by.width.isFinite, by.height.isFinite else { return CGRect() }
        return clamped(origin: CGPoint(x: from.minX + by.width, y: from.minY + by.height), size: from.size, within: within)
    }

    /// Merkt die Oberkante-Mitte des tatsächlichen Frames. Ungültige Frames (nicht endlich, negative
    /// oder leere Größe – z. B. das `CGRect()` eines fehlgeschlagenen `draggedFrame`) lassen den Anker unverändert.
    public mutating func setManualFrame(_ frame: CGRect) {
        guard Self.isValidFrame(frame), frame.size.width > 0, frame.size.height > 0 else { return }
        manualAnchor = CGPoint(x: frame.midX, y: frame.maxY)
    }

    /// Setzt die Display-Zuordnung. Bei gleicher ID bleibt der Anker erhalten; jede andere ID
    /// (auch die erste Zuordnung, `displayID == nil`) löscht ihn – die Default-Platzierung greift neu.
    /// Ein späterer Wechsel zurück auf die alte ID stellt den Anker nicht wieder her.
    public mutating func updateDisplay(id: UInt32) {
        if displayID != id { manualAnchor = nil }
        displayID = id
    }

    /// Ohne Anker: `defaultFrame` auf `bounds` begrenzt. Mit Anker: obere Mitte des Ankers mit der
    /// Größe von `defaultFrame` (wächst nach unten), auf `bounds` begrenzt. Ungültige Eingaben ergeben `CGRect()`.
    public func frame(for defaultFrame: CGRect, within bounds: CGRect) -> CGRect {
        guard Self.isValidFrame(defaultFrame) else { return CGRect() }
        guard let anchor = manualAnchor else {
            return Self.clamped(origin: defaultFrame.origin, size: defaultFrame.size, within: bounds)
        }
        return Self.clamped(
            origin: CGPoint(x: anchor.x - defaultFrame.width / 2, y: anchor.y - defaultFrame.height),
            size: defaultFrame.size, within: bounds
        )
    }

    // `size` statt `width`/`height`: CGRect normalisiert negative Größen, `size` bleibt roh.
    private static func isValidFrame(_ r: CGRect) -> Bool {
        r.origin.x.isFinite && r.origin.y.isFinite && r.size.width.isFinite && r.size.height.isFinite
            && r.size.width >= 0 && r.size.height >= 0
    }

    private static func clamped(origin: CGPoint, size: CGSize, within: CGRect) -> CGRect {
        guard within.origin.x.isFinite, within.origin.y.isFinite, within.size.width.isFinite, within.size.height.isFinite,
              within.size.width > 0, within.size.height > 0 else { return CGRect() }
        let width = min(size.width, within.width)
        let height = min(size.height, within.height)
        let x = min(max(origin.x, within.minX), within.maxX - width)
        let y = min(max(origin.y, within.minY), within.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

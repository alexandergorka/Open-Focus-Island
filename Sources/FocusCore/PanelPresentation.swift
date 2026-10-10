public enum PanelPresentation: Equatable {
    case compact, timer, controls

    /// Nur aus `compact`: Notch → Timeranzeige, sonst direkt Bedienung.
    public mutating func expand(isNotched: Bool) {
        if self == .compact { self = isNotched ? .timer : .controls }
    }

    /// Ein Schritt zurück (auch Escape): Bedienung → Timer (nur Notch) bzw. kompakt, Timer → kompakt.
    public mutating func collapse(isNotched: Bool) {
        switch self {
        case .controls: self = isNotched ? .timer : .compact
        case .timer: self = .compact
        case .compact: break
        }
    }

    public mutating func openControls() {
        self = .controls
    }
}

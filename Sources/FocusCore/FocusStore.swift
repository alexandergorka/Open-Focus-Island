import Foundation

public struct FocusStore {
    private let defaults: UserDefaults
    private let settingsKey = "focus.settings"
    private let sessionKey = "focus.session"
    private let historyKey = "focus.history"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadSettings() -> FocusSettings {
        guard let data = defaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(FocusSettings.self, from: data),
              settings.isValid else { return .defaults }
        return settings
    }

    public func saveSettings(_ settings: FocusSettings) throws {
        guard settings.isValid else { throw StoreError.invalidData }
        defaults.set(try JSONEncoder().encode(settings), forKey: settingsKey)
    }

    public func loadSession(at date: Date) -> FocusSession {
        guard let data = defaults.data(forKey: sessionKey),
              var session = try? JSONDecoder().decode(FocusSession.self, from: data),
              session.isValid else { return FocusSession() }
        if session.reconcile(at: date) { try? saveSession(session) }
        return session
    }

    public func saveSession(_ session: FocusSession) throws {
        guard session.isValid else { throw StoreError.invalidData }
        defaults.set(try JSONEncoder().encode(session), forKey: sessionKey)
    }

    public func loadHistory() throws -> [FocusHistoryEntry] {
        guard let stored = defaults.object(forKey: historyKey) else { return [] }
        guard let data = stored as? Data else { throw StoreError.invalidData }
        return try JSONDecoder().decode([FocusHistoryEntry].self, from: data)
    }

    public func recordCompletedFocus(_ session: FocusSession) throws {
        guard session.isValid else { throw StoreError.invalidData }
        guard let entry = FocusHistoryEntry(session: session) else { return }
        var history = try loadHistory()
        guard !history.contains(where: { $0.id == entry.id }) else { return }
        history.append(entry)
        history.sort { $0.completedAt == $1.completedAt ? $0.id.uuidString < $1.id.uuidString : $0.completedAt > $1.completedAt }
        defaults.set(try JSONEncoder().encode(history), forKey: historyKey)
    }

    public enum StoreError: Error { case invalidData }
}

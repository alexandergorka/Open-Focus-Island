import Foundation

public enum AppLanguage: String, Codable, Sendable, CaseIterable {
    case english = "en", german = "de"
    public func t(_ english: String, _ german: String) -> String { self == .german ? german : english }
}

public struct FocusSettings: Codable, Equatable, Sendable {
    public var focusDuration: TimeInterval
    public var shortBreakDuration: TimeInterval
    public var longBreakDuration: TimeInterval
    public var notificationsEnabled: Bool
    public var soundsEnabled: Bool
    public var notchModeEnabled: Bool
    public var language: AppLanguage
    public var menuBarTimerEnabled: Bool

    public init(focusDuration: TimeInterval = 25 * 60, shortBreakDuration: TimeInterval = 5 * 60, longBreakDuration: TimeInterval = 15 * 60, notificationsEnabled: Bool = false, soundsEnabled: Bool = false, notchModeEnabled: Bool = true, language: AppLanguage = .english, menuBarTimerEnabled: Bool = false) {
        self.focusDuration = focusDuration
        self.shortBreakDuration = shortBreakDuration
        self.longBreakDuration = longBreakDuration
        self.notificationsEnabled = notificationsEnabled
        self.soundsEnabled = soundsEnabled
        self.notchModeEnabled = notchModeEnabled
        self.language = language
        self.menuBarTimerEnabled = menuBarTimerEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case focusDuration, shortBreakDuration, longBreakDuration, notificationsEnabled, soundsEnabled, notchModeEnabled, language, menuBarTimerEnabled
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        focusDuration = try values.decode(TimeInterval.self, forKey: .focusDuration)
        shortBreakDuration = try values.decode(TimeInterval.self, forKey: .shortBreakDuration)
        longBreakDuration = try values.decode(TimeInterval.self, forKey: .longBreakDuration)
        notificationsEnabled = try values.decode(Bool.self, forKey: .notificationsEnabled)
        soundsEnabled = try values.decodeIfPresent(Bool.self, forKey: .soundsEnabled) ?? false
        notchModeEnabled = try values.decodeIfPresent(Bool.self, forKey: .notchModeEnabled) ?? true
        language = (try? values.decodeIfPresent(AppLanguage.self, forKey: .language)) ?? .english
        menuBarTimerEnabled = try values.decodeIfPresent(Bool.self, forKey: .menuBarTimerEnabled) ?? false
    }

    public var isValid: Bool {
        [focusDuration, shortBreakDuration, longBreakDuration].allSatisfy { $0.isFinite && $0 > 0 && $0 <= 86_400 }
    }

    public func duration(for kind: FocusSession.Kind) -> TimeInterval {
        switch kind {
        case .focus: focusDuration
        case .shortBreak: shortBreakDuration
        case .longBreak: longBreakDuration
        }
    }

    public static let defaults = FocusSettings()
}

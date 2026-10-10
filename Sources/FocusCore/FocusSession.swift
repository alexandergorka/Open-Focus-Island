import Foundation

public struct FocusSession: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case focus, shortBreak, longBreak }
    public enum State: String, Codable, Sendable { case idle, running, paused, completed }

    public private(set) var id = UUID()
    public private(set) var kind: Kind = .focus
    public private(set) var state: State = .idle
    public private(set) var taskName: String?
    public private(set) var startedAt: Date?
    public private(set) var targetEnd: Date?
    public private(set) var plannedDuration: TimeInterval = 0
    public private(set) var pausedAt: Date?
    public private(set) var completedAt: Date?
    public private(set) var completedFocusCount = 0
    private var longBreakStartedAtCount: Int?

    public var isValid: Bool {
        guard completedFocusCount >= 0, completedFocusCount < .max,
              longBreakStartedAtCount.map({ $0 >= 0 && $0 <= completedFocusCount }) ?? true,
              taskName.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) }) ?? true,
              [startedAt, targetEnd, pausedAt, completedAt].compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite }) else { return false }

        switch state {
        case .idle:
            return startedAt == nil && targetEnd == nil && pausedAt == nil && completedAt == nil && taskName == nil && plannedDuration == 0
        case .running, .paused:
            guard validDuration(plannedDuration), let startedAt, let targetEnd, targetEnd > startedAt, completedAt == nil else { return false }
            if state == .running { return pausedAt == nil }
            guard let pausedAt else { return false }
            return pausedAt >= startedAt && pausedAt < targetEnd
        case .completed:
            guard validDuration(plannedDuration), let startedAt, let targetEnd, let completedAt,
                  targetEnd > startedAt, completedAt >= startedAt else { return false }
            return pausedAt.map { $0 >= startedAt && $0 < targetEnd } ?? true
        }
    }

    public var recommendedBreak: Kind {
        completedFocusCount > 0 && completedFocusCount.isMultiple(of: 4) && longBreakStartedAtCount != completedFocusCount
            ? .longBreak : .shortBreak
    }

    public var didFullyElapse: Bool {
        guard state == .completed, pausedAt == nil, let targetEnd, let completedAt else { return false }
        return completedAt == targetEnd
    }

    public init() {}

    public func remaining(now: Date) -> TimeInterval {
        guard state == .running, let targetEnd else { return state == .paused ? max(0, targetEnd?.timeIntervalSince(pausedAt ?? now) ?? 0) : 0 }
        return max(0, targetEnd.timeIntervalSince(now))
    }

    @discardableResult
    public mutating func start(kind: Kind, duration: TimeInterval, taskName: String? = nil, at date: Date) -> Bool {
        guard state == .idle || state == .completed, validDuration(duration), date.timeIntervalSince1970.isFinite else { return false }
        let targetEnd = date.addingTimeInterval(duration)
        guard targetEnd.timeIntervalSince1970.isFinite, targetEnd > date else { return false }
        self.id = UUID()
        self.kind = kind
        self.state = .running
        self.taskName = taskName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.startedAt = date
        self.targetEnd = targetEnd
        self.plannedDuration = duration
        self.pausedAt = nil
        self.completedAt = nil
        if kind == .longBreak { longBreakStartedAtCount = completedFocusCount }
        return true
    }

    @discardableResult
    public mutating func pause(at date: Date) -> Bool {
        guard state == .running, let startedAt,
              validEventDate(date, notBefore: startedAt) else { return false }
        guard reconcile(at: date) == false else { return false }
        pausedAt = date
        state = .paused
        return true
    }

    @discardableResult
    public mutating func resume(at date: Date) -> Bool {
        guard state == .paused, let startedAt, let pausedAt, let targetEnd,
              validEventDate(date, notBefore: pausedAt) else { return false }
        let extensionDuration = date.timeIntervalSince(pausedAt)
        let resumedTargetEnd = targetEnd.addingTimeInterval(extensionDuration)
        guard extensionDuration.isFinite, validEventDate(resumedTargetEnd, notBefore: startedAt) else { return false }
        self.targetEnd = resumedTargetEnd
        self.pausedAt = nil
        state = .running
        return true
    }

    @discardableResult
    public mutating func finish(at date: Date) -> Bool {
        guard state == .running || state == .paused, let startedAt,
              validEventDate(date, notBefore: startedAt) else { return false }
        if state == .paused, let pausedAt, !validEventDate(date, notBefore: pausedAt) { return false }
        if state == .running, reconcile(at: date) { return false }
        state = .completed
        completedAt = date
        return true
    }

    @discardableResult
    public mutating func skipToBreak(shortDuration: TimeInterval, longDuration: TimeInterval, at date: Date) -> Bool {
        guard kind == .focus, state == .running || state == .paused || state == .completed,
              let startedAt, validEventDate(date, notBefore: startedAt) else { return false }
        if let actionFloor = state == .paused ? pausedAt : (state == .completed ? completedAt : nil),
           !validEventDate(date, notBefore: actionFloor) { return false }
        if state == .running, reconcile(at: date) { return false }
        let breakKind = recommendedBreak
        let duration = breakKind == .longBreak ? longDuration : shortDuration
        guard validDuration(duration), date.timeIntervalSince1970.isFinite else { return false }
        let targetEnd = date.addingTimeInterval(duration)
        guard targetEnd.timeIntervalSince1970.isFinite, targetEnd > date else { return false }
        state = .completed
        return start(kind: breakKind, duration: duration, at: date)
    }

    @discardableResult
    public mutating func reconcile(at date: Date) -> Bool {
        guard state == .running, let targetEnd,
              targetEnd.timeIntervalSince1970.isFinite,
              date.timeIntervalSince1970.isFinite, date >= targetEnd else { return false }
        state = .completed
        completedAt = targetEnd
        if kind == .focus, completedFocusCount < .max { completedFocusCount += 1 }
        return true
    }
}

private func validDuration(_ duration: TimeInterval) -> Bool {
    duration.isFinite && duration > 0 && duration <= 86_400
}

private func validEventDate(_ date: Date, notBefore lowerBound: Date) -> Bool {
    date.timeIntervalSince1970.isFinite && lowerBound.timeIntervalSince1970.isFinite && date >= lowerBound
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

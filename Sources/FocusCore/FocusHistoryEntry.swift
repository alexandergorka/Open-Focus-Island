import Foundation

public struct FocusHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let taskName: String?
    public let startedAt: Date
    public let completedAt: Date
    public let plannedDuration: TimeInterval

    public init?(session: FocusSession) {
        guard session.isValid, session.kind == .focus, session.didFullyElapse,
              let startedAt = session.startedAt, let completedAt = session.completedAt,
              Self.isValid(taskName: session.taskName, startedAt: startedAt, completedAt: completedAt, plannedDuration: session.plannedDuration) else { return nil }
        id = session.id
        taskName = session.taskName
        self.startedAt = startedAt
        self.completedAt = completedAt
        plannedDuration = session.plannedDuration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let taskName = try container.decodeIfPresent(String.self, forKey: .taskName)
        let startedAt = try container.decode(Date.self, forKey: .startedAt)
        let completedAt = try container.decode(Date.self, forKey: .completedAt)
        let plannedDuration = try container.decode(TimeInterval.self, forKey: .plannedDuration)
        guard Self.isValid(taskName: taskName, startedAt: startedAt, completedAt: completedAt, plannedDuration: plannedDuration) else {
            throw DecodingError.dataCorruptedError(forKey: .plannedDuration, in: container, debugDescription: "Invalid focus history entry")
        }
        self.id = id
        self.taskName = taskName
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.plannedDuration = plannedDuration
    }

    private static func isValid(taskName: String?, startedAt: Date, completedAt: Date, plannedDuration: TimeInterval) -> Bool {
        startedAt.timeIntervalSince1970.isFinite && completedAt.timeIntervalSince1970.isFinite && completedAt > startedAt &&
            plannedDuration.isFinite && plannedDuration > 0 && plannedDuration <= 86_400 &&
            (taskName.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? true)
    }
}

import Foundation

public enum Priority: String, Codable, CaseIterable, Sendable {
    case low
    case normal
    case high

    public var sortOrder: Int {
        switch self {
        case .high: return 0
        case .normal: return 1
        case .low: return 2
        }
    }

    public var label: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        }
    }
}

public struct TodoTask: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String?
    public var scheduledDate: Date
    public var isCompleted: Bool
    public var completedAt: Date?
    public var createdAt: Date
    public var priority: Priority

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        scheduledDate: Date = Calendar.current.startOfDay(for: Date()),
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        createdAt: Date = Date(),
        priority: Priority = .normal
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.scheduledDate = Calendar.current.startOfDay(for: scheduledDate)
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.priority = priority
    }
}

public struct TaskFile: Codable, Sendable {
    public var version: Int
    public var tasks: [TodoTask]

    public init(version: Int = 1, tasks: [TodoTask] = []) {
        self.version = version
        self.tasks = tasks
    }
}

import Foundation

public struct DeadlineTask: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var projectID: UUID
    public var dueDate: Date
    public var createdAt: Date
    public var completedAt: Date?
    public init(id: UUID = UUID(), title: String, projectID: UUID, dueDate: Date, createdAt: Date = Date(), completedAt: Date? = nil) {
        self.id = id; self.title = title; self.projectID = projectID; self.dueDate = dueDate
        self.createdAt = createdAt; self.completedAt = completedAt
    }
    public func daysRemaining(at now: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: dueDate)).day ?? 0
    }
}

public struct DeadlineStatistics {
    public var seconds: Double = 0
    public var daily: [Date: Double] = [:]
    public var hourly: [Int: Double] = [:]
    public var firstWorked: Date?
    public var sessions = 0
    public init(entries: [Entry], now: Date, calendar: Calendar = .current) {
        var focusIDs = Set<UUID>()
        for entry in entries {
            let end = entry.end ?? now
            guard end > entry.start else { continue }
            focusIDs.insert(entry.focusID)
            firstWorked = min(firstWorked ?? entry.start, entry.start)
            seconds += end.timeIntervalSince(entry.start)
            var cursor = entry.start
            while cursor < end {
                guard let hour = calendar.dateInterval(of: .hour, for: cursor) else { break }
                let next = min(hour.end, end)
                let duration = next.timeIntervalSince(cursor)
                daily[calendar.startOfDay(for: cursor), default: 0] += duration
                hourly[calendar.component(.hour, from: cursor), default: 0] += duration
                cursor = next
            }
        }
        sessions = focusIDs.count
    }
}

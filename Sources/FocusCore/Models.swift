import Foundation

public struct Project: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var parentID: UUID?
    public var weeklyGoal: Double
    public var color: Int
    public init(id: UUID = UUID(), name: String, parentID: UUID? = nil, weeklyGoal: Double = 0, color: Int = 0) {
        self.id = id; self.name = name; self.parentID = parentID
        self.weeklyGoal = weeklyGoal; self.color = color
    }
}

public struct Entry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var projectID: UUID
    public var focusID: UUID
    public var start: Date
    public var end: Date?
    public var note: String
    public var deadlineID: UUID?
    public init(id: UUID = UUID(), projectID: UUID, focusID: UUID = UUID(), start: Date, end: Date? = nil, note: String = "", deadlineID: UUID? = nil) {
        self.id = id; self.projectID = projectID; self.focusID = focusID
        self.start = start; self.end = end; self.note = note; self.deadlineID = deadlineID
    }
}

public struct IdleReview: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var projectID: UUID
    public var focusID: UUID
    public var start: Date
    public var reason: String
    public var returnedAt: Date?
    public init(projectID: UUID, focusID: UUID, start: Date, reason: String) {
        self.projectID = projectID; self.focusID = focusID; self.start = start; self.reason = reason
    }
}

public struct Notebook: Codable, Equatable, Sendable {
    public var deadlines: [DeadlineTask] = []
    public var projects: [Project] = []
    public var entries: [Entry] = []
    public var review: IdleReview?
    public var heartbeat: Date = Date()
    public var idleMinutes: Double = 10
    public init() {}
    enum CodingKeys: String, CodingKey { case projects, entries, review, heartbeat, idleMinutes, deadlines }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projects = try c.decode([Project].self, forKey: .projects)
        entries = try c.decode([Entry].self, forKey: .entries)
        review = try c.decodeIfPresent(IdleReview.self, forKey: .review)
        heartbeat = try c.decode(Date.self, forKey: .heartbeat)
        idleMinutes = try c.decode(Double.self, forKey: .idleMinutes)
        deadlines = try c.decodeIfPresent([DeadlineTask].self, forKey: .deadlines) ?? []
    }
}

public enum TimeMath {
    public static func idleCutoff(sessionStart: Date, now: Date, idleSeconds: Double, threshold: Double) -> Date? {
        guard idleSeconds.isFinite else { return nil }
        let cutoff = max(sessionStart, now.addingTimeInterval(-max(0, idleSeconds)))
        return now.timeIntervalSince(cutoff) >= threshold ? cutoff : nil
    }
    public static var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }
    public static func week(containing date: Date, calendar: Calendar = calendar) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date)!
    }
    public static func descendants(of id: UUID, projects: [Project]) -> Set<UUID> {
        var result: Set<UUID> = [id]
        var pending = [id]
        while let parent = pending.popLast() {
            for p in projects where p.parentID == parent && !result.contains(p.id) {
                result.insert(p.id); pending.append(p.id)
            }
        }
        return result
    }
    public static func seconds(_ entries: [Entry], in interval: DateInterval, projectIDs: Set<UUID>? = nil, now: Date = Date()) -> Double {
        entries.filter { projectIDs == nil || projectIDs!.contains($0.projectID) }.reduce(0) { total, e in
            total + max(0, min(e.end ?? now, interval.end).timeIntervalSince(max(e.start, interval.start)))
        }
    }
    public static func overlaps(_ entry: Entry, entries: [Entry], now: Date = Date()) -> Bool {
        entries.contains { other in
            other.id != entry.id && entry.start < (other.end ?? now) && (entry.end ?? now) > other.start
        }
    }
    public static func duration(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) }
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

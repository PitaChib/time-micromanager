import Foundation

public struct ReportCategory: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let color: Int
    public let seconds: Double
}

public struct ReportDay: Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let secondsByCategory: [UUID: Double]
    public var seconds: Double { secondsByCategory.values.reduce(0, +) }
}

public struct TimeReport: Sendable {
    public let categories: [ReportCategory]
    public let projectDetails: [ReportCategory]
    public let days: [ReportDay]
    public var seconds: Double { categories.reduce(0) { $0 + $1.seconds } }

    public init(entries: [Entry], projects: [Project], range: DateInterval,
                projectID: UUID? = nil, now: Date, calendar: Calendar = TimeMath.calendar) {
        // A parent contributes its own direct time plus separate child rollups.
        // At the top level, each category contains its entire subtree once.
        var groups: [(project: Project, ids: Set<UUID>, name: String)] = []
        if let parent = projects.first(where: { $0.id == projectID }) {
            groups.append((parent, [parent.id], "\(parent.name) · direct time"))
        }
        for project in projects where project.parentID == projectID {
            groups.append((project, TimeMath.descendants(of: project.id, projects: projects), project.name))
        }
        categories = groups.map { group in
            ReportCategory(id: group.project.id, name: group.name, color: group.project.color,
                           seconds: TimeMath.seconds(entries, in: range, projectIDs: group.ids, now: now))
        }
        let selectedIDs = projectID.map { TimeMath.descendants(of: $0, projects: projects) }
        projectDetails = projects.filter { selectedIDs == nil || selectedIDs!.contains($0.id) }.map { project in
            ReportCategory(id: project.id, name: project.name, color: project.color,
                           seconds: TimeMath.seconds(entries, in: range, projectIDs: [project.id], now: now))
        }.filter { $0.seconds > 0 }

        // Keep longer reports readable; full-range category totals remain above.
        let chartEnd = min(range.end, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!)
        let lastDay = calendar.startOfDay(for: chartEnd.addingTimeInterval(-0.001))
        var day = max(calendar.startOfDay(for: range.start), calendar.date(byAdding: .day, value: -30, to: lastDay)!)
        var result: [ReportDay] = []
        // Weekly ranges include all seven days, including future zero-hour days.
        let isWeek = range == TimeMath.week(containing: range.start, calendar: calendar)
        let end = isWeek ? range.end : chartEnd
        if isWeek { day = range.start }
        while day < end {
            let next = calendar.date(byAdding: .day, value: 1, to: day)!
            let interval = DateInterval(start: max(day, range.start), end: min(next, range.end))
            let values = groups.map { group in
                (group.project.id, TimeMath.seconds(entries, in: interval, projectIDs: group.ids, now: now))
            }
            result.append(ReportDay(date: day, secondsByCategory: Dictionary(uniqueKeysWithValues: values)))
            day = next
        }
        days = result
    }
}

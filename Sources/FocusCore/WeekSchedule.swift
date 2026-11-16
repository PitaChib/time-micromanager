import Foundation

public struct TimelineSegment: Identifiable, Sendable {
    public struct ID: Hashable, Sendable {
        let entry: UUID
        let start: Date
    }
    public var id: ID { ID(entry: entryID, start: start) }
    public let entryID: UUID
    public let projectID: UUID
    public let projectName: String
    public let color: Int
    public let day: Date
    public let start: Date
    public let end: Date
    public let startMinute: Double
    public let endMinute: Double
}

public struct TimelineAxis: Sendable {
    public let startMinute: Double
    public let endMinute: Double

    public init(segments: [TimelineSegment]) {
        startMinute = min(330, floor((segments.map(\.startMinute).min() ?? 330) / 30) * 30)
        endMinute = max(1320, ceil((segments.map(\.endMinute).max() ?? 1320) / 30) * 30)
    }
    public var labelMinutes: [Double] {
        let first = ceil((startMinute + 60) / 120) * 120
        let middle = stride(from: first, through: endMinute - 60, by: 120)
        return [startMinute] + Array(middle) + [endMinute]
    }
    public var gridMinutes: [Double] {
        let hours = stride(from: ceil(startMinute / 60) * 60, through: endMinute, by: 60)
        return Array(Set(Array(hours) + labelMinutes)).sorted()
    }
}

public enum WeekSchedule {
    public static func segments(entries: [Entry], projects: [Project], range: DateInterval,
                                now: Date, calendar: Calendar = TimeMath.calendar) -> [TimelineSegment] {
        let byID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        var result: [TimelineSegment] = []
        for entry in entries {
            guard let project = byID[entry.projectID] else { continue }
            var start = max(entry.start, range.start)
            let end = min(entry.end ?? now, range.end, now)
            while start < end {
                let day = calendar.startOfDay(for: start)
                let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
                var finish = min(nextDay, end)
                // A clock change needs its own piece so clock coordinates stay valid.
                if let change = calendar.timeZone.nextDaylightSavingTimeTransition(after: start), change > start {
                    finish = min(finish, change)
                }
                let clock = calendar.dateComponents([.hour, .minute, .second], from: start)
                let startMinute = Double(clock.hour! * 60 + clock.minute!) + Double(clock.second!) / 60
                let endMinute = min(1440, startMinute + finish.timeIntervalSince(start) / 60)
                result.append(TimelineSegment(entryID: entry.id, projectID: project.id,
                                              projectName: project.name, color: project.color, day: day,
                                              start: start, end: finish,
                                              startMinute: startMinute, endMinute: endMinute))
                start = finish
            }
        }
        return result.sorted { $0.start == $1.start ? $0.entryID.uuidString < $1.entryID.uuidString : $0.start < $1.start }
    }
}

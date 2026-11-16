import Foundation

public extension Notebook {
    var activeEntry: Entry? { entries.first { $0.end == nil } }

    mutating func start(projectID: UUID, focusID: UUID = UUID(), at date: Date, deadlineID: UUID? = nil) {
        guard review == nil, projects.contains(where: { $0.id == projectID }) else { return }
        stop(at: date)
        let taskID = deadlineID ?? entries.last(where: { $0.focusID == focusID })?.deadlineID
        entries.append(Entry(projectID: projectID, focusID: focusID, start: date, deadlineID: taskID))
        heartbeat = date
    }

    mutating func stop(at date: Date) {
        for i in entries.indices where entries[i].end == nil {
            entries[i].end = max(entries[i].start, date)
        }
        heartbeat = date
    }

    @discardableResult
    mutating func describeTimeChunk(focusID: UUID, note: String) -> Bool {
        let description = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard activeEntry == nil, review == nil, !description.isEmpty,
              entries.contains(where: { $0.focusID == focusID }) else { return false }
        for i in entries.indices where entries[i].focusID == focusID {
            entries[i].note = description
        }
        return true
    }

    @discardableResult
    mutating func discardPausedSession(focusID: UUID) -> Bool {
        guard activeEntry == nil, review == nil,
              entries.contains(where: { $0.focusID == focusID }) else { return false }
        entries.removeAll { $0.focusID == focusID }
        return true
    }

    mutating func pauseForReview(at date: Date, reason: String) {
        guard let active = activeEntry, review == nil else { return }
        let cutoff = max(active.start, date)
        stop(at: cutoff)
        review = IdleReview(projectID: active.projectID, focusID: active.focusID, start: cutoff, reason: reason)
    }

    mutating func recoverAfterRelaunch() {
        guard activeEntry != nil else { return }
        pauseForReview(at: heartbeat, reason: "The app closed while this timer was running.")
    }

    mutating func markReturned(at date: Date) {
        guard review != nil, review?.returnedAt == nil else { return }
        review?.returnedAt = date
    }

    mutating func resolveReview(countUntil end: Date?, resume: Bool, at now: Date) {
        guard let pending = review else { return }
        if let end, end > pending.start {
            entries.append(Entry(projectID: pending.projectID, focusID: pending.focusID,
                                 start: pending.start, end: min(end, now), note: "Reviewed away time", deadlineID: entries.last(where: { $0.focusID == pending.focusID })?.deadlineID))
        }
        review = nil
        if resume { start(projectID: pending.projectID, focusID: pending.focusID, at: now) }
    }
}

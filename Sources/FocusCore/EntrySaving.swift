import Foundation

public enum EntrySaveResult: Equatable {
    case saved
    case invalid(String)
    case conflicts([Entry])
}

public extension Notebook {
    mutating func saveEntry(_ entry: Entry, overrideOverlaps: Bool = false, now: Date = Date()) -> EntrySaveResult {
        guard review == nil else { return .invalid("Review your away time before editing entries.") }
        guard let end = entry.end, end > entry.start else { return .invalid("End time must be after start time.") }
        guard end <= now else { return .invalid("Recorded time cannot end in the future.") }
        let conflicts = entries.filter {
            $0.id != entry.id && $0.start < end && ($0.end ?? now) > entry.start
        }
        guard conflicts.isEmpty || overrideOverlaps else { return .conflicts(conflicts) }

        let conflictingIDs = Set(conflicts.map(\.id))
        var updated: [Entry] = []
        for existing in entries where existing.id != entry.id {
            guard conflictingIDs.contains(existing.id) else { updated.append(existing); continue }
            let hasLeftPortion = existing.start < entry.start
            if hasLeftPortion {
                var left = existing
                left.end = entry.start
                updated.append(left)
            }
            // An active timer keeps running after the overridden interval.
            if existing.end == nil || existing.end! > end {
                var right = existing
                right.start = end
                if hasLeftPortion { right.id = UUID() }
                updated.append(right)
            }
        }
        updated.append(entry)
        entries = updated
        return .saved
    }
}

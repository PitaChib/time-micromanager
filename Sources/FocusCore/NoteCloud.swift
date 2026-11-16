import Foundation

public struct NoteWord: Identifiable, Sendable {
    public var id: String { word }
    public let word: String
    public let mentions: Int
    public let categoryID: UUID
    public let categoryName: String
    public let color: Int
}

public enum NoteCloud {
    private struct NoteKey: Hashable {
        let session: UUID
        let project: UUID
        let text: String
    }
    private static let stopWords: Set<String> = Set("""
        a an and are as at be been being but by can could did do does doing for from
        had has have having he her here hers him his how i if in into is it its just
        me more most my no not of on or our ours out over she so some than that the
        their theirs them then there these they this those through to too under up
        us very was we were what when where which while who why will with would
        you your yours i'm i've i'll it's don't didn't wasn't weren't isn't aren't
        """.split(whereSeparator: \.isWhitespace).map(String.init))

    public static func words(entries: [Entry], projects: [Project], range: DateInterval, now: Date) -> [NoteWord] {
        var categoryForProject: [UUID: Project] = [:]
        let roots = projects.filter { $0.parentID == nil }
        for root in roots {
            for id in TimeMath.descendants(of: root.id, projects: projects) {
                categoryForProject[id] = root
            }
        }
        var seen: Set<NoteKey> = []
        var counts: [String: [UUID: Int]] = [:]
        for entry in entries where entry.start < min(range.end, now) && (entry.end ?? now) > range.start {
            guard let category = categoryForProject[entry.projectID] else { continue }
            let text = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased().replacingOccurrences(of: "’", with: "'")
            guard !text.isEmpty,
                  seen.insert(NoteKey(session: entry.focusID, project: entry.projectID, text: text)).inserted else { continue }
            var tokens: Set<String> = []
            text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { word, _, _, _ in
                guard let word, word.count > 1, word.unicodeScalars.contains(where: CharacterSet.letters.contains),
                      !stopWords.contains(word) else { return }
                tokens.insert(word)
            }
            for word in tokens { counts[word, default: [:]][category.id, default: 0] += 1 }
        }
        return counts.compactMap { word, mentions in
            // Stable project order breaks ties so colors never flicker between updates.
            guard let root = roots.max(by: { (mentions[$0.id] ?? 0) < (mentions[$1.id] ?? 0) }) else { return nil }
            return NoteWord(word: word, mentions: mentions.values.reduce(0, +),
                            categoryID: root.id, categoryName: root.name, color: root.color)
        }.sorted { a, b in
            a.mentions == b.mentions ? a.word < b.word : a.mentions > b.mentions
        }.prefix(40).map { $0 }
    }
}

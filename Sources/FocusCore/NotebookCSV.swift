import Foundation

/// Versioned, lossless CSV backup. Dates are seconds since 2001-01-01 UTC (Foundation reference date); empty means absent.
public enum NotebookCSV {
    public static let header = ["type", "id", "name_or_note", "project_id", "parent_or_deadline_id", "focus_id", "start_or_created", "end_or_completed", "due", "weekly_goal", "color", "heartbeat", "idle_minutes", "review_json"]
    public enum Failure: LocalizedError {
        case invalid(String)
        public var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
    }
    public static func encode(_ book: Notebook) throws -> String {
        func date(_ d: Date?) -> String { d.map { String($0.timeIntervalSinceReferenceDate) } ?? "" }
        var rows = [header]
        let review = try book.review.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) } ?? ""
        rows.append(["notebook_v1", "", "", "", "", "", "", "", "", "", "", date(book.heartbeat), String(book.idleMinutes), review])
        for p in book.projects { rows.append(["project", p.id.uuidString, p.name, "", p.parentID?.uuidString ?? "", "", "", "", "", String(p.weeklyGoal), String(p.color), "", "", ""]) }
        for t in book.deadlines { rows.append(["deadline", t.id.uuidString, t.title, t.projectID.uuidString, "", "", date(t.createdAt), date(t.completedAt), date(t.dueDate), "", "", "", "", ""]) }
        for e in book.entries { rows.append(["entry", e.id.uuidString, e.note, e.projectID.uuidString, e.deadlineID?.uuidString ?? "", e.focusID.uuidString, date(e.start), date(e.end), "", "", "", "", "", ""]) }
        return rows.map { $0.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
    public static func decode(_ text: String) throws -> Notebook {
        let rows = try parse(text)
        guard rows.first == header else { throw Failure.invalid("This is not a FocusNest CSV backup (unsupported header).") }
        var book = Notebook(); var metadata = false
        func uuid(_ s: String) throws -> UUID { guard let v = UUID(uuidString: s) else { throw Failure.invalid("Invalid identifier.") }; return v }
        func date(_ s: String) throws -> Date { guard let v = Double(s), v.isFinite, abs(v) < 1e11 else { throw Failure.invalid("Invalid date.") }; return Date(timeIntervalSinceReferenceDate: v) }
        for r in rows.dropFirst() {
            guard r.count == header.count else { throw Failure.invalid("A CSV row has the wrong number of fields.") }
            switch r[0] {
            case "notebook_v1":
                guard !metadata, let idle = Double(r[12]), idle.isFinite, idle > 0 else { throw Failure.invalid("Invalid notebook settings.") }
                metadata = true; book.heartbeat = try date(r[11]); book.idleMinutes = idle
                if !r[13].isEmpty { book.review = try JSONDecoder().decode(IdleReview.self, from: Data(r[13].utf8)) }
            case "project":
                guard let goal = Double(r[9]), goal.isFinite, goal >= 0, let color = Int(r[10]), !r[2].isEmpty else { throw Failure.invalid("Invalid project.") }
                book.projects.append(try Project(id: uuid(r[1]), name: r[2], parentID: r[4].isEmpty ? nil : uuid(r[4]), weeklyGoal: goal, color: color))
            case "deadline":
                guard !r[2].isEmpty else { throw Failure.invalid("Missing deadline title.") }
                book.deadlines.append(try DeadlineTask(id: uuid(r[1]), title: r[2], projectID: uuid(r[3]), dueDate: date(r[8]), createdAt: date(r[6]), completedAt: r[7].isEmpty ? nil : date(r[7])))
            case "entry":
                book.entries.append(try Entry(id: uuid(r[1]), projectID: uuid(r[3]), focusID: uuid(r[5]), start: date(r[6]), end: r[7].isEmpty ? nil : date(r[7]), note: r[2], deadlineID: r[4].isEmpty ? nil : uuid(r[4])))
            default: throw Failure.invalid("Unknown CSV record type.")
            }
        }
        guard metadata else { throw Failure.invalid("Missing notebook settings.") }
        try validate(book)
        return book
    }
    public static func validate(_ book: Notebook) throws {
        let projects = Set(book.projects.map(\.id)), tasks = Dictionary(book.deadlines.map { ($0.id, $0.projectID) }, uniquingKeysWith: { a, _ in a })
        guard projects.count == book.projects.count, tasks.count == book.deadlines.count, Set(book.entries.map(\.id)).count == book.entries.count else { throw Failure.invalid("Duplicate record identifiers.") }
        for p in book.projects {
            var seen: Set<UUID> = [p.id]; var parent = p.parentID
            while let id = parent {
                guard projects.contains(id), seen.insert(id).inserted else { throw Failure.invalid("Missing parent or project cycle.") }
                parent = book.projects.first { $0.id == id }?.parentID
            }
        }
        guard book.deadlines.allSatisfy({ projects.contains($0.projectID) }), book.entries.allSatisfy({ e in projects.contains(e.projectID) && (e.end == nil || e.end! >= e.start) && (e.deadlineID == nil || tasks[e.deadlineID!] == e.projectID) }), book.entries.filter({ $0.end == nil }).count <= 1 else { throw Failure.invalid("Invalid time range or missing project/deadline reference.") }
        if let r = book.review {
            guard projects.contains(r.projectID), book.activeEntry == nil else { throw Failure.invalid("Invalid away review.") }
        }
    }
    static func parse(_ text: String) throws -> [[String]] {
        let chars = Array(text); var rows: [[String]] = []; var row: [String] = []; var field = ""; var quoted = false; var closed = false; var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append(c); i += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(c) }
            } else if c == "," { row.append(field); field = ""; closed = false }
            else if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(field); rows.append(row); row = []; field = ""; closed = false
            } else if c == "\"" && field.isEmpty && !closed { quoted = true }
            else {
                guard !closed, c != "\"" else { throw Failure.invalid("Malformed CSV quoting.") }
                field.append(c)
            }
            i += 1
        }
        guard !quoted else { throw Failure.invalid("Unclosed CSV quote.") }
        if !row.isEmpty || !field.isEmpty || closed { row.append(field); rows.append(row) }
        return rows
    }
}

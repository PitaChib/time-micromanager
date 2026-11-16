import Foundation
import FocusCore

struct Failure: Error { let message: String }
func check(_ condition: Bool, _ message: String) throws { if !condition { throw Failure(message: message) } }
func rejects(_ operation: () throws -> Void) throws {
    do { try operation() } catch { return }
    throw Failure(message: "Expected rejection")
}
let origin = Date(timeIntervalSince1970: 1_700_000_000)
func fixture() -> Notebook {
    var b = Notebook(); let p = Project(name: "Grant, \"writing\"\n研究")
    b.projects = [p]; b.heartbeat = origin
    let task = DeadlineTask(title: "Grant application", projectID: p.id, dueDate: origin.addingTimeInterval(86400), createdAt: origin)
    b.deadlines = [task]
    b.entries = [Entry(projectID: p.id, start: origin, end: origin.addingTimeInterval(3600), note: "Draft, \"aims\"\r\n第二段", deadlineID: task.id)]
    return b
}
let tests: [(String, () throws -> Void)] = [
    ("Legacy JSON migration preserves entries", {
        let b = fixture(); var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(b)) as! [String: Any]
        object.removeValue(forKey: "deadlines")
        var entries = object["entries"] as! [[String: Any]]; entries[0].removeValue(forKey: "deadlineID"); object["entries"] = entries
        let decoded = try JSONDecoder().decode(Notebook.self, from: JSONSerialization.data(withJSONObject: object))
        try check(decoded.deadlines.isEmpty && decoded.entries[0].id == b.entries[0].id && decoded.entries[0].deadlineID == nil, "Legacy records changed")
    }),
    ("CSV lossless Unicode/quotes/newlines round trip", {
        var b = fixture(); b.deadlines[0].completedAt = origin.addingTimeInterval(7200)
        try check(try NotebookCSV.decode(NotebookCSV.encode(b)) == b, "Round trip mismatch")
    }),
    ("CSV pending review and active timer snapshots", {
        var b = fixture(); b.start(projectID: b.projects[0].id, at: origin.addingTimeInterval(4000), deadlineID: b.deadlines[0].id)
        try check(try NotebookCSV.decode(NotebookCSV.encode(b)) == b, "Active timer mismatch")
        b.pauseForReview(at: origin.addingTimeInterval(4500), reason: "Idle, review")
        try check(try NotebookCSV.decode(NotebookCSV.encode(b)) == b, "Review mismatch")
    }),
    ("CSV rejects malformed, duplicate and dangling records", {
        let b = fixture(); let csv = try NotebookCSV.encode(b)
        try rejects { _ = try NotebookCSV.decode(csv + "\"broken") }
        try rejects { _ = try NotebookCSV.decode("unknown\n") }
        var duplicate = b; duplicate.entries += b.entries
        try rejects { _ = try NotebookCSV.decode(NotebookCSV.encode(duplicate)) }
        var orphan = b; orphan.entries[0].deadlineID = UUID()
        try rejects { _ = try NotebookCSV.decode(NotebookCSV.encode(orphan)) }
        var cycle = b; cycle.projects[0].parentID = cycle.projects[0].id
        try rejects { _ = try NotebookCSV.decode(NotebookCSV.encode(cycle)) }
    }),
    ("Timer switches, pause/resume and review retain task identity", {
        var b = fixture(); let p = b.projects[0].id; let task = b.deadlines[0].id
        let focus = UUID(); b.start(projectID: p, focusID: focus, at: origin.addingTimeInterval(4000), deadlineID: task)
        b.pauseForReview(at: origin.addingTimeInterval(4500), reason: "Idle")
        b.resolveReview(countUntil: origin.addingTimeInterval(4600), resume: true, at: origin.addingTimeInterval(4700))
        try check(b.entries.filter { $0.focusID == focus }.allSatisfy { $0.deadlineID == task }, "Review lost task")
        b.start(projectID: p, at: origin.addingTimeInterval(4800))
        try check(b.activeEntry?.deadlineID == nil && b.entries.filter { $0.end == nil }.count == 1, "Switch leaked attribution")
    }),
    ("Task totals and hourly/day splits reconcile without double counting", {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 23, minute: 30))!
        let e = Entry(projectID: UUID(), start: start, end: start.addingTimeInterval(7200))
        let s = DeadlineStatistics(entries: [e], now: start, calendar: calendar)
        try check(s.seconds == 7200 && s.daily.count == 2 && s.hourly[23] == 1800 && s.hourly[0] == 3600 && s.hourly[1] == 1800, "Boundary allocation wrong")
        try check(s.daily.values.reduce(0,+) == s.seconds && s.sessions == 1, "Totals wrong")
    }),
    ("Countdown uses calendar days across daylight saving", {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Chicago")!
        let now = c.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 23))!
        let due = c.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 1))!
        let t = DeadlineTask(title: "Due", projectID: UUID(), dueDate: due)
        try check(t.daysRemaining(at: now, calendar: c) == 2 && t.daysRemaining(at: due, calendar: c) == 0, "Countdown wrong")
    }),
    ("Override split preserves deadline links", {
        var b = fixture(); let original = b.entries[0]
        let replacement = Entry(projectID: original.projectID, start: origin.addingTimeInterval(600), end: origin.addingTimeInterval(1200))
        _ = b.saveEntry(replacement, overrideOverlaps: true, now: origin.addingTimeInterval(7200))
        try check(b.entries.filter { $0.deadlineID == original.deadlineID }.count == 2, "Split lost task links")
    })
]
var failures = 0
for (name, test) in tests { do { try test(); print("PASS: \(name)") } catch { failures += 1; print("FAIL: \(name): \(error)") } }
print("\(tests.count - failures)/\(tests.count) deadline/CSV checks passed")
if failures > 0 { exit(1) }
if CommandLine.arguments.contains("--benchmark") {
    for count in [1_000, 20_000, 100_000] {
        var b = fixture(); let template = b.entries[0]
        b.entries = (0..<count).map { i in Entry(projectID: template.projectID, start: origin.addingTimeInterval(Double(i) * 3600), end: origin.addingTimeInterval(Double(i) * 3600 + 1800), note: "Grant drafting", deadlineID: template.deadlineID) }
        let start = Date(); let csv = try NotebookCSV.encode(b); let encoded = Date()
        let decoded = try NotebookCSV.decode(csv); let imported = Date()
        let stats = DeadlineStatistics(entries: decoded.entries, now: Date()); let end = Date()
        try check(stats.seconds == Double(count) * 1800, "Benchmark totals wrong")
        print(String(format: "BENCH %d entries: CSV %.2f MB; export %.3fs; import %.3fs; statistics %.3fs", count, Double(csv.utf8.count)/1e6, encoded.timeIntervalSince(start), imported.timeIntervalSince(encoded), end.timeIntervalSince(imported)))
    }
}

import Foundation
import FocusCore

@main struct DeadlineStoreChecks {
    @MainActor static func main() throws {
        func check(_ value: Bool, _ text: String) throws { if !value { throw NotebookCSV.Failure.invalid(text) } }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FocusNest-deadline-check-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TrackerStore(dataURL: dir.appendingPathComponent("notebook.json"))
        let p = store.book.projects[0].id
        let t = DeadlineTask(title: "Grant", projectID: p, dueDate: Date())
        store.saveDeadline(t); store.startDeadline(t)
        try check(store.active?.deadlineID == t.id, "Deadline timer not linked")
        store.pause(); store.startDeadline(t)
        try check(Set(store.book.entries.map(\.focusID)).count == 1, "Resume split the session")
        store.completeDeadline(t)
        try check(store.active == nil && store.book.deadlines[0].completedAt != nil && store.focusID == nil, "Completion left timer resumable")
        store.startDeadline(store.book.deadlines[0])
        try check(store.active == nil, "Completed task can still start")
        print("PASS: deadline start/resume/completion lifecycle")
        let before = store.book
        let csv = try NotebookCSV.encode(before)
        try store.restoreCSV(NotebookCSV.decode(csv)); try store.restoreCSV(NotebookCSV.decode(csv))
        try check(store.book == before, "Repeated restore duplicates or loses data")
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("Backups").path)
        try check(backups.filter { $0.hasPrefix("pre-import-") }.count == 2, "Pre-import backup missing")
        let disk = try JSONDecoder().decode(Notebook.self, from: Data(contentsOf: store.dataURL))
        try check(disk == before, "Restore was not persisted")
        print("PASS: repeated restore is exact and writes pre-import backups")
        store.start(p)
        var rejected = false
        do { try store.restoreCSV(before) } catch { rejected = true }
        try check(rejected && store.active != nil, "Active restore guard failed")
        store.pause(); try check(store.flushSaves(), "Flush failed")
        let reloaded = TrackerStore(dataURL: store.dataURL)
        try check(reloaded.book.deadlines == store.book.deadlines, "Relaunch lost tasks")
        try check(FileManager.default.fileExists(atPath: dir.appendingPathComponent("notebook-before-deadlines.json").path), "Migration backup missing")
        try check(reloaded.flushSaves(), "Reload save failed")
        print("PASS: active restore guard, relaunch and migration backup")
    }
}

import Foundation
import FocusCore

extension TrackerStore {
    func saveDeadline(_ task: DeadlineTask) {
        guard storageAvailable, !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              project(task.projectID) != nil else { return }
        if let i = book.deadlines.firstIndex(where: { $0.id == task.id }) {
            guard book.deadlines[i].projectID == task.projectID || !book.entries.contains(where: { $0.deadlineID == task.id }) else {
                errorMessage = "A deadline with recorded time must keep its original category."; return
            }
            book.deadlines[i] = task
        } else { book.deadlines.append(task) }
        save()
    }
    func startDeadline(_ task: DeadlineTask) {
        guard task.completedAt == nil else { return }
        let continuing = focusID != nil && book.entries.last(where: { $0.focusID == focusID })?.deadlineID == task.id
        start(task.projectID, continuing: continuing, deadlineID: task.id)
    }
    func completeDeadline(_ task: DeadlineTask) {
        guard storageAvailable, book.review == nil, savingChunk == nil,
              let i = book.deadlines.firstIndex(where: { $0.id == task.id }) else { return }
        if active?.deadlineID == task.id { pause() }
        book.deadlines[i].completedAt = task.completedAt == nil ? Date() : nil
        if task.completedAt == nil && book.entries.last(where: { $0.focusID == focusID })?.deadlineID == task.id { focusID = nil }
        save()
    }
    func restoreCSV(_ imported: Notebook) throws {
        guard storageAvailable, active == nil, book.review == nil, savingChunk == nil else {
            throw NotebookCSV.Failure.invalid("Pause your timer and resolve any away review before restoring.")
        }
        try NotebookCSV.validate(imported)
        guard flushSaves() else { throw NotebookCSV.Failure.invalid("Could not finish saving the current notebook.") }
        let backup = dataURL.deletingLastPathComponent().appendingPathComponent("Backups/pre-import-\(UUID().uuidString).json")
        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(book).write(to: backup, options: .atomic)
        var restored = imported
        restored.recoverAfterRelaunch(); restored.markReturned(at: Date())
        // Commit to disk before changing visible state. A failed restore leaves the current notebook intact.
        try JSONEncoder().encode(restored).write(to: dataURL, options: .atomic)
        book = restored; focusID = restored.review?.focusID
        selectedProjectID = restored.review?.projectID ?? restored.projects.first?.id
        now = Date()
    }
}

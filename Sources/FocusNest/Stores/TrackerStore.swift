import SwiftUI
import FocusCore

struct TimeChunkDraft: Identifiable {
    let id: UUID
    let projectID: UUID
    let seconds: Double
    let note: String
}

@MainActor
final class TrackerStore: ObservableObject {
    @Published var book = Notebook() { didSet { refreshClock() } }
    let clock = SessionClock()
    var now = Date() {
        didSet {
            clock.advance(to: now)
            // Reports need minute resolution while running and day changes while paused.
            if (active != nil && Int(now.timeIntervalSince1970 / 60) != Int(oldValue.timeIntervalSince1970 / 60)) ||
                !TimeMath.calendar.isDate(now, inSameDayAs: oldValue) {
                objectWillChange.send()
            }
        }
    }
    private let writer = NotebookWriter()
    private var lastCheckpoint = Date()
    @Published var selectedProjectID: UUID?
    @Published var focusID: UUID? { didSet { refreshClock() } }
    @Published var discardingSessionID: UUID?
    @Published var savingChunk: TimeChunkDraft?
    @Published var errorMessage: String?
    @Published var storageAvailable = true
    let dataURL: URL

    init(dataURL: URL? = nil) {
        self.dataURL = dataURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FocusNest/notebook.json")
        do {
            if FileManager.default.fileExists(atPath: self.dataURL.path) {
                let original = try Data(contentsOf: self.dataURL)
                book = try JSONDecoder().decode(Notebook.self, from: original)
                // Preserve the exact pre-migration file once, before the first new-format save.
                let migration = self.dataURL.deletingLastPathComponent().appendingPathComponent("notebook-before-deadlines.json")
                if !FileManager.default.fileExists(atPath: migration.path) {
                    try original.write(to: migration, options: .atomic)
                }
                book.recoverAfterRelaunch()
                book.markReturned(at: Date())
            } else {
                book.projects = [Project(name: "Research", weeklyGoal: 20, color: 0),
                                 Project(name: "Teaching", weeklyGoal: 8, color: 1),
                                 Project(name: "Other", color: 2)]
            }
            selectedProjectID = book.review?.projectID ?? book.projects.first?.id
            focusID = book.review?.focusID
            refreshClock()
            save()
        } catch {
            storageAvailable = false
            errorMessage = "Your saved notebook could not be opened. It has been left untouched. \(error.localizedDescription)"
        }
    }

    var active: Entry? { book.activeEntry }
    var currentProject: Project? { project(active?.projectID ?? selectedProjectID) }
    var sessionSeconds: Double { clock.seconds }
    private func refreshClock() {
        let seconds = book.entries.reduce(0.0) { total, entry in
            guard entry.focusID == focusID else { return total }
            return total + (entry.end.map { max(0, $0.timeIntervalSince(entry.start)) } ?? 0)
        }
        clock.configure(seconds: seconds, runningSince: active?.start, at: now)
    }
    func updateActivity(at date: Date, idleSeconds: Double) {
        now = date
        if book.review != nil, book.review?.returnedAt == nil, idleSeconds < 2 { markReturned() }
        guard let active else { return }
        if let cutoff = TimeMath.idleCutoff(sessionStart: active.start, now: date,
                                          idleSeconds: idleSeconds, threshold: book.idleMinutes * 60) {
            pauseForReview(at: cutoff, reason: "There was no keyboard or mouse activity for \(Int(book.idleMinutes)) minutes.")
        } else if date.timeIntervalSince(lastCheckpoint) >= 15 {
            save()
        }
    }
    func project(_ id: UUID?) -> Project? { book.projects.first { $0.id == id } }
    func path(_ id: UUID) -> String {
        var names: [String] = []; var cursor: UUID? = id; var seen: Set<UUID> = []
        while let current = cursor, !seen.contains(current), let p = project(current) {
            seen.insert(current); names.insert(p.name, at: 0); cursor = p.parentID
        }
        return names.joined(separator: " › ")
    }
    var orderedProjects: [Project] {
        book.projects.sorted { path($0.id).localizedStandardCompare(path($1.id)) == .orderedAscending }
    }
    func save() {
        guard storageAvailable else { return }
        var snapshot = book
        if active != nil { snapshot.heartbeat = now }
        lastCheckpoint = now
        writer.save(snapshot, to: dataURL) { [weak self] message in
            Task { @MainActor [weak self] in self?.errorMessage = message }
        }
    }
    // Used only at termination and by persistence checks, never for routine UI actions.
    @discardableResult
    func flushSaves() -> Bool {
        if let error = writer.flush() {
            errorMessage = error
            return false
        }
        return true
    }
    func start(_ id: UUID, continuing: Bool = false, deadlineID: UUID? = nil) {
        guard storageAvailable, book.review == nil, savingChunk == nil else { return }
        let date = Date()
        if active?.projectID == id && active?.deadlineID == deadlineID { return }
        let previousTask = continuing ? book.entries.last(where: { $0.focusID == focusID })?.deadlineID : nil
        let taskID = deadlineID ?? previousTask
        if let taskID, !book.deadlines.contains(where: { $0.id == taskID && $0.projectID == id && $0.completedAt == nil }) { return }
        let nextFocus = continuing && selectedProjectID == id ? (focusID ?? UUID()) : UUID()
        book.start(projectID: id, focusID: nextFocus, at: date, deadlineID: taskID)
        selectedProjectID = id; focusID = nextFocus; now = date; save()
    }
    func pause() { book.stop(at: Date()); now = Date(); save() }
    var canSaveTimeChunk: Bool {
        guard storageAvailable, book.review == nil, savingChunk == nil, let focusID else { return false }
        return book.entries.contains { $0.focusID == focusID }
    }
    func requestSaveTimeChunk() {
        guard canSaveTimeChunk, let focusID else { return }
        if active != nil { pause() }
        let entries = book.entries.filter { $0.focusID == focusID }
        guard let first = entries.first else { return }
        savingChunk = TimeChunkDraft(id: focusID, projectID: first.projectID,
                                    seconds: entries.reduce(0) { $0 + max(0, ($1.end ?? now).timeIntervalSince($1.start)) },
                                    note: first.note)
    }
    func saveTimeChunk(_ requestedID: UUID, note: String) {
        guard storageAvailable, savingChunk?.id == requestedID, focusID == requestedID,
              book.describeTimeChunk(focusID: requestedID, note: note) else { return }
        focusID = nil
        savingChunk = nil
        now = Date()
        save()
    }
    var canDiscardPausedSession: Bool {
        guard storageAvailable, active == nil, book.review == nil, savingChunk == nil, let focusID else { return false }
        return book.entries.contains { $0.focusID == focusID }
    }
    func requestDiscardSession() {
        guard canDiscardPausedSession else { return }
        discardingSessionID = focusID
    }
    func discardPausedSession(_ requestedID: UUID) {
        defer { discardingSessionID = nil }
        guard canDiscardPausedSession, focusID == requestedID,
              book.discardPausedSession(focusID: requestedID) else { return }
        focusID = nil
        now = Date()
        save()
    }
    func toggle() {
        if active != nil { pause() }
        else if let id = selectedProjectID { start(id, continuing: true) }
    }
    func pauseForReview(at date: Date, reason: String) {
        guard active != nil else { return }
        book.pauseForReview(at: date, reason: reason); now = Date(); save()
    }
    func resolveReview(until end: Date?, resume: Bool) {
        guard let review = book.review else { return }
        selectedProjectID = review.projectID; focusID = review.focusID
        book.resolveReview(countUntil: end, resume: resume, at: Date()); now = Date(); save()
    }
    func markReturned() {
        guard book.review != nil, book.review?.returnedAt == nil else { return }
        book.markReturned(at: Date()); save()
    }
    func saveProject(_ p: Project) {
        guard storageAvailable else { return }
        if let i = book.projects.firstIndex(where: { $0.id == p.id }) { book.projects[i] = p }
        else { book.projects.append(p) }
        save()
    }
    func saveEntry(_ e: Entry, overrideOverlaps: Bool = false) -> EntrySaveResult {
        guard storageAvailable else { return .invalid("Your notebook is unavailable.") }
        if let taskID = e.deadlineID, !book.deadlines.contains(where: { $0.id == taskID && $0.projectID == e.projectID }) {
            return .invalid("The deadline must belong to the selected project.")
        }
        let result = book.saveEntry(e, overrideOverlaps: overrideOverlaps)
        if result == .saved { save() }
        return result
    }
    func deleteEntry(_ id: UUID) { book.entries.removeAll { $0.id == id && $0.end != nil }; save() }
    func total(in range: DateInterval, projectID: UUID? = nil) -> Double {
        let ids = projectID.map { TimeMath.descendants(of: $0, projects: book.projects) }
        return TimeMath.seconds(book.entries, in: range, projectIDs: ids, now: now)
    }
}

@MainActor
final class SessionClock: ObservableObject {
    @Published private(set) var seconds = 0.0
    private var baseSeconds = 0.0
    private var runningSince: Date?

    func configure(seconds: Double, runningSince: Date?, at date: Date) {
        baseSeconds = seconds; self.runningSince = runningSince
        let value = seconds + (runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
        if self.seconds != value { self.seconds = value }
    }
    func advance(to date: Date) {
        guard let runningSince else { return }
        let value = baseSeconds + max(0, date.timeIntervalSince(runningSince))
        if Int(value) != Int(seconds) { seconds = value }
    }
}

// One serial writer and one replaceable pending snapshot bound memory during slow I/O.
private final class NotebookWriter: @unchecked Sendable {
    private struct Pending: Sendable {
        let book: Notebook
        let url: URL
        let failed: @Sendable (String) -> Void
    }
    private let queue = DispatchQueue(label: "local.focusnest.persistence", qos: .utility)
    private let lock = NSLock()
    private var pending: Pending?
    private var scheduled = false
    private var lastError: String?

    func save(_ book: Notebook, to url: URL, failed: @escaping @Sendable (String) -> Void) {
        lock.lock()
        pending = Pending(book: book, url: url, failed: failed)
        let start = !scheduled
        scheduled = true
        lock.unlock()
        if start { queue.async { self.drain() } }
    }
    private func drain() {
        while true {
            lock.lock()
            guard let next = pending else {
                scheduled = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()
            do {
                try FileManager.default.createDirectory(at: next.url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let fm = FileManager.default
                let backups = next.url.deletingLastPathComponent().appendingPathComponent("Backups")
                try fm.createDirectory(at: backups, withIntermediateDirectories: true)
                let day = ISO8601DateFormatter().string(from: Date()).prefix(10)
                let backup = backups.appendingPathComponent("notebook-\(day).json")
                if fm.fileExists(atPath: next.url.path), !fm.fileExists(atPath: backup.path) {
                    try fm.copyItem(at: next.url, to: backup)
                }
                try JSONEncoder().encode(next.book).write(to: next.url, options: .atomic)
                lastError = nil
            } catch {
                let message = "Could not save your time. Please keep the app open and check available disk space. \(error.localizedDescription)"
                lastError = message
                next.failed(message)
            }
        }
    }
    func flush() -> String? { queue.sync { lastError } }
}

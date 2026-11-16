import Foundation
import Combine
import FocusCore

private struct Failure: Error { let message: String }
private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw Failure(message: message) }
}

@main
struct TimeChunkChecks {
    @MainActor static func main() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FocusNest-chunk-check-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("notebook.json")
        let store = TrackerStore(dataURL: file)
        let project = store.book.projects[0]
        let earlier = Entry(projectID: project.id, start: Date().addingTimeInterval(-7200),
                            end: Date().addingTimeInterval(-3600), note: "Earlier work")
        store.book.entries.append(earlier)
        store.start(project.id)
        store.book.entries[store.book.entries.count - 1].start = Date().addingTimeInterval(-60)
        let session = store.focusID!
        store.requestSaveTimeChunk()
        try check(store.active == nil && store.savingChunk?.id == session, "Save must pause the correct chunk before asking for its note")
        try check((store.savingChunk?.seconds ?? 0) >= 60, "Draft must show recorded chunk duration")
        try check(!store.canSaveTimeChunk && !store.canDiscardPausedSession, "Pending description must block duplicate save/discard actions")
        let paused = store.book
        store.start(store.book.projects[1].id)
        store.toggle()
        store.saveTimeChunk(UUID(), note: "Wrong target")
        store.saveTimeChunk(session, note: "  \n")
        try check(store.book == paused && store.savingChunk?.id == session, "Resume, stale targets, and blank notes must not alter the pending chunk")
        print("PASS: Save pauses the correct chunk and protects its pending note")

        store.saveTimeChunk(session, note: "  Data analysis  ")
        try check(store.focusID == nil && store.savingChunk == nil && store.active == nil, "Successful save must finish the chunk and reset its clock")
        try check(store.book.entries.first { $0.id == earlier.id } == earlier, "Earlier work must stay unchanged")
        try check(store.flushSaves(), "Queued saves must finish successfully")
        let loaded = try JSONDecoder().decode(Notebook.self, from: Data(contentsOf: file))
        try check(loaded.entries.last?.note == "Data analysis", "Chunk note must be persisted")
        let words = NoteCloud.words(entries: loaded.entries, projects: loaded.projects,
                                   range: DateInterval(start: Date().addingTimeInterval(-1800), end: Date()), now: Date())
        try check(Set(words.map(\.word)) == ["data", "analysis"], "Saved note must feed the overall themes")
        try check(!store.canSaveTimeChunk, "Already finished chunks must not be offered for save again")
        print("PASS: Saving persists the note, finishes the chunk, and updates themes")

        store.start(project.id)
        let nextSession = store.focusID!
        store.requestSaveTimeChunk()
        let canceled = store.book
        store.savingChunk = nil
        try check(store.book == canceled && store.focusID == nextSession && store.canSaveTimeChunk, "Cancel must keep recorded time paused and resumable")
        store.start(project.id, continuing: true)
        try check(store.active?.focusID == nextSession, "Resume after Cancel must continue the same chunk")
        print("PASS: Cancel preserves the paused chunk for Resume or Save later")

        let minute = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 60) * 60)
        store.now = minute
        store.save()
        var updates = 0
        let subscription = store.objectWillChange.sink { updates += 1 }
        for second in 1...10 { store.now = minute.addingTimeInterval(Double(second)) }
        try check(updates == 0, "Clock seconds must not invalidate dashboard reports")
        defer { withExtendedLifetime(subscription) {} }
        print("PASS: Clock seconds do not invalidate dashboard reports")
        let before = store.book
        updates = 0
        for second in 11...25 { store.updateActivity(at: minute.addingTimeInterval(Double(second)), idleSeconds: 0) }
        try check(updates == 0 && store.book == before, "Heartbeat checks must not publish notebook changes")
        try check(store.flushSaves(), "Automatic heartbeat must finish")
        let automatic = try JSONDecoder().decode(Notebook.self, from: Data(contentsOf: file))
        try check(automatic.heartbeat == minute.addingTimeInterval(15), "Automatic checkpoint must run after 15 seconds")
        store.save()
        try check(store.flushSaves(), "Heartbeat save must finish")
        let checkpoint = try JSONDecoder().decode(Notebook.self, from: Data(contentsOf: file))
        try check(checkpoint.heartbeat == store.now, "Crash recovery must retain the latest saved heartbeat")
        print("PASS: Heartbeats persist without invalidating reports")
        store.pause()
        updates = 0
        store.markReturned()
        for second in 26...40 { store.updateActivity(at: minute.addingTimeInterval(Double(second)), idleSeconds: 0) }
        try check(updates == 0, "Paused clock and activation without review must not invalidate reports")
        for index in 0..<100 {
            var edited = project
            edited.name = "Revision \(index)"
            store.saveProject(edited)
        }
        try check(store.flushSaves(), "Rapid saves must finish")
        let latest = try JSONDecoder().decode(Notebook.self, from: Data(contentsOf: file))
        try check(latest.projects[0].name == "Revision 99" && latest.activeEntry == nil,
                  "Coalesced saves must keep the newest snapshot and pause")
        print("PASS: Paused updates stay quiet and rapid saves preserve the latest state")
        let clock = SessionClock()
        clock.configure(seconds: 12, runningSince: minute.addingTimeInterval(10), at: minute)
        clock.advance(to: minute.addingTimeInterval(15))
        try check(clock.seconds == 17, "Elapsed time must use actual start, not a stale UI tick")
        clock.advance(to: minute.addingTimeInterval(115))
        try check(clock.seconds == 117, "Delayed clock updates must retain exact elapsed time")
        clock.configure(seconds: 117, runningSince: nil, at: minute.addingTimeInterval(115))
        clock.advance(to: minute.addingTimeInterval(200))
        try check(clock.seconds == 117, "Paused clock must remain fixed")
        print("PASS: Clock accuracy survives stale ticks, delays, and pauses")
        try Data().write(to: dir.appendingPathComponent("missing"))
        let invalid = TrackerStore(dataURL: dir.appendingPathComponent("missing/notebook.json"))
        invalid.save()
        try check(!invalid.flushSaves(), "Write failures must be reported when flushing before quit")
        print("PASS: Failed persistence prevents a successful quit flush")
    }
}

import SwiftUI
import FocusCore
import Darwin

@main struct PerformancePreview: App {
    @StateObject private var store: TrackerStore
    init() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("FocusNest-performance-\(UUID())")
        let store = TrackerStore(dataURL: root.appendingPathComponent("notebook.json"))
        let p = store.book.projects[0].id
        let now = Date()
        store.book.deadlines = (0..<100).map { DeadlineTask(title: "Synthetic grant \($0 + 1)", projectID: p, dueDate: now.addingTimeInterval(Double($0 + 1) * 86400)) }
        let tasks = store.book.deadlines
        store.book.entries = (0..<20_000).map { i in
            let start = now.addingTimeInterval(Double(i - 20_000) * 3600)
            return Entry(projectID: p, start: start, end: start.addingTimeInterval(1800), note: "Synthetic drafting", deadlineID: tasks[i % tasks.count].id)
        }
        store.save()
        _store = StateObject(wrappedValue: store)
    }
    var body: some Scene {
        Window("FocusNest Test Preview", id: "main") {
            ContentView(store: store, registerWindowOpener: { _ in }).frame(minWidth: 1000, minHeight: 700)
                .onAppear {
                    NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
                    for delay in [5.0, 30, 60, 120] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
                            let text = "\(delay)s: peak RSS \(Double(usage.ru_maxrss) / 1048576) MiB, user CPU \(usage.ru_utime.tv_sec)s, system CPU \(usage.ru_stime.tv_sec)s\n"
                            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("FocusNest-performance.txt")
                            let previous = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                            try? (previous + text).write(to: url, atomically: true, encoding: .utf8)
                        }
                    }
                }
        }
        Settings { PreferencesView(store: store) }
    }
}

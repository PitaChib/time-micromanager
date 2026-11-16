import SwiftUI
import Charts
import FocusCore

struct DeadlinesView: View {
    @ObservedObject var store: TrackerStore
    @State private var editing: DeadlineTask?
    @State private var showCompleted = false
    var body: some View {
        let grouped = Dictionary(grouping: store.book.entries.compactMap { e in e.deadlineID.map { ($0, e) } }, by: { $0.0 })
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Deadlines").font(.largeTitle.bold())
                    Text("A clear finish line for your work.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("New Deadline", systemImage: "plus") {
                    if let id = store.selectedProjectID ?? store.book.projects.first?.id {
                        editing = DeadlineTask(title: "", projectID: id, dueDate: Calendar.current.date(byAdding: .day, value: 7, to: Date())!)
                    }
                }.disabled(!store.storageAvailable || store.book.projects.isEmpty)
            }
            Toggle("Show completed tasks", isOn: $showCompleted)
            let tasks = store.book.deadlines.filter { showCompleted || $0.completedAt == nil }.sorted { $0.dueDate < $1.dueDate }
            if tasks.isEmpty {
                ContentUnavailableView("Your next finish line", systemImage: "calendar.badge.clock", description: Text("Add a deadline, choose a time category, and track work toward it."))
            }
            LazyVStack(spacing: 16) {
                ForEach(tasks) { task in
                    DeadlineCard(store: store, task: task, entries: grouped[task.id]?.map { $0.1 } ?? [], edit: { editing = task })
                }
            }
        }.padding(20)
            .sheet(item: $editing) { DeadlineEditor(store: store, task: $0) }
    }
}

private struct DeadlineCard: View {
    @ObservedObject var store: TrackerStore
    let task: DeadlineTask
    let entries: [Entry]
    let edit: () -> Void
    @State private var cumulative = false
    var body: some View {
        let stats = DeadlineStatistics(entries: entries, now: store.now)
        let days = task.daysRemaining(at: store.now)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title).font(.title2.bold()).strikethrough(task.completedAt != nil)
                    Text(store.path(task.projectID)).foregroundStyle(.secondary)
                    Text("Due \(task.dueDate.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                }
                Spacer()
                Text(task.completedAt != nil ? "Completed" : days < 0 ? "\(-days) days overdue" : days == 0 ? "Due today" : "\(days) \(days == 1 ? "day" : "days") left")
                    .font(.title3.bold()).foregroundStyle(task.completedAt != nil ? Color.green : days <= 2 ? .orange : .indigo)
            }
            HStack(spacing: 20) {
                Text(String(format: "%.2f hours total", stats.seconds / 3600)).font(.headline)
                Text("\(stats.sessions) sessions")
                if let first = stats.firstWorked { Text("Started \(first.formatted(date: .abbreviated, time: .omitted))") }
            }.font(.callout)
            if !stats.daily.isEmpty {
                Picker("Activity chart", selection: $cumulative) {
                    Text("Daily hours").tag(false)
                    Text("Accumulated hours").tag(true)
                }.pickerStyle(.segmented).frame(maxWidth: 320)
                let points = chartPoints(stats)
                Chart(points, id: \.date) { point in
                    if cumulative {
                        LineMark(x: .value("Day", point.date), y: .value("Hours", point.hours))
                    } else {
                        BarMark(x: .value("Day", point.date, unit: .day), y: .value("Hours", point.hours))
                    }
                }.frame(height: 110).chartYAxisLabel("Hours")
                if let peak = stats.daily.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }), let hour = stats.hourly.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }) {
                    Text("Busiest day: \(peak.key.formatted(date: .abbreviated, time: .omitted)) · Most work: \(hour.key):00–\(hour.key + 1):00")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                if task.completedAt == nil {
                    if store.active?.deadlineID == task.id {
                        SessionElapsedText(clock: store.clock).monospacedDigit()
                        Button("Pause", action: store.pause)
                        Button("Save Time", action: store.requestSaveTimeChunk)
                    } else { Button("Start / Resume", systemImage: "play.fill") { store.startDeadline(task) }.buttonStyle(.borderedProminent) }
                }
                if store.active == nil && store.book.entries.last(where: { $0.focusID == store.focusID })?.deadlineID == task.id {
                    Button("Save Time", action: store.requestSaveTimeChunk).disabled(!store.canSaveTimeChunk)
                }
                Button(task.completedAt == nil ? "Mark Complete" : "Reopen") { store.completeDeadline(task) }
                Spacer()
                Button("Edit", action: edit)
            }.disabled(!store.storageAvailable || store.book.review != nil || store.savingChunk != nil)
        }.padding(18).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }
    private func chartPoints(_ stats: DeadlineStatistics) -> [(date: Date, hours: Double)] {
        var total = 0.0
        return stats.daily.keys.sorted().map { date in
            let hours = stats.daily[date, default: 0] / 3600
            total += hours
            return (date, cumulative ? total : hours)
        }
    }
}

private struct DeadlineEditor: View {
    @ObservedObject var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    @State var task: DeadlineTask
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Deadline task").font(.title2.bold())
            Form {
                TextField("Title", text: $task.title)
                Picker("Time category", selection: $task.projectID) {
                    ForEach(store.orderedProjects) { Text(store.path($0.id)).tag($0.id) }
                }.disabled(store.book.entries.contains { $0.deadlineID == task.id })
                DatePicker("Due", selection: $task.dueDate)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Deadline") {
                    task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.saveDeadline(task); dismiss()
                }.keyboardShortcut(.defaultAction).disabled(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 480)
    }
}

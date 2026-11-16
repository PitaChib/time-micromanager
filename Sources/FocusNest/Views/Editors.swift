import SwiftUI
import FocusCore

struct ProjectEditor: View {
    @ObservedObject var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    @State var project: Project
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(store.project(project.id) == nil ? "A new place to focus" : "Edit project").font(.title2.bold())
            Form {
                TextField("Name", text: $project.name)
                Picker("Belongs to", selection: $project.parentID) {
                    Text("Top-level category").tag(nil as UUID?)
                    ForEach(store.orderedProjects.filter { !TimeMath.descendants(of: project.id, projects: store.book.projects).contains($0.id) }) { p in
                        Text(store.path(p.id)).tag(Optional(p.id))
                    }
                }
                HStack {
                    TextField("Weekly goal (hours)", value: $project.weeklyGoal, format: .number)
                    Text("0 = no goal").font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Color")
                        Spacer()
                        Text(NestStyle.palette[abs(project.color % NestStyle.palette.count)].name).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 10), spacing: 10) {
                        ForEach(NestStyle.colors.indices, id: \.self) { i in
                            Button { project.color = i } label: {
                                Circle().fill(NestStyle.color(i)).frame(width: 22, height: 22)
                                    .overlay {
                                        if project.color == i {
                                            Circle().strokeBorder(.primary, lineWidth: 2).padding(-4)
                                        }
                                    }.frame(width: 30, height: 30)
                            }.buttonStyle(.plain)
                                .help(NestStyle.palette[i].name)
                                .accessibilityLabel(NestStyle.palette[i].name)
                                .accessibilityValue(project.color == i ? "Selected" : "")
                        }
                    }
                }
            }.formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Project") {
                    project.name = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.saveProject(project); dismiss()
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !project.weeklyGoal.isFinite || project.weeklyGoal < 0)
            }
        }.padding(24).frame(width: 470)
    }
}

struct EntryEditor: View {
    @ObservedObject var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    @State var entry: Entry
    @State private var error: String?
    @State private var conflicts: [Entry] = []
    @State private var showOverrideConfirmation = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Record your time").font(.title2.bold())
            Form {
                Picker("Project", selection: $entry.projectID) {
                    ForEach(store.orderedProjects) { p in Text(store.path(p.id)).tag(p.id) }
                }
                Picker("Deadline task", selection: $entry.deadlineID) {
                    Text("None").tag(nil as UUID?)
                    ForEach(store.book.deadlines.filter { $0.projectID == entry.projectID }) { Text($0.title).tag(Optional($0.id)) }
                }
                .onChange(of: entry.projectID) { _, _ in entry.deadlineID = nil }
                DatePicker("Started", selection: $entry.start)
                DatePicker("Finished", selection: Binding(get: { entry.end ?? Date() }, set: { entry.end = $0 }))
                TextField("Note (optional)", text: $entry.note)
            }.formStyle(.grouped)
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Time") { saveEntry() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 520)
            .alert("Override overlapping time?", isPresented: $showOverrideConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Override", role: .destructive) { saveEntry(overrideOverlaps: true) }
            } message: {
                Text(overrideMessage)
            }
    }
    private var overrideMessage: String {
        let descriptions = conflicts.map { existing in
            let project = store.path(existing.projectID)
            let start = existing.start.formatted(date: .abbreviated, time: .shortened)
            let end = existing.end?.formatted(date: .abbreviated, time: .shortened) ?? "Running now"
            return "\(project)\n\(start) → \(end)"
        }
        return "This time overlaps:\n\n" + descriptions.joined(separator: "\n\n")
            + "\n\nOverride replaces only the overlapping portions. Time outside this interval will be kept."
    }
    private func saveEntry(overrideOverlaps: Bool = false) {
        error = nil
        switch store.saveEntry(entry, overrideOverlaps: overrideOverlaps) {
        case .saved: dismiss()
        case .invalid(let message): error = message
        case .conflicts(let entries):
            conflicts = entries
            showOverrideConfirmation = true
        }
    }
}

struct ReviewView: View {
    @ObservedObject var store: TrackerStore
    let review: IdleReview
    @State private var returnedAt = Date()
    @State private var countUntil = Date()
    @State private var resume = true
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Welcome back", systemImage: "moon.zzz.fill").font(.title2.bold()).foregroundStyle(.indigo)
            Text(review.reason)
            Text("\(store.project(review.projectID)?.name ?? "Your timer") paused at \(review.start.formatted(date: .abbreviated, time: .shortened)). Were you still working?")
                .fixedSize(horizontal: false, vertical: true)
            Text("Away for \(TimeMath.duration(returnedAt.timeIntervalSince(review.start))) when you returned.")
                .font(.callout).foregroundStyle(.secondary)
            DatePicker("Count work until", selection: $countUntil, in: review.start...max(review.start, returnedAt))
            Toggle("Resume this project after reviewing", isOn: $resume)
            HStack {
                Button("Discard Away Time") { store.resolveReview(until: nil, resume: resume) }
                Spacer()
                Button("Keep Until Selected Time") { store.resolveReview(until: countUntil, resume: resume) }
                    .buttonStyle(.borderedProminent)
            }
            Text("Choose your return time to keep the whole interval, or an earlier time to correct it.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(width: 550)
            .onAppear { let date = review.returnedAt ?? Date(); returnedAt = max(date, review.start); countUntil = max(date, review.start) }
            .interactiveDismissDisabled()
    }
}

struct PreferencesView: View {
    @ObservedObject var store: TrackerStore
    var body: some View {
        Form {
            Section("Forgotten timers") {
                Picker("Pause after inactivity", selection: Binding(get: { store.book.idleMinutes }, set: { store.book.idleMinutes = $0; store.save() })) {
                    ForEach([2.0, 5, 10, 15, 20, 30, 60], id: \.self) { Text("\(Int($0)) minutes").tag($0) }
                }
                Text("Time is removed back to your last keyboard or mouse activity. You can restore it when you return. Sleep and locking pause immediately.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Your notebook") {
                Text("Saved only on this Mac. No account or internet required.")
                Button("Show Data in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.dataURL]) }
                BackupControls(store: store)
            }
        }.formStyle(.grouped).padding().frame(width: 500)
    }
}

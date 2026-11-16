import SwiftUI
import FocusCore

struct ContentView: View {
    @ObservedObject var store: TrackerStore
    let registerWindowOpener: (@escaping () -> Void) -> Void
    @Environment(\.openWindow) private var openWindow
    private enum ProjectSelection: Hashable {
        case deadlines
        case allProjects
        case project(UUID)
    }
    @State private var projectSelection: ProjectSelection = .allProjects
    @State private var timerProjectID: UUID?
    @State private var timerDeadlineID: UUID?
    @State private var editingProject: Project?
    @State private var editingEntry: Entry?
    @State private var reviewingAwayTime: IdleReview?
    @State private var deletingEntry: Entry?
    @State private var section = 0
    @State private var period: ReportPeriod = .week
    @State private var anchor = Date()
    @State private var customStart = TimeMath.week(containing: Date()).start
    @State private var customEnd = Date()

    private var filterID: UUID? {
        if case .project(let id) = projectSelection { return id }
        return nil
    }

    private var range: DateInterval {
        let c = TimeMath.calendar
        switch period {
        case .week: return TimeMath.week(containing: anchor)
        case .month: return c.dateInterval(of: .month, for: anchor)!
        case .all:
            return DateInterval(start: c.startOfDay(for: store.book.entries.map(\.start).min() ?? store.now), end: store.now)
        case .custom:
            let start = c.startOfDay(for: min(customStart, customEnd))
            let end = c.date(byAdding: .day, value: 1, to: c.startOfDay(for: max(customStart, customEnd)))!
            return DateInterval(start: start, end: end)
        }
    }
    private var filteredEntries: [Entry] {
        let ids = filterID.map { TimeMath.descendants(of: $0, projects: store.book.projects) }
        return store.book.entries.filter {
            (ids == nil || ids!.contains($0.projectID)) && $0.start < range.end && ($0.end ?? store.now) > range.start
        }.sorted { $0.start > $1.start }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit().frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Time Micromanager").font(.system(.title3, design: .rounded, weight: .bold))
                        Text("A little pressure. A little progress.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(20)
                List(selection: $projectSelection) {
                    Label("All projects", systemImage: "square.grid.2x2").tag(ProjectSelection.allProjects)
                    Label("Deadlines", systemImage: "calendar.badge.clock").tag(ProjectSelection.deadlines)
                    Section("YOUR PROJECTS") {
                        ForEach(store.orderedProjects) { p in
                            HStack(spacing: 8) {
                                Circle().fill(NestStyle.color(p.color)).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name)
                                    if let parent = p.parentID { Text(store.path(parent)).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                }
                            }.tag(ProjectSelection.project(p.id))
                                .contextMenu {
                                    Button("Start Timer") { store.start(p.id) }.disabled(store.book.review != nil)
                                    Button("Edit Project…") { editingProject = p }
                                    Button("Add Subproject…") { editingProject = Project(name: "", parentID: p.id, color: p.color) }
                                }
                        }
                    }
                }.listStyle(.sidebar)
                Button { editingProject = Project(name: "", parentID: filterID, color: NestStyle.nextColor(used: store.book.projects.map(\.color))) } label: {
                    Label("New Project", systemImage: "plus").frame(maxWidth: .infinity)
                }.padding(16).disabled(!store.storageAvailable)
            }.navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            VStack(spacing: 0) {
                if projectSelection != .deadlines { header }
                if store.book.review != nil { awayReviewBanner }
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if projectSelection == .deadlines { DeadlinesView(store: store) } else {
                        timerStrip
                        reportControls
                        if section == 0 {
                            ReportView(store: store, range: range, filterID: filterID, period: period)
                        } else { entryList }
                        }
                    }.padding(16)
                }
            }
            .background(.background)
        }
        .tint(.indigo)
        .onAppear {
            let openMainAction = openWindow
            registerWindowOpener { openMainAction(id: "main") }
            presentAwayReviewIfReady()
        }
        .onChange(of: store.book.review) { _, review in
            if review == nil { reviewingAwayTime = nil }
            else { presentAwayReviewIfReady() }
        }
        .onChange(of: filterID) { _, projectID in
            if let projectID { timerProjectID = projectID; timerDeadlineID = nil }
        }
        .sheet(item: $editingProject) { ProjectEditor(store: store, project: $0) }
        .sheet(item: $editingEntry) { EntryEditor(store: store, entry: $0) }
        .sheet(item: $reviewingAwayTime) { ReviewView(store: store, review: $0) }
        .sheet(item: $store.savingChunk) { TimeChunkNoteEditor(store: store, draft: $0) }
        .alert("Time Micromanager needs your attention", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .confirmationDialog("Delete this time entry?", isPresented: Binding(get: { deletingEntry != nil }, set: { if !$0 { deletingEntry = nil } }), titleVisibility: .visible) {
            Button("Delete Entry", role: .destructive) { if let entry = deletingEntry { store.deleteEntry(entry.id) }; deletingEntry = nil }
        }
    }

    private func presentAwayReviewIfReady() {
        guard let review = store.book.review, review.returnedAt != nil,
              editingProject == nil, editingEntry == nil else { return }
        reviewingAwayTime = review
    }

    private var awayReviewBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.zzz.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("Away time needs review").font(.headline)
                Text("Your timer is paused. Choose which time to keep.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Review Away Time") {
                store.markReturned()
                reviewingAwayTime = store.book.review
            }.buttonStyle(.borderedProminent)
        }.padding(.horizontal, 28).padding(.vertical, 14)
            .background(.orange.opacity(0.10))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(filterID.flatMap { store.project($0)?.name } ?? "All projects")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(filterID.map { store.path($0) } ?? "Combined time across all projects").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let p = store.project(filterID) {
                Button { editingProject = p } label: { Image(systemName: "pencil") }.help("Edit project and weekly goal")
            }
            SettingsLink { Image(systemName: "gearshape") }.help("Settings")
            Button {
                guard let id = filterID ?? store.selectedProjectID ?? store.book.projects.first?.id else { return }
                editingEntry = Entry(projectID: id, start: Date().addingTimeInterval(-3600), end: Date())
            } label: { Label("Add Time", systemImage: "plus") }
                .disabled(!store.storageAvailable || store.book.review != nil)
        }.padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var timerStrip: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Project to time").font(.caption).foregroundStyle(.secondary)
                Picker("Project to time", selection: Binding(get: { timerTargetID }, set: { timerProjectID = $0; timerDeadlineID = nil })) {
                    if store.book.projects.isEmpty { Text("Choose a project").tag(nil as UUID?) }
                    ForEach(store.orderedProjects) { project in
                        Text(store.path(project.id)).tag(Optional(project.id))
                    }
                }.pickerStyle(.menu).labelsHidden()
                    .accessibilityIdentifier("timerProjectPicker")
            }.frame(maxWidth: .infinity, alignment: .leading)
            Picker("Deadline", selection: $timerDeadlineID) {
                Text("No deadline").tag(nil as UUID?)
                ForEach(store.book.deadlines.filter { $0.projectID == timerTargetID && $0.completedAt == nil }) {
                    Text($0.title).tag(Optional($0.id))
                }
            }.frame(maxWidth: 180)
            VStack(alignment: .trailing, spacing: 2) {
                Text(store.active != nil ? "Timing \(store.currentProject?.name ?? "project")" : "Paused")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .help(store.currentProject.map { store.path($0.id) } ?? "Choose a project")
                SessionElapsedText(clock: store.clock).font(.system(size: 26, weight: .medium, design: .rounded)).monospacedDigit()
            }
            if store.active != nil {
                Button("Pause", systemImage: "pause.fill", action: store.pause).buttonStyle(.bordered)
            } else if store.canDiscardPausedSession {
                Button("Discard", systemImage: "trash", role: .destructive) {
                    store.requestDiscardSession()
                }.buttonStyle(.bordered)
                    .accessibilityLabel("Discard Session")
                    .help("Discard this paused session")
                    .accessibilityIdentifier("discardPausedSession")
            }
            Button("Save Time", systemImage: "checkmark.circle", action: store.requestSaveTimeChunk)
                .buttonStyle(.bordered).disabled(!store.canSaveTimeChunk)
                .help("Finish this time chunk and describe what you worked on")
                .accessibilityIdentifier("saveTimeChunk")
            Button {
                if let id = timerTargetID { store.start(id, continuing: canResumeSelectedTimer, deadlineID: timerDeadlineID) }
            } label: {
                Label(timerStartTitle, systemImage: "play.fill").frame(minWidth: 75)
            }.buttonStyle(.borderedProminent)
                .disabled(timerTargetID == nil || store.active?.projectID == timerTargetID && store.active?.deadlineID == timerDeadlineID)
                .accessibilityIdentifier("startSelectedTimer")
            if canResumeSelectedTimer {
                Button("New Session") {
                    if let id = timerTargetID { store.start(id, deadlineID: timerDeadlineID) }
                }.help("Start this project with the session clock at zero")
            }
        }
        .padding(12).background(.indigo.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        .disabled(store.book.review != nil || !store.storageAvailable)
        .alert("Discard this paused session?", isPresented: Binding(
            get: { store.discardingSessionID != nil },
            set: { if !$0 { store.discardingSessionID = nil } }
        ), presenting: store.discardingSessionID) { sessionID in
            Button("Cancel", role: .cancel) { store.discardingSessionID = nil }
            Button("Discard Session", role: .destructive) { store.discardPausedSession(sessionID) }
        } message: { _ in
            Text("Remove all recorded time from this paused session, including any paused/resumed portions? Your project and earlier sessions will be kept.")
        }
    }

    private var timerTargetID: UUID? {
        timerProjectID ?? store.selectedProjectID ?? store.book.projects.first?.id
    }
    private var canResumeSelectedTimer: Bool {
        store.active == nil && store.focusID != nil && store.selectedProjectID == timerTargetID && store.book.entries.last(where: { $0.focusID == store.focusID })?.deadlineID == timerDeadlineID
    }
    private var timerStartTitle: String {
        if store.active?.projectID == timerTargetID && store.active?.deadlineID == timerDeadlineID { return "Running" }
        if store.active != nil { return "Switch & Start" }
        return canResumeSelectedTimer ? "Resume" : "Start"
    }

    private var reportControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("Range", selection: $period) {
                    ForEach(ReportPeriod.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().frame(width: 110)
                if period == .week || period == .month {
                    Button { move(-1) } label: { Image(systemName: "chevron.left") }.help("Previous period")
                    Text(range.start.formatted(.dateTime.month(.abbreviated).day()) + " – " + range.end.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day().year()))
                        .font(.callout.weight(.medium)).lineLimit(1).minimumScaleFactor(0.85)
                    Button { move(1) } label: { Image(systemName: "chevron.right") }.help("Next period")
                    Button("Today") { anchor = Date() }
                } else if period == .all { Text("Every session, since the beginning").foregroundStyle(.secondary) }
                Spacer(minLength: 8)
                Picker("View", selection: $section) {
                    Text("Overview").tag(0)
                    Text("Time Entries").tag(1)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 200)
            }.controlSize(.small)
            if period == .custom {
                HStack {
                    DatePicker("From", selection: $customStart, displayedComponents: .date)
                    DatePicker("Through", selection: $customEnd, displayedComponents: .date)
                }
            }
        }
    }
    private func move(_ direction: Int) {
        anchor = TimeMath.calendar.date(byAdding: period == .week ? .weekOfYear : .month, value: direction, to: anchor)!
    }

    private var entryList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if filteredEntries.isEmpty {
                ContentUnavailableView("A fresh page", systemImage: "clock", description: Text("Start a project timer or add time you’ve already worked."))
                    .frame(maxWidth: .infinity).padding(40)
            }
            ForEach(filteredEntries) { e in
                HStack(spacing: 14) {
                    Circle().fill(NestStyle.color(store.project(e.projectID)?.color ?? 0)).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.path(e.projectID)).font(.headline)
                        Text(e.start.formatted(date: .abbreviated, time: .shortened) + " → " + (e.end?.formatted(date: .abbreviated, time: .shortened) ?? "Now"))
                            .font(.caption).foregroundStyle(.secondary)
                        if !e.note.isEmpty { Text(e.note).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Text(TimeMath.duration((e.end ?? store.now).timeIntervalSince(e.start))).monospacedDigit()
                    if e.end != nil {
                        Button { editingEntry = e } label: { Image(systemName: "pencil") }.help("Edit entry")
                        Button(role: .destructive) { deletingEntry = e } label: { Image(systemName: "trash") }.help("Delete entry")
                    } else { Text("LIVE").font(.caption.bold()).foregroundStyle(.indigo) }
                }.padding(.vertical, 16)
                Divider()
            }
        }
    }
}

enum ReportPeriod: String, CaseIterable, Identifiable {
    case week = "Weekly", month = "Monthly", all = "All Time", custom = "Custom"
    var id: Self { self }
}

import SwiftUI
import FocusCore

struct TimeChunkNoteEditor: View {
    @ObservedObject var store: TrackerStore
    let draft: TimeChunkDraft
    @State private var note: String
    @FocusState private var focused: Bool

    init(store: TrackerStore, draft: TimeChunkDraft) {
        self.store = store
        self.draft = draft
        _note = State(initialValue: draft.note)
    }

    private var description: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What did you work on?").font(.title2.bold())
            Text("\(store.path(draft.projectID)) · \(TimeMath.duration(draft.seconds)) · paused")
                .font(.callout).foregroundStyle(.secondary)
            TextField("A few words, e.g. lecture prep or data analysis", text: $note)
                .textFieldStyle(.roundedBorder).focused($focused)
                .accessibilityIdentifier("timeChunkDescription")
                .onSubmit { save() }
            Text("These words will be used in your overall themes. A short phrase is enough.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { store.savingChunk = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Time Chunk", action: save)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(description.isEmpty)
                    .accessibilityIdentifier("confirmSaveTimeChunk")
            }
            Text("Cancel keeps this chunk paused for later.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 470)
            .onAppear { focused = true }
            .interactiveDismissDisabled()
    }
    private func save() {
        guard !description.isEmpty else { return }
        store.saveTimeChunk(draft.id, note: description)
    }
}

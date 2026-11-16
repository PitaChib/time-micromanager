import SwiftUI
import UniformTypeIdentifiers
import FocusCore

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        self.text = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

struct BackupControls: View {
    @ObservedObject var store: TrackerStore
    @State private var exporting = false
    @State private var importing = false
    @State private var document = CSVDocument(text: "")
    @State private var pending: Notebook?
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily JSON backups and a pre-update copy are kept beside your notebook. Export CSV to keep a copy on another drive.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Export CSV…") {
                    do {
                        var snapshot = store.book
                        if store.active != nil { snapshot.heartbeat = Date() }
                        document = CSVDocument(text: try NotebookCSV.encode(snapshot)); exporting = true
                    } catch { message = error.localizedDescription }
                }
                Button("Restore CSV…") { importing = true }
                    .disabled(store.active != nil || store.book.review != nil || store.savingChunk != nil)
            }.disabled(!store.storageAvailable)
            Text("Restore replaces the notebook after validation and creates a pre-import backup. Pause your timer first.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .commaSeparatedText, defaultFilename: "FocusNest-backup") { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                pending = try NotebookCSV.decode(String(contentsOf: url, encoding: .utf8))
            } catch { message = error.localizedDescription }
        }
        .confirmationDialog("Restore this notebook?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button("Restore Backup", role: .destructive) {
                do { if let pending { try store.restoreCSV(pending); message = "Notebook restored. Your previous notebook is in the Backups folder." } }
                catch { message = error.localizedDescription }
                pending = nil
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text("Replace current data with \(pending?.projects.count ?? 0) projects, \(pending?.deadlines.count ?? 0) deadlines and \(pending?.entries.count ?? 0) entries? A backup of current data will be saved first.")
        }
        .alert("Notebook backup", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") { message = nil } } message: { Text(message ?? "") }
    }
}

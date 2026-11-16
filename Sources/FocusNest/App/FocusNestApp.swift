import SwiftUI
import AppKit
import FocusCore

@main
struct FocusNestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = TrackerStore()
    var body: some Scene {
        Window("Time Micromanager", id: "main") {
            ContentView(store: store, registerWindowOpener: { action in delegate.configure(store: store, openMainWindow: action) })
                .frame(minWidth: 1000, minHeight: 700)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Show Floating Clock") { delegate.showClock() }.keyboardShortcut("k", modifiers: [.command, .shift])
                Button(store.active == nil ? "Start Timer" : "Pause Timer") { store.toggle() }
                    .keyboardShortcut(" ", modifiers: [.command, .shift])
                    .disabled(store.book.review != nil)
            }
        }
        Settings { PreferencesView(store: store) }
        MenuBarExtra {
            Text(store.currentProject?.name ?? "Choose a project")
            Button(store.active == nil ? "Resume Timer" : "Pause Timer") { store.toggle() }
                .disabled(store.book.review != nil)
            Button("Show Floating Clock") { delegate.showClock() }
            Button("Open Time Micromanager") { delegate.openMain() }
            Divider()
            Button("Quit Time Micromanager") { NSApp.terminate(nil) }
        } label: {
            SessionMenuLabel(store: store)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: TrackerStore?
    private var monitor: ActivityMonitor?
    private var clock: FloatingClockController?
    private var openMainWindow: (() -> Void)?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func configure(store: TrackerStore, openMainWindow: @escaping () -> Void) {
        self.openMainWindow = openMainWindow
        guard self.store == nil else { return }
        self.store = store
        monitor = ActivityMonitor(store: store)
        clock = FloatingClockController(store: store, openMain: { [weak self] in self?.openMain() })
        showClock()
    }
    func showClock() { clock?.show() }
    func openMain() {
        store?.markReturned()
        openMainWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        store?.markReturned()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMain(); return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        store?.pauseForReview(at: Date(), reason: "You quit Time Micromanager while this timer was running.")
        store?.save()
        guard store?.flushSaves() != false else {
            let alert = NSAlert()
            alert.messageText = "Your time could not be saved"
            alert.informativeText = store?.errorMessage ?? "Please keep Time Micromanager open and try again."
            alert.runModal()
            return .terminateCancel
        }
        return .terminateNow
    }
}


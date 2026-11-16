import AppKit
import CoreGraphics
import FocusCore

@MainActor
final class ActivityMonitor {
    private let store: TrackerStore
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    init(store: TrackerStore) {
        self.store = store
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.away("Your Mac went to sleep.") }
        })
        observers.append(nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.away("Your display went to sleep.") }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.away("Your Mac was locked.") }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = 0.2
        RunLoop.main.add(timer!, forMode: .common)
    }
    private func away(_ reason: String) { store.pauseForReview(at: Date(), reason: reason) }
    private func tick() {
        guard store.active != nil || store.book.review?.returnedAt == nil && store.book.review != nil else {
            store.now = Date()
            return
        }
        store.updateActivity(at: Date(), idleSeconds: SystemActivity.idleSeconds())
    }
}

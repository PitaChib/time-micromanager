import Foundation
import CoreGraphics

public enum SystemActivity {
    public static let inputEventType = CGEventType(rawValue: UInt32.max)!
    public static func idleSeconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: inputEventType)
    }
}

public extension Notebook {
    mutating func checkInactivity(at now: Date, idleSeconds: Double) {
        guard let active = activeEntry else { return }
        if let cutoff = TimeMath.idleCutoff(sessionStart: active.start, now: now, idleSeconds: idleSeconds, threshold: idleMinutes * 60) {
            pauseForReview(at: cutoff, reason: "There was no keyboard or mouse activity for \(Int(idleMinutes)) minutes.")
        } else {
            heartbeat = now
        }
    }
}

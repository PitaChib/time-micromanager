import SwiftUI
import FocusCore
import AppKit

enum NestStyle {
    // Tableau 20, ordered to keep existing project indices in similar hue families.
    static let palette: [(name: String, hex: UInt)] = [
        ("Slate", 0x79706E), ("Teal", 0x439894), ("Tangerine", 0xF58518),
        ("Rose", 0xD67195), ("Orchid", 0xB279A2), ("Blue", 0x4C78A8),
        ("Leaf", 0x54A24B), ("Coral", 0xE45756), ("Goldenrod", 0xEECA3B),
        ("Olive", 0x9D755D), ("Sky", 0x9ECAE9), ("Peach", 0xFFBF79),
        ("Sage", 0x88D27A), ("Lime", 0xF2CF5B), ("Seafoam", 0x83BCB6),
        ("Salmon", 0xFF9D98), ("Silver", 0xBAB0AC), ("Blush", 0xFCBFD2),
        ("Lilac", 0xD6A5C9), ("Sand", 0xD8B5A5)
    ]
    static let colors: [Color] = palette.map { swatch in
        Color(red: Double((swatch.hex >> 16) & 255) / 255,
              green: Double((swatch.hex >> 8) & 255) / 255,
              blue: Double(swatch.hex & 255) / 255)
    }
    static func color(_ index: Int) -> Color { colors[abs(index % colors.count)] }
    static func nextColor(used: [Int]) -> Int {
        colors.indices.min { a, b in
            used.filter { $0 == a }.count < used.filter { $0 == b }.count
        } ?? 0
    }
}

struct FloatingClockView: View {
    @ObservedObject var store: TrackerStore
    @ObservedObject var clock: SessionClock
    let setPinned: (Bool) -> Void
    let openMain: () -> Void
    let hideClock: () -> Void
    @State private var pinned = true

    private var elapsed: Int { max(0, Int(clock.seconds)) }
    private var groups: [(String, String)] {
        if elapsed >= 3600 {
            return [(String(format: "%02d", elapsed / 3600), "HR"),
                    (String(format: "%02d", elapsed / 60 % 60), "MIN"),
                    (String(format: "%02d", elapsed % 60), "SEC")]
        }
        return [(String(format: "%02d", elapsed / 60), "MIN"),
                (String(format: "%02d", elapsed % 60), "SEC")]
    }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(red: 0.59, green: 0.15, blue: 0.12))
                .frame(width: 164, height: 16).offset(y: 103)
            Capsule().fill(.black.opacity(0.7)).frame(width: 42, height: 4).offset(x: 52, y: 2)
            clockBody.padding(.top, 6)
        }
        .frame(width: 244, height: 120)
        .environment(\.colorScheme, .light)
        .contextMenu {
            Button("Open Dashboard", action: openMain)
            Button(pinned ? "Unpin Clock" : "Keep Clock on Top") { togglePin() }
            Button("Hide Clock", action: hideClock)
        }
    }

    private var clockBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 23)
                .fill(LinearGradient(colors: [Color(red: 0.94, green: 0.32, blue: 0.27),
                                               Color(red: 0.72, green: 0.17, blue: 0.14)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.25), lineWidth: 1)
                .padding(1)
            RoundedRectangle(cornerRadius: 17)
                .fill(LinearGradient(colors: [Color(red: 0.87, green: 0.82, blue: 0.73),
                                               Color(red: 0.96, green: 0.91, blue: 0.82)], startPoint: .top, endPoint: .bottom))
                .overlay { RoundedRectangle(cornerRadius: 17).strokeBorder(.white.opacity(0.75), lineWidth: 1.5) }
                .padding(7)
            VStack(spacing: 5) {
                HStack(spacing: 6) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        RetroFlapView(value: group.0, caption: group.1, compact: groups.count == 3)
                    }
                    VStack(spacing: 9) {
                        HStack(spacing: 7) {
                            Button(action: togglePin) {
                                Image(systemName: pinned ? "pin.fill" : "pin.slash").font(.system(size: 8, weight: .semibold))
                            }.help("Keep clock above other windows")
                            Button(action: hideClock) {
                                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                            }.help("Hide floating clock")
                        }
                        Button(action: openMain) {
                            Text("Time\nManager")
                                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                                .multilineTextAlignment(.center).lineSpacing(2).lineLimit(2).fixedSize()
                        }.help("Open Time Micromanager dashboard")
                        Button(action: timerAction) {
                            Image(systemName: store.book.review != nil ? "exclamationmark.circle.fill" : (store.active == nil ? "play.fill" : "pause.fill"))
                                .font(.system(size: 11, weight: .bold)).frame(width: 24, height: 17)
                                .background(.black.opacity(0.07), in: Capsule())
                        }
                        .help(store.book.review != nil ? "Review away time" : (store.active == nil ? "Start or resume timer" : "Pause timer"))
                        .disabled(store.book.review == nil && (store.selectedProjectID == nil || !store.storageAvailable))
                    }.frame(width: 27)
                }
                HStack(spacing: 4) {
                    Circle().fill(store.active == nil ? Color(red: 0.59, green: 0.49, blue: 0.39) : Color(red: 0.55, green: 0.20, blue: 0.09))
                        .frame(width: 4, height: 4)
                    Text(store.book.review != nil ? "Away time to review" : (store.currentProject?.name ?? "Choose a project"))
                        .font(.system(size: 9, weight: .medium, design: .rounded)).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(store.active == nil ? "PAUSED" : "IN SESSION")
                        .font(.system(size: 6, weight: .bold, design: .rounded)).tracking(0.6)
                    if store.canDiscardPausedSession {
                        Button {
                            openMain()
                            DispatchQueue.main.async { store.requestDiscardSession() }
                        } label: {
                            Image(systemName: "trash").font(.system(size: 9)).frame(width: 14, height: 11)
                        }.help("Discard paused session")
                            .accessibilityLabel("Discard paused session")
                            .accessibilityIdentifier("discardPausedSessionClock")
                    }
                }.padding(.horizontal, 2)
            }
            .foregroundStyle(Color(red: 0.24, green: 0.19, blue: 0.16))
            .buttonStyle(.plain)
            .padding(.horizontal, 16).padding(.top, 13).padding(.bottom, 12)
            VStack {
                ClockDragArea().frame(height: 8)
                Spacer(minLength: 0)
                ClockDragArea().frame(height: 7)
            }
        }.frame(height: 106)
    }
    private func togglePin() { pinned.toggle(); setPinned(pinned) }
    private func timerAction() {
        if store.book.review != nil { store.markReturned(); openMain() }
        else { store.toggle() }
    }
}

private struct ClockDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
    final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}

@MainActor
final class FloatingClockController {
    private let panel: NSPanel
    init(store: TrackerStore, openMain: @escaping () -> Void) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 244, height: 120),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Session Clock"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: FloatingClockView(store: store, clock: store.clock, setPinned: { [weak panel] pinned in
            panel?.level = pinned ? .floating : .normal
        }, openMain: openMain, hideClock: { [weak panel] in panel?.orderOut(nil) }))
        panel.setFrameAutosaveName("FocusNestFloatingClock")
        let restored = panel.setFrameUsingName("FocusNestFloatingClock")
        // Restore the position, but never the previous, much taller clock size.
        panel.setContentSize(NSSize(width: 244, height: 120))
        if let screen = panel.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            let origin = restored ? panel.frame.origin : NSPoint(x: visible.maxX - 264, y: visible.maxY - 160)
            panel.setFrameOrigin(NSPoint(x: min(max(origin.x, visible.minX), visible.maxX - 244),
                                         y: min(max(origin.y, visible.minY), visible.maxY - 120)))
        }
    }
    func show() { panel.orderFrontRegardless() }
}

struct SessionElapsedText: View {
    @ObservedObject var clock: SessionClock
    var body: some View { Text(TimeMath.duration(clock.seconds)) }
}

struct SessionMenuLabel: View {
    @ObservedObject var store: TrackerStore
    var body: some View {
        Label {
            if store.active == nil { Text("Time Micromanager") }
            else { SessionElapsedText(clock: store.clock) }
        } icon: { Image(systemName: "clock") }
    }
}

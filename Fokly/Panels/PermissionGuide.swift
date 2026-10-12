import AppKit
import ApplicationServices
import Observation
import SwiftUI

/// The two permissions Fokly can't work without.
enum Permission: String, CaseIterable, Identifiable {
    case screenRecording, accessibility
    var id: Self { self }

    var title: String {
        switch self {
        case .screenRecording: "Screen Recording"
        case .accessibility: "Accessibility"
        }
    }

    var reason: String {
        switch self {
        case .screenRecording: "To see the window you're working in. Read in memory, never saved."
        case .accessibility: "To take you back to the exact window and browser tab."
        }
    }

    var symbol: String {
        switch self {
        case .screenRecording: "rectangle.dashed.badge.record"
        case .accessibility: "arrow.uturn.backward"
        }
    }

    var tint: Color {
        switch self {
        case .screenRecording: Theme.focus
        case .accessibility: Theme.rest
        }
    }

    var settingsURL: URL {
        let anchor = self == .screenRecording ? "Privacy_ScreenCapture" : "Privacy_Accessibility"
        return URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)")!
    }

    var isGranted: Bool {
        switch self {
        case .screenRecording: CGPreflightScreenCaptureAccess()
        case .accessibility: AXIsProcessTrusted()
        }
    }
}

/// Live permission state, polled while someone is looking at it.
@MainActor @Observable
final class PermissionCenter {
    static let shared = PermissionCenter()
    private(set) var granted: Set<Permission> = []
    private var timer: Timer?
    private var watchers = 0

    var allGranted: Bool { granted.count == Permission.allCases.count }

    private init() { refresh() }

    func refresh() {
        let now = Set(Permission.allCases.filter(\.isGranted))
        if now != granted { granted = now }
    }

    func startWatching() {
        watchers += 1
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { PermissionCenter.shared.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopWatching() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - The guide that docks beside System Settings

/// Opens the right System Settings pane, then flies a small glass card out of the switch the
/// person clicked and docks it beside the Settings window, holding a Fokly row to drag into
/// the list. It follows the window around and leaves on its own once access is granted.
@MainActor
final class PermissionGuide {
    static let shared = PermissionGuide()
    private var panel: NSPanel?
    private var follow: Task<Void, Never>?
    private var current: Permission?
    private let state = GuideState()
    /// The tour steps aside while the guide is up and returns when it ends.
    var onStart: () -> Void = {}
    var onEnd: () -> Void = {}

    func request(_ permission: Permission, from origin: NSRect?) {
        guard !permission.isGranted else { return }
        if permission == .screenRecording {
            // Granting may make macOS relaunch Fokly; the tour picks up here again.
            Prefs.d.set(true, forKey: Prefs.tourAtPermissions)
        }
        dismiss(animated: false)
        onStart()
        current = permission
        state.permission = permission
        state.done = false
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(permission.settingsURL, configuration: config) { _, _ in }

        let p = FloatingPanel(movable: false) {
            GuideCard(state: self.state, close: { [weak self] in self?.dismiss(animated: true) })
        }
        p.level = .floating
        panel = p
        PermissionCenter.shared.startWatching()

        follow = Task { [weak self] in
            // Wait for the Settings window to appear and settle (it may restore from the Dock).
            var frame: NSRect?
            var last: NSRect?
            for _ in 0..<50 {
                if let f = Self.settingsWindowFrame() {
                    if f.integral == last?.integral { frame = f; break }
                    last = f
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
            guard let self, let p = self.panel, let settings = frame ?? last else { return }
            let dock = self.dockOrigin(for: p.frame.size, beside: settings)
            let start = origin.map { NSPoint(x: $0.midX - p.frame.width / 2, y: $0.midY - p.frame.height / 2) } ?? dock
            p.setFrameOrigin(start)
            p.alphaValue = 0
            p.orderFrontRegardless()
            Self.spring(p, to: dock)
            await self.track()
        }
    }

    func dismiss(animated: Bool) {
        follow?.cancel()
        follow = nil
        guard let panel else { return }
        self.panel = nil
        PermissionCenter.shared.stopWatching()
        onEnd()
        guard animated else { panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    /// Follow the Settings window; finish when access shows up or the window goes away.
    private func track() async {
        var lastSettings: NSRect?
        while !Task.isCancelled, let panel, let permission = current {
            PermissionCenter.shared.refresh()
            if permission.isGranted {
                state.done = true
                try? await Task.sleep(for: .seconds(0.9))
                dismiss(animated: true)
                NSApp.activate()
                NotificationCenter.default.post(name: .permissionGranted, object: permission.rawValue)
                return
            }
            guard let settings = Self.settingsWindowFrame() else {
                dismiss(animated: true)
                return
            }
            if settings != lastSettings {
                if lastSettings != nil { panel.setFrameOrigin(dockOrigin(for: panel.frame.size, beside: settings)) }
                lastSettings = settings
                state.arrowPointsLeft = panel.frame.minX > settings.midX
            }
            try? await Task.sleep(for: .milliseconds(120))
        }
    }

    /// Right of the Settings window when there's room, otherwise left; level with its list.
    private func dockOrigin(for size: NSSize, beside s: NSRect) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.intersects(s) } ?? NSScreen.main!
        let v = screen.visibleFrame
        let gap: CGFloat = -6  // the panel's own padding already leaves air
        var x = s.maxX + gap
        if x + size.width > v.maxX { x = s.minX - size.width - gap }
        let y = min(v.maxY - size.height, max(v.minY, s.maxY - size.height - 90))
        return NSPoint(x: max(v.minX, x), y: y)
    }

    /// The System Settings window in Cocoa coordinates (largest one, if there are several).
    static func settingsWindowFrame() -> NSRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]
        else { return nil }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        var best: NSRect?
        for info in list {
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                owner == "System Settings" || owner == "Nastavení systému" || owner == "System Preferences",
                (info[kCGWindowLayer as String] as? Int) == 0,
                let b = info[kCGWindowBounds as String] as? [String: CGFloat],
                let w = b["Width"], let h = b["Height"], let x = b["X"], let y = b["Y"], w > 300, h > 200
            else { continue }
            let r = NSRect(x: x, y: top - y - h, width: w, height: h)
            if best == nil || r.width * r.height > best!.width * best!.height { best = r }
        }
        return best
    }

    /// An underdamped spring: the card overshoots a touch and settles.
    private static func spring(_ panel: NSPanel, to target: NSPoint) {
        let from = panel.frame.origin
        guard !Motion.reduced else { panel.setFrameOrigin(target); panel.alphaValue = 1; return }
        let start = CACurrentMediaTime(), duration = 0.7
        let timer = Timer(timeInterval: 1 / 120, repeats: true) { t in
            MainActor.assumeIsolated {
                let p = min(1, (CACurrentMediaTime() - start) / duration)
                let e = 1 - exp(-7 * p) * cos(9 * p)
                panel.setFrameOrigin(NSPoint(x: from.x + (target.x - from.x) * e, y: from.y + (target.y - from.y) * e))
                panel.alphaValue = min(1, p * 4)
                if p >= 1 { panel.setFrameOrigin(target); t.invalidate() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}

extension Notification.Name {
    static let permissionGranted = Notification.Name("FoklyPermissionGranted")
}

@MainActor @Observable
final class GuideState {
    var permission: Permission = .screenRecording
    var done = false
    var arrowPointsLeft = true
}

private struct GuideCard: View {
    var state: GuideState
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: state.permission.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6).fill(state.permission.tint.gradient))
                Text(state.permission.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        .frame(width: 20, height: 20).background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            ZStack(alignment: .leading) {
                if state.done {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 26)).foregroundStyle(Theme.rest)
                            .symbolEffect(.bounce, value: state.done)
                        Text("You're all set.").font(.system(size: 17, weight: .bold, design: .rounded))
                    }
                    .transition(.blurReplace)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Drag Fokly into the list").font(.system(size: 17, weight: .bold, design: .rounded))
                        Text("Then make sure its switch is on.").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    .transition(.blurReplace)
                }
            }
            .animation(.smooth(duration: 0.35), value: state.done)

            HStack(spacing: 10) {
                if !state.arrowPointsLeft { Spacer(minLength: 0) }
                if state.arrowPointsLeft { NudgeArrow(left: true) }
                DraggableAppRow()
                    .frame(height: 46)
                    .opacity(state.done ? 0.4 : 1)
                if !state.arrowPointsLeft { NudgeArrow(left: false) }
            }

            Text("Can't drag it? Click + below the list and choose Fokly in Applications.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 300)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(36)
    }
}

/// Chevrons drifting toward the Settings list.
private struct NudgeArrow: View {
    var left: Bool
    var body: some View {
        TimelineView(.animation(paused: Motion.reduced)) { ctx in
            let phase = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
            let shift = sin(phase * .pi * 2) * 4
            Image(systemName: left ? "chevron.left.2" : "chevron.right.2")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.focus)
                .offset(x: left ? -shift : shift)
        }
        .frame(width: 22)
        .accessibilityHidden(true)
    }
}

/// A row with Fokly's icon and name that drags the app bundle, which is what the
/// Privacy & Security lists accept.
private struct DraggableAppRow: NSViewRepresentable {
    func makeNSView(context: Context) -> DragRowView { DragRowView() }
    func updateNSView(_ view: DragRowView, context: Context) {}
}

final class DragRowView: NSView, NSDraggingSource {
    private var down: NSEvent?
    private var dragging = false
    private let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    private var hovering = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        setAccessibilityLabel("Fokly app, drag into the list")
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 200, height: 46) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: dragging ? .closedHand : .openHand) }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let shape = NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12)
        (NSColor.controlBackgroundColor.withAlphaComponent(hovering ? 1 : 0.85)).setFill()
        shape.fill()
        NSColor.separatorColor.setStroke()
        shape.lineWidth = 1
        shape.stroke()
        icon.draw(in: NSRect(x: 10, y: (bounds.height - 30) / 2, width: 30, height: 30))
        let title = NSAttributedString(string: "Fokly", attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.labelColor,
        ])
        title.draw(at: NSPoint(x: 50, y: (bounds.height - title.size().height) / 2))
        // Grip dots on the right: this thing moves.
        NSColor.tertiaryLabelColor.setFill()
        for row in 0..<3 {
            for col in 0..<2 {
                let x = bounds.maxX - 22 + CGFloat(col) * 6, y = bounds.midY - 7 + CGFloat(row) * 6
                NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 2.6, height: 2.6)).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) { down = event }

    override func mouseDragged(with event: NSEvent) {
        guard let down, !dragging else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard hypot(dx, dy) > 3 else { return }
        dragging = true
        window?.invalidateCursorRects(for: self)
        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        item.setDraggingFrame(bounds, contents: snapshot())
        let session = beginDraggingSession(with: [item], event: down, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) { down = nil }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragging = false
        down = nil
        window?.invalidateCursorRects(for: self)
        PermissionCenter.shared.refresh()
    }

    private func snapshot() -> NSImage {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return icon }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }
}

// MARK: - The tour slide

/// The last tour slide: two switches. Each opens Settings and the docking guide.
struct PermissionsArt: View {
    @State private var center = PermissionCenter.shared

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Permission.allCases) { p in
                PermissionRow(permission: p, granted: center.granted.contains(p))
            }
        }
        .padding(.horizontal, 22)
        .onAppear { center.startWatching() }
        .onDisappear { center.stopWatching() }
    }
}

private struct PermissionRow: View {
    var permission: Permission
    var granted: Bool
    @State private var rowFrame: CGRect = .zero

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: permission.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9).fill(permission.tint.gradient))
                if granted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white, Theme.rest)
                        .offset(x: 5, y: 5)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title).font(.system(size: 13, weight: .semibold))
                Text(permission.reason).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            FoklySwitch(isOn: granted) {
                guard !granted else { return }
                PermissionGuide.shared.request(permission, from: screenRect())
            }
            .accessibilityLabel("\(permission.title), \(granted ? "on" : "off")")
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 16).fill(.background.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(granted ? Theme.rest.opacity(0.5) : .clear, lineWidth: 1))
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { rowFrame = $0 }
        .animation(.spring(response: 0.4, dampingFraction: 0.65), value: granted)
    }

    /// The switch's place on screen, where the guide flies out from.
    private func screenRect() -> NSRect? {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.level == .floating && $0.frame.width > 400 })
        else { return nil }
        let h = window.contentView?.bounds.height ?? window.frame.height
        return NSRect(x: window.frame.minX + rowFrame.maxX - 40, y: window.frame.minY + h - rowFrame.midY, width: 1, height: 1)
    }
}

/// A switch in Fokly's colors that stays lively even when its window isn't key.
private struct FoklySwitch: View {
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Capsule()
                .fill(isOn ? Theme.rest : Color.primary.opacity(0.16))
                .frame(width: 40, height: 24)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 20, height: 20).padding(2)
                        .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isOn)
        }
        .buttonStyle(PressableStyle())
    }
}

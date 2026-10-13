import AppKit
import Observation
import SwiftUI

/// The menu bar presence: a quiet mark when idle, a live pill while focusing.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let focus = FocusController.shared
    let miniTimer = MiniTimerController()
    private let tour = WelcomeTour()
    private let nudges = NudgePresenter()
    private var settingsWindow: NSWindow?
    private var insightsWindow: NSWindow?
    private var lastPhase: Phase = .idle
    private var lastLook = ""
    private var lastAccent = ""
    private var isClosing = false

    override init() {
        super.init()

        let root = PopoverRoot(
            toggleMiniTimer: { [weak self] in self?.miniTimer.toggle() },
            openSettings: { [weak self] in self?.showSettings() },
            openInsights: { [weak self] in self?.showInsights() },
            onHeight: { [weak self] in self?.contentHeightChanged($0) }
        ).environment(focus)
        // How the popover changes height without the content jumping or the app crashing:
        // - The SwiftUI view is not the popover's root. As the root, NSHostingView resizes the window
        //   to fit its content by itself, fights our sizing and can recurse until the stack overflows.
        // - It has a fixed, tall size, pinned to the top of a top-anchored container. If SwiftUI's
        //   own bounds changed mid-animation, it would animate the content from the bottom edge.
        // - Only the popover window changes height, animated by NSPopover, revealing or clipping
        //   the content, which stays exactly where it is.
        let hosting = NSHostingView(rootView: root)
        let initial = NSSize(width: Theme.popoverWidth, height: max(200, hosting.fittingSize.height))
        hosting.sizingOptions = []
        let container = NSViewController()
        container.view = TopAnchoredView(frame: NSRect(origin: .zero, size: initial))
        container.view.clipsToBounds = true
        hosting.frame = NSRect(x: 0, y: 0, width: Theme.popoverWidth, height: 1600)
        hosting.autoresizingMask = [.width]
        container.view.addSubview(hosting)
        popover.contentSize = initial
        popover.contentViewController = container
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Fokly")
        }

        focus.presentNudge = { [weak self] in self?.nudges.show($0) }
        focus.dismissNudge = { [weak self] in self?.nudges.dismiss() }
        miniTimer.openPopover = { [weak self] in self?.showPopover() }
        tour.targetFrame = { [weak self] in self?.item.button?.window?.frame }
        tour.onFinish = { [weak self] in self?.showPopover() }
        NotificationCenter.default.addObserver(forName: .showWelcomeTour, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { [weak self] in self?.showWelcome() }
        }

        observe()
        // Accent color lives in UserDefaults, outside observation: repaint when it changes.
        // Only the accent color matters here. Other writes (a window saving its position, say)
        // must not trigger a redraw, or they can loop back through render().
        lastAccent = Theme.focusNS.hexString
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self, Theme.focusNS.hexString != self.lastAccent else { return }
                self.lastAccent = Theme.focusNS.hexString
                self.render()
            }
        }
    }

    // MARK: - Rendering

    private func observe() {
        withObservationTracking {
            render()
        } onChange: {
            Task { @MainActor [weak self] in self?.observe() }
        }
    }

    private func render() {
        guard let button = item.button else { return }
        let phase = focus.phase

        // Crossfade when the pill changes state or color, never on the per-second tick.
        let look = "\(phase)|\(focus.attention)|\(Theme.focusNS.hexString)"
        if look != lastLook {
            if !lastLook.isEmpty, !Motion.reduced {
                button.wantsLayer = true
                let fade = CATransition()
                fade.type = .fade
                fade.duration = 0.35
                fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                button.layer?.add(fade, forKey: "foklyLook")
            }
            lastLook = look
        }

        switch phase {
        case .idle, .finished:
            button.image = StatusArt.mark()
            button.title = ""
        case .focusing:
            let tint = focus.attention == .drifting ? Theme.driftNS : Theme.focusNS
            button.image = StatusArt.pill(text: Clock.string(focus.clock), progress: focus.ring, tint: tint, glyph: .ring)
        case .paused:
            button.image = StatusArt.pill(text: Clock.string(focus.clock), progress: focus.ring, tint: .secondaryLabelColor, glyph: .pause)
        case .onBreak:
            button.image = StatusArt.pill(text: Clock.string(focus.breakRemaining), progress: focus.ring, tint: Theme.restNS, glyph: .ring)
        }
        button.toolTip = focus.isActive ? focus.goal : "Fokly — start a focus session"
        switch phase {
        case .focusing: button.setAccessibilityValue("\(focus.attention == .drifting ? "Distracted" : "Focusing"), \(Clock.string(focus.clock)) left")
        case .paused: button.setAccessibilityValue("Paused")
        case .onBreak: button.setAccessibilityValue("On a break, \(Clock.string(focus.breakRemaining)) left")
        default: button.setAccessibilityValue(nil)
        }

        if phase != lastPhase {
            // Record the new phase first: reacting to it (showing the floating timer) can
            // re-enter render(), which must not see the same change again.
            let old = lastPhase
            lastPhase = phase
            phaseChanged(from: old, to: phase)
        }
    }

    private func phaseChanged(from old: Phase, to new: Phase) {
        let wantsMini = Prefs.d.bool(forKey: Prefs.showMiniTimer)
        switch new {
        case .focusing where old == .idle || old == .finished:
            if wantsMini { miniTimer.show() }
            popover.performClose(nil)
        case .idle, .finished:
            miniTimer.hide()
        default: break
        }
    }

    // MARK: - Actions

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    func showPopover() {
        guard let button = item.button else { return }
        NSApp.activate()
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showMenu() {
        let menu = NSMenu()
        if focus.isActive {
            menu.addItem(withTitle: focus.phase == .paused ? "Resume" : "Pause", action: #selector(pause), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Finish Session", action: #selector(finish), keyEquivalent: "").target = self
            menu.addItem(withTitle: miniTimer.isVisible ? "Hide Floating Timer" : "Show Floating Timer", action: #selector(toggleMini), keyEquivalent: "").target = self
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Insights & History…", action: #selector(insights), keyEquivalent: "y").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit Fokly", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func pause() { focus.togglePause() }
    @objc private func finish() { focus.finish() }
    @objc private func toggleMini() { miniTimer.toggle() }
    @objc private func settings() { showSettings() }
    @objc private func insights() { showInsights() }

    // Stress-test hooks.
    var insightsWindowForTest: NSWindow? { insightsWindow }
    func dismissPopoverForTest() { popover.performClose(nil) }
    var popoverWindowForTest: NSWindow? { popover.contentViewController?.view.window }
    var nudgeWindowForTest: NSWindow? { nudges.window }
    var statusButtonFrameForTest: NSRect? { item.button?.window?.frame }

    func showWelcome(atPermissions: Bool = false) {
        popover.performClose(nil)
        settingsWindow?.close()
        tour.show(atPermissions: atPermissions)
    }

    func showInsights() {
        popover.performClose(nil)
        if insightsWindow == nil {
            let host = NSHostingController(rootView: InsightsView().environment(focus))
            let window = NSWindow(contentViewController: host)
            window.title = "Insights"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 760, height: 720))
            window.minSize = NSSize(width: 620, height: 520)
            window.setFrameAutosaveName("FoklyInsights")
            window.center()
            insightsWindow = window
        }
        NSApp.activate()
        insightsWindow?.makeKeyAndOrderFront(nil)
    }

    func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(setTitle: { [weak self] in self?.settingsWindow?.title = $0 }).environment(focus))
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbar = NSToolbar(identifier: "FoklySettings")
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 720, height: 520))
            window.setFrameAutosaveName("FoklySettings")
            window.center()
            settingsWindow = window
            window.title = SettingsView.Pane.general.title
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// The content reports its height; the popover window animates to it. The SwiftUI view itself
    /// never changes size (see init), so the content stays put while the window reveals or clips it.
    /// The height SwiftUI last reported, waiting to be applied on the next run-loop turn.
    private var pendingHeight: CGFloat?

    private func contentHeightChanged(_ height: CGFloat) {
        // This arrives from inside SwiftUI's layout pass. An animated popover resize spins a nested
        // run loop, which would re-enter the update cycle mid-layout and crash (editing the goal did),
        // so apply the latest height just after the pass instead.
        let scheduled = pendingHeight != nil
        pendingHeight = ceil(height)
        guard !scheduled else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let h = self.pendingHeight else { return }
            self.pendingHeight = nil
            guard !self.isClosing, abs(self.popover.contentSize.height - h) > 0.5 else { return }
            self.popover.contentSize = NSSize(width: Theme.popoverWidth, height: h)
        }
    }

    func popoverWillShow(_ notification: Notification) {
        isClosing = false
        popover.animates = !Motion.reduced
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        isClosing = true
        return true
    }

    func popoverDidClose(_ notification: Notification) {
        isClosing = false
        if focus.editingGoal, focus.isActive { focus.editingGoal = false }
    }
}

/// Draws the menu bar artwork.
enum StatusArt {
    enum Glyph { case ring, pause }

    static func mark() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let c = NSPoint(x: rect.midX, y: rect.midY)
            NSColor.black.setStroke()
            let ring = NSBezierPath()
            ring.appendArc(withCenter: c, radius: 6.5, startAngle: 90, endAngle: 90 - 260, clockwise: true)
            ring.lineWidth = 1.9
            ring.lineCapStyle = .round
            ring.stroke()
            NSColor.black.withAlphaComponent(0.35).setStroke()
            let rest = NSBezierPath()
            rest.appendArc(withCenter: c, radius: 6.5, startAngle: 90 - 260, endAngle: 90 - 360, clockwise: true)
            rest.lineWidth = 1.9
            rest.stroke()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - 2.2, y: c.y - 2.2, width: 4.4, height: 4.4)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    static func pill(text: String, progress: Double, tint: NSColor, glyph: Glyph) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 13) } ?? font
        let attrs: [NSAttributedString.Key: Any] = [.font: rounded, .foregroundColor: tint]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let height: CGFloat = 22
        let width = ceil(textSize.width) + 38

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let pill = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: height / 2, yRadius: height / 2)
            tint.withAlphaComponent(0.17).setFill()
            pill.fill()

            let c = NSPoint(x: 14, y: rect.midY)
            switch glyph {
            case .ring:
                tint.withAlphaComponent(0.3).setStroke()
                let track = NSBezierPath(ovalIn: NSRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12))
                track.lineWidth = 2
                track.stroke()
                tint.setStroke()
                let arc = NSBezierPath()
                let p = max(0.02, min(1, progress))
                arc.appendArc(withCenter: c, radius: 6, startAngle: 90, endAngle: 90 - 360 * p, clockwise: true)
                arc.lineWidth = 2
                arc.lineCapStyle = .round
                arc.stroke()
            case .pause:
                tint.setFill()
                NSBezierPath(roundedRect: NSRect(x: c.x - 4, y: c.y - 5, width: 3, height: 10), xRadius: 1, yRadius: 1).fill()
                NSBezierPath(roundedRect: NSRect(x: c.x + 1, y: c.y - 5, width: 3, height: 10), xRadius: 1, yRadius: 1).fill()
            }

            (text as NSString).draw(at: NSPoint(x: 26, y: rect.midY - textSize.height / 2), withAttributes: attrs)
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// A container whose origin is its top-left corner, so when the popover grows or shrinks, the
/// SwiftUI content it holds stays pinned to the top instead of riding along with the bottom edge.
private final class TopAnchoredView: NSView {
    override var isFlipped: Bool { true }
}

extension Notification.Name {
    static let showWelcomeTour = Notification.Name("ShowWelcomeTour")
}

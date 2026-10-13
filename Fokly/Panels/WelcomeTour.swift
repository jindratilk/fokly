import AppKit
import SwiftUI

/// First-run tour: a floating glass card with live, animated slides. The last step flies the card
/// into the menu bar icon, so people learn where the app lives, then opens the setup popover.
@MainActor
final class WelcomeTour {
    private var panel: NSPanel?
    private var pulse: NSPanel?
    /// Where the card flies to at the end: the status item's frame on screen.
    var targetFrame: () -> NSRect? = { nil }
    var onFinish: () -> Void = {}

    /// Get Started: both permissions are on, so onboarding is done.
    private func complete() {
        Prefs.d.set(true, forKey: Prefs.onboarded)
        Prefs.d.set(false, forKey: Prefs.tourAtPermissions)
        flyIntoMenuBar()
    }

    /// - Parameter atPermissions: open straight on the last slide, e.g. after macOS relaunched
    ///   Fokly to apply Screen Recording.
    func show(atPermissions: Bool = false) {
        guard panel == nil else { panel?.makeKeyAndOrderFront(nil); return }
        let p = FloatingPanel(movable: true) {
            TourCard(startPage: atPermissions ? TourCard.permissionsPage : 0,
                     finish: { [weak self] in self?.complete() },
                     skip: { [weak self] in self?.close(finished: true) })
        }
        // The card fades out of the way of System Settings while the guide is up, then comes back.
        PermissionGuide.shared.onStart = { [weak self] in
            guard let p = self?.panel else { return }
            NSAnimationContext.runAnimationGroup { $0.duration = 0.25; p.animator().alphaValue = 0 }
            p.ignoresMouseEvents = true
        }
        PermissionGuide.shared.onEnd = { [weak self] in
            guard let p = self?.panel else { return }
            p.ignoresMouseEvents = false
            NSApp.activate()
            p.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { $0.duration = 0.35; p.animator().alphaValue = 1 }
        }
        p.level = .floating
        guard let screen = NSScreen.active else { return }
        let v = screen.visibleFrame
        let size = p.frame.size
        let rest = NSPoint(x: v.midX - size.width / 2, y: v.maxY - size.height - v.height * 0.12)
        p.setFrameOrigin(NSPoint(x: rest.x, y: rest.y - (Motion.reduced ? 0 : 16)))
        p.alphaValue = 0
        NSApp.activate()
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.5
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            p.animator().alphaValue = 1
            p.animator().setFrameOrigin(rest)
        }
        panel = p
    }

    private func close(finished: Bool) {
        PermissionGuide.shared.onEnd = {}
        PermissionGuide.shared.onStart = {}
        PermissionGuide.shared.dismiss(animated: false)
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().alphaValue = 0 },
                                             completionHandler: { panel.orderOut(nil) })
        if finished { onFinish() }
    }

    /// The card folds away and a spark of the accent color flies from it into the menu bar icon,
    /// which answers with a ring. People see exactly where Fokly went.
    private func flyIntoMenuBar() {
        PermissionGuide.shared.onEnd = {}
        PermissionGuide.shared.onStart = {}
        PermissionGuide.shared.dismiss(animated: false)
        guard let panel, let target = targetFrame(), let screen = panel.screen ?? NSScreen.active, !Motion.reduced
        else { close(finished: true); return }
        self.panel = nil
        let f = panel.frame
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })

        // SwiftUI coordinates inside a screen-sized overlay: origin top-left.
        let sf = screen.frame
        let from = CGPoint(x: f.midX - sf.minX, y: sf.maxY - f.maxY + 40)
        let to = CGPoint(x: target.midX - sf.minX, y: sf.maxY - target.midY)
        let overlay = FloatingPanel(movable: false) {
            Spark(from: from, to: to).frame(width: sf.width, height: sf.height)
        }
        overlay.level = .popUpMenu
        overlay.ignoresMouseEvents = true
        overlay.setFrame(sf, display: true)
        overlay.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) { [weak self] in
            overlay.orderOut(nil)
            self?.ring(at: target)
        }
    }

    private func ring(at target: NSRect) {
        let size: CGFloat = 64
        let p = FloatingPanel(movable: false) { RingPulse().frame(width: size, height: size) }
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.setFrame(NSRect(x: target.midX - size / 2, y: target.midY - size / 2, width: size, height: size), display: true)
        p.orderFrontRegardless()
        pulse = p
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.onFinish() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            self?.pulse?.orderOut(nil)
            self?.pulse = nil
        }
    }
}

/// A glowing dot travelling along a gentle arc from the card to the icon.
private struct Spark: View {
    var from: CGPoint
    var to: CGPoint
    @State private var t: CGFloat = 0

    var body: some View {
        Circle()
            .fill(Theme.focus)
            .frame(width: 14, height: 14)
            .shadow(color: Theme.focus.opacity(0.9), radius: 10)
            .scaleEffect(1 - 0.45 * t)
            .modifier(ArcPosition(from: from, to: to, t: t))
            .onAppear { withAnimation(.timingCurve(0.45, 0, 0.25, 1, duration: 0.6)) { t = 1 } }
    }
}

/// Animatable position on a quadratic curve that bows upward, so the spark swoops rather than slides.
private struct ArcPosition: ViewModifier, Animatable {
    var from: CGPoint
    var to: CGPoint
    var t: CGFloat
    var animatableData: CGFloat {
        get { t }
        set { t = newValue }
    }

    func body(content: Content) -> some View {
        let control = CGPoint(x: (from.x + to.x) / 2 + (to.x - from.x) * 0.15, y: min(from.y, to.y) - 60)
        let u = 1 - t
        let x = u * u * from.x + 2 * u * t * control.x + t * t * to.x
        let y = u * u * from.y + 2 * u * t * control.y + t * t * to.y
        return content.position(x: x, y: y)
    }
}

private struct RingPulse: View {
    @State private var go = false
    var body: some View {
        Circle()
            .strokeBorder(Theme.focus, lineWidth: 2.5)
            .scaleEffect(go ? 1 : 0.25)
            .opacity(go ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 0.9)) { go = true } }
    }
}

// MARK: - The card

private struct Slide: Identifiable {
    let id: Int
    let title: String
    let text: String
}

private struct TourCard: View {
    static let permissionsPage = 5
    var finish: () -> Void
    var skip: () -> Void
    @State private var page: Int
    @State private var forward = true
    @State private var permissions = PermissionCenter.shared

    init(startPage: Int, finish: @escaping () -> Void, skip: @escaping () -> Void) {
        self.finish = finish
        self.skip = skip
        _page = State(initialValue: startPage)
    }

    private var isLast: Bool { page == slides.count - 1 }
    /// On the last slide, Get Started waits until both permissions are on.
    private var canFinish: Bool { !isLast || permissions.allGranted }

    private let slides = [
        Slide(id: 0, title: "Never be distracted again.",
              text: "Tell Fokly what you're working on. A quiet timer keeps you company in the menu bar."),
        Slide(id: 1, title: "It checks your screen.",
              text: "Every few seconds Fokly looks at the window in front of you. Each bar is one check."),
        Slide(id: 2, title: "A reminder when you get distracted.",
              text: "Stay distracted for a while and Fokly reminds you, then takes you right back."),
        Slide(id: 3, title: "Private by design.",
              text: "Fokly uses a local AI model running on your Mac that keeps you from distractions. No account, no cloud, nothing saved."),
        Slide(id: 4, title: "Fokly lives up here.",
              text: "Click the ring in the menu bar, or press ⌃⌥Space from anywhere."),
        Slide(id: 5, title: "Two things, and you're set.",
              text: "Fokly needs both to keep you on track. Flip a switch, then drag Fokly into the list that opens."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                art
                    .id(page)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(x: forward ? 40 : -40)),
                        removal: .opacity.combined(with: .offset(x: forward ? -40 : 40))))
            }
            .frame(height: 210)
            .frame(maxWidth: .infinity)
            .background(
                RadialGradient(colors: [Theme.focus.opacity(0.28), .clear], center: .init(x: 0.5, y: 0.35),
                               startRadius: 4, endRadius: 260))
            .clipped()
            .overlay(alignment: .topTrailing) {
                if !isLast || !permissions.allGranted {
                    Button(isLast ? "Later" : "Skip", action: skip)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .keyboardShortcut(.cancelAction)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(slides[page].title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(slides[page].text)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .id("text\(page)")
            .transition(.opacity)

            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    ForEach(slides) { s in
                        Capsule()
                            .fill(s.id == page ? Theme.focus : Color.primary.opacity(0.18))
                            .frame(width: s.id == page ? 18 : 6, height: 6)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Step \(page + 1) of \(slides.count)")
                Spacer()
                if page > 0 {
                    Button { go(-1) } label: {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold)).frame(width: 36, height: 36)
                    }
                    .buttonStyle(TourButtonStyle(prominent: false, circle: true))
                    .accessibilityLabel("Back")
                    .keyboardShortcut(.leftArrow, modifiers: [])
                }
                Button { isLast ? finish() : go(1) } label: {
                    Text(isLast ? (permissions.allGranted ? "Get Started" : "Turn on both") : "Continue")
                        .contentTransition(.interpolate)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 22)
                        .frame(height: 36)
                }
                .buttonStyle(TourButtonStyle(prominent: canFinish, circle: false))
                .disabled(!canFinish)
                .animation(.smooth(duration: 0.3), value: canFinish)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .frame(width: 440)
        .clipShape(.rect(cornerRadius: 28))  // keeps the artwork's glow inside the rounded corners
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .padding(48)  // room for the glass shadow, which the window would otherwise cut off
        .animation(.smooth(duration: 0.35), value: page)
        .background(KeyArrows(next: { go(1) }))
        .onReceive(NotificationCenter.default.publisher(for: .tourAdvance)) { _ in
            isLast ? (canFinish ? finish() : ()) : go(1)
        }
    }

    private func go(_ delta: Int) {
        let next = min(slides.count - 1, max(0, page + delta))
        guard next != page else { return }
        forward = delta > 0
        page = next
    }

    @ViewBuilder private var art: some View {
        switch page {
        case 0: PillArt()
        case 1: StripArt()
        case 2: NudgeArt()
        case 3: PrivacyArt()
        case 4: MenuBarArt()
        default: PermissionsArt()
        }
    }
}

/// Right arrow advances too (left is a shortcut on the Back button).
private struct KeyArrows: View {
    var next: () -> Void
    var body: some View {
        Button("", action: next).keyboardShortcut(.rightArrow, modifiers: []).opacity(0).allowsHitTesting(false)
    }
}

// MARK: - Live artwork

/// The menu bar pill counting down, big.
private struct PillArt: View {
    @State private var start = Date()
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = max(0, 24 * 60 + 13 - Int(ctx.date.timeIntervalSince(start)))
            let progress = 1 - Double(left) / 3000
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Theme.focus.opacity(0.25), lineWidth: 5)
                    Circle().trim(from: 0, to: progress)
                        .stroke(Theme.focus, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.smooth(duration: 0.9), value: progress)
                }
                .frame(width: 34, height: 34)
                Text(Clock.string(TimeInterval(left)))
                    .font(.clock(44, weight: .bold))
                    .foregroundStyle(Theme.focus)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: left)
            }
            .padding(.horizontal, 26).padding(.vertical, 14)
            .background(Capsule().fill(Theme.focus.opacity(0.16)))
        }
    }
}

/// Glances arriving one by one; a short drift in amber, then back on goal.
private struct StripArt: View {
    @State private var start = Date()
    private let count = 34
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: Motion.reduced)) { ctx in
            let t = Motion.reduced ? 99 : ctx.date.timeIntervalSince(start)
            let shown = min(count, Int(t / 0.09))
            VStack(spacing: 14) {
                HStack(spacing: 4) {
                    ForEach(0..<count, id: \.self) { i in
                        Capsule()
                            .fill(i < shown ? ((14...19).contains(i) ? Theme.drift : Theme.focus) : Color.primary.opacity(0.1))
                            .frame(width: 6, height: i < shown ? 34 : 14)
                            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: shown)
                    }
                }
                .frame(height: 36)
                HStack(spacing: 16) {
                    Label("On goal", systemImage: "circle.fill").foregroundStyle(Theme.focus)
                    Label("Distracted", systemImage: "circle.fill").foregroundStyle(Theme.drift)
                }
                .font(.caption.weight(.medium))
                .labelStyle(DotLabel())
            }
        }
    }
}

private struct DotLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.icon.font(.system(size: 6)); configuration.title.foregroundStyle(.secondary) }
    }
}

/// A miniature reminder sliding in.
private struct NudgeArt: View {
    @State private var shown = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7).fill(Color.red.gradient).frame(width: 28, height: 28)
                    .overlay(Image(systemName: "play.fill").font(.system(size: 11)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Still with “Write the Q3 report”?").font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text("That's a long F1 video. The report is waiting.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                Text("Take me back").foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.focus))
                Text("This is relevant").padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            .font(.system(size: 11, weight: .semibold))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(.background.opacity(0.7)))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .offset(x: shown || Motion.reduced ? 0 : 60)
        .opacity(shown || Motion.reduced ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.15)) { shown = true } }
    }
}

private struct PrivacyArt: View {
    @State private var shown = false
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 52))
                .foregroundStyle(Theme.rest)
                .symbolEffect(.bounce, value: shown)
            HStack(spacing: 6) {
                ForEach(["On this Mac", "No account", "No cloud"], id: \.self) { t in
                    Text(t).font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            }
        }
        .onAppear { shown = true }
    }
}

/// A slice of menu bar with the Fokly ring, breathing.
private struct MenuBarArt: View {
    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 16) {
                Image(systemName: "wifi").opacity(0.6)
                Image(systemName: "battery.75percent").opacity(0.6)
                ZStack {
                    PulseHalo()
                    FoklyMark(size: 18, tint: Theme.focus)
                }
                .frame(width: 30, height: 30)
                Text("Tue 9:41").font(.system(size: 13, weight: .medium)).opacity(0.6)
            }
            .font(.system(size: 14))
            .padding(.horizontal, 18).padding(.vertical, 8)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
            HStack(spacing: 4) {
                ForEach(["⌃", "⌥", "Space"], id: \.self) { k in
                    Text(k).font(.system(size: 13, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                }
            }
        }
    }
}

private struct PulseHalo: View {
    var body: some View {
        TimelineView(.animation(paused: Motion.reduced)) { ctx in
            let phase = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            Circle().fill(Theme.focus.opacity(0.35 * (1 - phase))).scaleEffect(0.6 + phase)
        }
    }
}

extension Notification.Name {
    /// Debug hook for recording the tour.
    static let tourAdvance = Notification.Name("TourAdvance")
}

/// Always-live buttons: the tour may sit behind another app's window, and system button styles
/// would then render grey. Same shapes and colors as the rest of Fokly.
private struct TourButtonStyle: ButtonStyle {
    var prominent: Bool
    var circle: Bool
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background {
                if circle {
                    Circle().fill(Color.primary.opacity(hovering ? 0.14 : 0.08))
                } else {
                    Capsule().fill(prominent ? Theme.focus : Color.primary.opacity(hovering ? 0.14 : 0.08))
                }
            }
            .overlay {
                if circle { Circle().fill(Color.black.opacity(configuration.isPressed ? 0.12 : 0)) }
                else { Capsule().fill(Color.black.opacity(configuration.isPressed ? 0.12 : 0)) }
            }
            .brightness(prominent && hovering ? 0.04 : 0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.spring(response: 0.2), value: configuration.isPressed)
    }
}

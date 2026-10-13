import AppKit
import SwiftUI

/// A small always-on-top timer you can park anywhere.
@MainActor
final class MiniTimerController {
    private var panel: NSPanel?
    var isVisible: Bool { panel?.isVisible ?? false }
    var window: NSWindow? { panel }
    var openPopover: () -> Void = {}

    func show() {
        if panel == nil {
            let focus = FocusController.shared
            let p = FloatingPanel(movable: true) {
                MiniTimerView(open: { [weak self] in self?.openPopover() })
                    .environment(focus)
            }
            p.setFrameAutosaveName("FoklyMiniTimer")
            if !p.setFrameUsingName("FoklyMiniTimer"), let screen = NSScreen.active {
                let v = screen.visibleFrame
                p.setFrameOrigin(NSPoint(x: v.midX - p.frame.width / 2, y: v.maxY - p.frame.height - 8))
            }
            panel = p
        }
        guard let panel else { return }
        let rest = panel.frame.origin
        panel.alphaValue = 0
        if !Motion.reduced { panel.setFrameOrigin(NSPoint(x: rest.x, y: rest.y + 12)) }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(rest)
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        let rest = panel.frame.origin
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            if !Motion.reduced { panel.animator().setFrameOrigin(NSPoint(x: rest.x, y: rest.y + 8)) }
        }, completionHandler: {
            panel.orderOut(nil)
            panel.setFrameOrigin(rest)  // keep the user's spot for next time
        })
    }

    func toggle() { isVisible ? hide() : show() }
}

struct MiniTimerView: View {
    @Environment(FocusController.self) private var focus
    var open: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            Button(action: open) {
                HStack(spacing: 12) {
                    ZStack {
                        ProgressRing(progress: focus.ring,
                                     tint: tint, lineWidth: 3.5)
                        Image(systemName: symbol)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(tint)
                    }
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tint.opacity(0.85))
                        Text(Clock.string(focus.phase == .onBreak ? focus.breakRemaining : focus.clock))
                            .font(.clock(26, weight: .bold))
                            .foregroundStyle(tint)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy, value: Int(focus.clock))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(focus.goal)

            Spacer(minLength: 18)

            if focus.phase == .onBreak {
                RoundButton(symbol: "forward.fill", tint: Theme.rest, size: 38, help: "Back to focus") { focus.endBreak() }
            } else {
                RoundButton(symbol: focus.phase == .paused ? "play.fill" : "pause.fill", tint: tint, size: 38,
                            help: focus.phase == .paused ? "Resume" : "Pause") { focus.togglePause() }
            }
            RoundButton(symbol: "stop.fill", tint: .secondary, size: 38, help: "Finish") { focus.finish() }
        }
        .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 11)
        .frame(width: 300)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .padding(10)
        .onHover { hovering = $0 }
    }

    private var tint: Color {
        switch focus.phase {
        case .onBreak: Theme.rest
        case .paused: .secondary
        default: focus.attention == .drifting ? Theme.drift : Theme.focus
        }
    }

    private var label: String {
        switch focus.phase {
        case .onBreak: "On break"
        case .paused: "Paused"
        default: focus.attention == .drifting ? "Distracted" : "Focusing"
        }
    }

    private var symbol: String {
        switch focus.phase {
        case .onBreak: "cup.and.heat.waves.fill"
        case .paused: "pause.fill"
        default: "scope"
        }
    }
}

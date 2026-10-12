import AppKit
import SwiftUI

/// Slides a gentle reminder in under the menu bar, top right.
@MainActor
final class NudgePresenter {
    private var panel: NSPanel?
    private var autoHide: Task<Void, Never>?
    var window: NSWindow? { panel }

    func show(_ nudge: Nudge) {
        dismiss(animated: false)
        let focus = FocusController.shared
        let panel = FloatingPanel(movable: false) {
            NudgeView(
                nudge: nudge,
                takeMeBack: { focus.takeMeBack() },
                relevant: { focus.markRelevant() },
                takeBreak: { focus.breakFromNudge() },
                close: { [weak self] in self?.dismiss() })
        }
        panel.level = .statusBar
        guard let screen = NSScreen.active else { return }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        let target = NSPoint(x: visible.maxX - size.width - 10, y: visible.maxY - size.height - 10)
        panel.setFrameOrigin(NSPoint(x: target.x + (Motion.reduced ? 0 : 24), y: target.y))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().setFrameOrigin(target)
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        autoHide = Task { [weak self] in
            try? await Task.sleep(for: .seconds(90))
            if !Task.isCancelled { self?.dismiss() }
        }
    }

    func dismiss(animated: Bool = true) {
        autoHide?.cancel()
        guard let panel else { return }
        self.panel = nil
        guard animated else { panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(NSPoint(x: panel.frame.minX + (Motion.reduced ? 0 : 16), y: panel.frame.minY))
        }, completionHandler: { panel.orderOut(nil) })
    }
}

struct NudgeView: View {
    var nudge: Nudge
    var takeMeBack: () -> Void
    var relevant: () -> Void
    var takeBreak: () -> Void
    var close: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    AppIconView(bundleID: nudge.bundleID, size: 38)
                    Circle().fill(Theme.drift)
                        .frame(width: 13, height: 13)
                        .overlay(Image(systemName: "arrow.uturn.backward").font(.system(size: 7, weight: .black)).foregroundStyle(.white))
                        .offset(x: 3, y: 3)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Still with “\(nudge.goal)”?")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                    Text(nudge.reminder)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
                .opacity(hovering ? 1 : 0)
            }

            HStack(spacing: 8) {
                action("Take me back", "arrow.uturn.backward", takeMeBack, prominent: true)
                action("This is relevant", "checkmark", relevant)
                action("Take a break", "cup.and.heat.waves", takeBreak)
            }
        }
        .padding(16)
        .frame(width: 400)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(12)  // room for the glass shadow
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private func action(_ title: String, _ symbol: String, _ run: @escaping () -> Void, prominent: Bool = false) -> some View {
        Button(action: run) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(NudgeButtonStyle(prominent: prominent))
    }
}

/// Always-live button look: the panel never becomes key, so system styles would render inactive.
struct NudgeButtonStyle: ButtonStyle {
    var prominent: Bool
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(
                Capsule().fill(prominent ? Theme.focus : Color.primary.opacity(hovering ? 0.14 : 0.08))
            )
            .overlay(Capsule().fill(Color.black.opacity(configuration.isPressed ? 0.12 : 0)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.spring(response: 0.2), value: configuration.isPressed)
    }
}

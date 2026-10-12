import AppKit
import SwiftUI

/// The Fokly mark: a ring with a single point held on it.
struct FoklyMark: View {
    var size: CGFloat = 18
    var tint: Color = Theme.focus

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.35), lineWidth: size * 0.12)
            Circle().trim(from: 0, to: 0.72)
                .stroke(tint, style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle().fill(tint).frame(width: size * 0.3, height: size * 0.3)
        }
        .frame(width: size, height: size)
    }
}

struct ProgressRing: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.13), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.75), tint], center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(360 * max(progress, 0.01))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.35), radius: 6)
                .animation(.smooth(duration: 0.9), value: progress)
        }
        .animation(.smooth(duration: 0.45), value: tint)
    }
}

/// A soft breathing dot that signals "watching, all good".
struct PulseDot: View {
    var color: Color
    var animate = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Driven by a clock rather than a repeating animation, so it can't leak into
        // surrounding transitions and it stops the moment `animate` turns off.
        TimelineView(.animation(paused: !animate || reduceMotion)) { context in
            let phase = animate && !reduceMotion
                ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8 : 1
            let eased = 1 - pow(1 - phase, 3)
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .background(Circle().fill(color.opacity(0.4)).scaleEffect(1 + 1.5 * eased).opacity(1 - eased))
        }
    }
}

/// Circular control like the system's media buttons, tinted.
struct RoundButton: View {
    var symbol: String
    var tint: Color
    var prominent = false
    var size: CGFloat = 44
    var help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(prominent ? Color.white : tint)
                .contentTransition(.symbolEffect(.replace.downUp))
                .frame(width: size, height: size)
                .background(Circle().fill(prominent ? tint : tint.opacity(0.14)))
                .contentShape(Circle())
                .animation(.smooth(duration: 0.3), value: symbol)
                .animation(.smooth(duration: 0.3), value: prominent)
        }
        .buttonStyle(PressableStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Timeline of recent checks: each sliver is one look at the screen.
struct ActivityStrip: View {
    var checks: [CheckRecord]
    var slots = 36

    var body: some View {
        let recent = Array(checks.suffix(slots))
        HStack(spacing: 2.5) {
            ForEach(0..<slots, id: \.self) { i in
                let offset = i - (slots - recent.count)
                Capsule()
                    .fill(offset >= 0 ? color(recent[offset].status) : Color.primary.opacity(0.07))
                    .frame(width: 4, height: 16)
                    .help(offset >= 0 ? "\(recent[offset].appName) · \(recent[offset].activity)" : "")
            }
        }
        .animation(.smooth, value: checks.count)
    }

    private func color(_ s: CheckRecord.Status) -> Color {
        switch s {
        case .onGoal: Theme.focus
        case .offGoal: Theme.drift
        case .away: Color.primary.opacity(0.18)
        }
    }
}

struct AppIconView: View {
    var bundleID: String
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, p) in arrange(bounds.width, subviews).points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += row + spacing; row = 0 }
            points.append(CGPoint(x: x, y: y))
            x += s.width + spacing
            row = max(row, s.height)
            maxX = max(maxX, x - spacing)
        }
        return (points, CGSize(width: maxX, height: y + row))
    }
}

/// Editable token list for "also relevant" research and side tasks.
struct ChipField: View {
    @Binding var items: [String]
    var placeholder: String
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 4) {
                    Text(item).lineLimit(1)
                    Button {
                        withAnimation(.snappy) { items.removeAll { $0 == item } }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                            .accessibilityLabel("Remove \(item)")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .font(.callout)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            TextField(items.isEmpty ? placeholder : "Add…", text: $draft)
                .textFieldStyle(.plain)
                .font(.callout)
                .frame(minWidth: 90)
                .fixedSize()
                .padding(.vertical, 5)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                .onDisappear(perform: commit)
        }
    }

    private func commit() {
        let parts = draft.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        withAnimation(.snappy) {
            for p in parts where !items.contains(p) { items.append(p) }
        }
        draft = ""
    }
}

struct SectionLabel: View {
    var text: String
    var body: some View {
        Text(text).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
    }
}

/// Fades a piece in with a small rise, after `delay`; used to sequence a screen's entrance.
private struct Reveal: ViewModifier {
    var shown: Bool
    var delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .animation(.smooth(duration: 0.45).delay(reduceMotion ? 0 : delay), value: shown)
    }
}

extension View {
    func reveal(_ shown: Bool, delay: Double) -> some View { modifier(Reveal(shown: shown, delay: delay)) }
}

enum Motion {
    /// System Settings → Accessibility → Display → Reduce motion.
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

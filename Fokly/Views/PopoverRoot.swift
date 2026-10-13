import SwiftUI

/// Everything that lives in the menu bar popover.
struct PopoverRoot: View {
    @Environment(FocusController.self) private var focus
    @AppStorage(Prefs.onboarded) private var onboarded = false
    @AppStorage(Prefs.accentHex) private var accent = ""
    var toggleMiniTimer: () -> Void
    var openSettings: () -> Void
    var openInsights: () -> Void
    /// Reports the content's height so the popover can be sized without fighting SwiftUI's animation.
    var onHeight: (CGFloat) -> Void = { _ in }

    var body: some View {
        ZStack {
            switch focus.phase {
            case .idle:
                if onboarded {
                    StartView(openSettings: openSettings, openInsights: openInsights).transition(.blurReplace)
                } else {
                    OnboardingView().transition(.blurReplace)
                }
            case .focusing, .paused:
                if focus.editingGoal {
                    StartView(openSettings: openSettings, openInsights: openInsights).transition(.blurReplace)
                } else {
                    ActiveView(toggleMiniTimer: toggleMiniTimer, openSettings: openSettings)
                        .transition(.blurReplace)
                }
            case .onBreak:
                BreakView().transition(.blurReplace)
            case .finished:
                SummaryView().transition(.blurReplace)
            }
        }
        .frame(width: Theme.popoverWidth)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: onHeight)
        // The popover window snaps to its new height while SwiftUI animates the content's;
        // pin to the top so the header stays put and only what's below moves.
        .frame(maxHeight: .infinity, alignment: .top)
        .id(accent)  // repaint everything when the accent color changes
        .animation(.smooth(duration: 0.35), value: focus.phase)
        .animation(.smooth(duration: 0.3), value: focus.editingGoal)
        .animation(.smooth(duration: 0.3), value: onboarded)
    }
}

struct BreakView: View {
    @Environment(FocusController.self) private var focus
    @State private var appeared = Motion.reduced

    private let tips = [
        "Look at something far away for twenty seconds.",
        "Stand up, stretch, roll your shoulders.",
        "Refill your water. Take a slow breath.",
        "Step away from the screen. It'll wait.",
    ]

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Label("Break", systemImage: "cup.and.heat.waves.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.rest)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.rest.opacity(0.13)))
                Spacer()
            }

            ZStack {
                ProgressRing(progress: appeared ? focus.ring : 0, tint: Theme.rest, lineWidth: 11)
                VStack(spacing: 2) {
                    Text(Clock.string(focus.breakRemaining))
                        .font(.clock(44))
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: Int(focus.breakRemaining))
                    Text("until focus").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 184, height: 184)

            Text(tips[abs(focus.goal.hashValue) % tips.count])
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)

            HStack(spacing: 10) {
                Button("+5 min") { focus.extendBreak() }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                Button {
                    focus.endBreak()
                } label: {
                    Text("Back to Focus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.focus)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .onAppear { appeared = true }  // the ring sweeps in
    }
}

struct SummaryView: View {
    @Environment(FocusController.self) private var focus
    @State private var drawn = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.focus.opacity(0.1))
                Circle().stroke(Theme.focus.opacity(0.15), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: drawn ? 1 : 0)
                    .stroke(Theme.focus, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.focus)
                    .scaleEffect(drawn ? 1 : 0.3)
                    .opacity(drawn ? 1 : 0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.55).delay(0.6), value: drawn)
            }
            .frame(width: 72, height: 72)
            .padding(.top, 6)
            .onAppear {
                withAnimation(Motion.reduced ? nil : .easeOut(duration: 0.8)) { drawn = true }
            }

            VStack(spacing: 4) {
                Text("Session complete").font(.system(size: 20, weight: .semibold, design: .rounded))
                Text(focus.goal).font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).lineLimit(2)
            }
            .reveal(drawn, delay: 0.3)

            if let s = focus.summary {
                HStack(spacing: 0) {
                    stat(Clock.minutes(s.focused), "focused")
                    Divider().frame(height: 32)
                    stat(s.onGoalRatio.map { "\(Int($0 * 100))%" } ?? "—", "on goal")
                    Divider().frame(height: 32)
                    stat("\(s.nudges)", s.nudges == 1 ? "reminder" : "reminders")
                }
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.045)))
                .reveal(drawn, delay: 0.42)
            }

            if !focus.checks.isEmpty {
                ActivityStrip(checks: focus.checks, slots: 48)
                    .reveal(drawn, delay: 0.52)
            }

            HStack(spacing: 10) {
                Button {
                    focus.closeSummary()
                } label: { Text("Done").frame(maxWidth: .infinity) }
                    .buttonStyle(.glass).controlSize(.large)
                Button {
                    focus.closeSummary(startAnother: true)
                } label: { Text("Another Round").frame(maxWidth: .infinity) }
                    .buttonStyle(.glassProminent).tint(Theme.focus).controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .reveal(drawn, delay: 0.6)
        }
        .padding(20)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.clock(19))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// First run: explain the promise, get screen access, fetch the model.
struct OnboardingView: View {
    @Environment(FocusController.self) private var focus
    @AppStorage(Prefs.onboarded) private var onboarded = false
    @State private var screenGranted = ScreenAccess.granted
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                FoklyMark(size: 34)
                Text("Never be distracted again.")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Tell Fokly your goal. It checks your screen now and then and reminds you when you get distracted.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                step(
                    icon: "rectangle.dashed.badge.record", title: "Screen access",
                    detail: "Read in memory, never saved.",
                    done: screenGranted,
                    action: screenGranted ? nil : ("Allow", { ScreenAccess.request() }))
                Divider().padding(.leading, 44)
                step(
                    icon: "cpu", title: focus.model.modelName,
                    detail: modelDetail,
                    done: focus.model.isReady || (focus.model.state == .idle && focus.model.isDownloaded),
                    action: modelAction)
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.045)))

            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill").foregroundStyle(Theme.rest)
                Text("Nothing leaves your Mac. No accounts, no cloud.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button {
                onboarded = true
            } label: {
                Text("Get Started").font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 30)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.focus)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(22)
        .onReceive(poll) { _ in screenGranted = ScreenAccess.granted }
    }

    private var modelDetail: String {
        switch focus.model.state {
        case .downloading(let p): "Downloading… \(Int(p * 100))%"
        case .loading: "Loading into memory…"
        case .ready: "Ready, running locally."
        case .failed(let m): m
        case .idle: focus.model.isDownloaded ? "Downloaded. Loads when you start." : "One-time 3 GB download. You can start now."
        }
    }

    private var modelAction: (String, () -> Void)? {
        switch focus.model.state {
        case .idle where focus.model.isDownloaded: nil
        case .idle, .failed: ("Download", { focus.model.prepare() })
        default: nil
        }
    }

    private func step(icon: String, title: String, detail: String, done: Bool,
                      action: (String, () -> Void)?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : icon)
                .font(.system(size: 18))
                .foregroundStyle(done ? Theme.rest : .secondary)
                .frame(width: 22)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if let action {
                Button(action.0, action: action.1).buttonStyle(.glass).controlSize(.small)
            } else if case .downloading = focus.model.state, !done, icon == "cpu" {
                ProgressView().controlSize(.small)
            }
        }
        .padding(12)
    }
}

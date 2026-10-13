import SwiftUI

/// The session in progress: clock, goal, what Fokly sees, controls.
struct ActiveView: View {
    @Environment(FocusController.self) private var focus
    var toggleMiniTimer: () -> Void
    var openSettings: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                AttentionChip()
                Spacer()
                Button(action: toggleMiniTimer) { Image(systemName: "pip").accessibilityLabel("Floating timer") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .help("Floating timer")
                Button(action: openSettings) { Image(systemName: "gearshape").accessibilityLabel("Settings") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .keyboardShortcut(",", modifiers: .command)
                    .help("Settings")
            }

            ZStack {
                ProgressRing(progress: focus.ring, tint: tint, lineWidth: 11)
                VStack(spacing: 2) {
                    Text(Clock.string(focus.clock))
                        .font(.clock(44))
                        .foregroundStyle(focus.phase == .paused ? .secondary : .primary)
                        .contentTransition(.numericText(countsDown: focus.remaining != nil))
                        .animation(.snappy, value: Int(focus.clock))
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 184, height: 184)
            .padding(.vertical, 2)

            VStack(spacing: 8) {
                Button(action: editGoal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(focus.goal)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                        Image(systemName: "pencil").font(.caption).foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .help("Change goal")

                // What counts as on track, editable mid-session: it opens the same editor as the pencil.
                Button(action: editGoal) {
                    VStack(spacing: 4) {
                        if !focus.alsoRelevant.isEmpty || !focus.approved.isEmpty {
                            Label((focus.alsoRelevant + focus.approved).joined(separator: " · "), systemImage: "checkmark.circle")
                                .lineLimit(2)
                        }
                        if !focus.notRelevant.isEmpty {
                            Label(focus.notRelevant.joined(separator: " · "), systemImage: "nosign")
                                .lineLimit(2)
                        }
                        if focus.alsoRelevant.isEmpty && focus.approved.isEmpty && focus.notRelevant.isEmpty {
                            Label("What counts as on track", systemImage: "plus.circle")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Edit what counts as on track")
            }
            .padding(.horizontal, 8)

            NowCard()

            HStack(spacing: 16) {
                RoundButton(symbol: focus.phase == .paused ? "play.fill" : "pause.fill",
                            tint: Theme.focus, prominent: focus.phase == .paused,
                            help: focus.phase == .paused ? "Resume" : "Pause") {
                    focus.togglePause()
                }
                RoundButton(symbol: "cup.and.heat.waves.fill", tint: Theme.rest,
                            help: "Take a \(Prefs.d.integer(forKey: Prefs.breakMinutes))-minute break") {
                    focus.startBreak()
                }
                RoundButton(symbol: "stop.fill", tint: .secondary, help: "Finish session") {
                    focus.finish()
                }
            }
        }
        .padding(20)
        // The first activity strip and card changes push the controls down; let them glide.
        .animation(.smooth(duration: 0.35), value: focus.checks.isEmpty)
    }

    private func editGoal() {
        withAnimation(.snappy) { focus.editingGoal = true }
    }

    private var tint: Color {
        if focus.phase == .paused { return .secondary }
        return focus.attention == .drifting ? Theme.drift : Theme.focus
    }

    private var subtitle: String {
        if focus.phase == .paused { return "Paused" }
        if let m = focus.plannedMinutes { return "of \(m) min" }
        return "elapsed"
    }
}

struct AttentionChip: View {
    @Environment(FocusController.self) private var focus

    var body: some View {
        HStack(spacing: 7) {
            PulseDot(color: color, animate: focus.phase == .focusing && focus.attention != .drifting)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .contentTransition(.interpolate)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.12)))
        .animation(.smooth(duration: 0.35), value: label)
    }

    private var label: String {
        if focus.phase == .paused { return "Paused" }
        switch focus.attention {
        case .warmingUp: return "Warming up"
        case .onTrack: return "On track"
        case .drifting: return "Distracted"
        case .away: return "Away"
        case .unknown: return "Focusing"
        }
    }

    private var color: Color {
        if focus.phase == .paused { return .secondary }
        switch focus.attention {
        case .drifting: return Theme.drift
        case .away, .warmingUp: return .secondary
        default: return Theme.focus
        }
    }
}

/// What Fokly currently sees, or why it isn't looking yet.
struct NowCard: View {
    @Environment(FocusController.self) private var focus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Overlap old and new while they crossfade instead of stacking them.
            ZStack(alignment: .leading) {
                HStack(spacing: 10) {
                    content
                    Spacer(minLength: 0)
                }
                .id(contentKey)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .leading)))
            }
            if !focus.checks.isEmpty {
                ActivityStrip(checks: focus.checks, slots: 44)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.045)))
        .animation(.smooth(duration: 0.35), value: contentKey)
        .animation(.smooth(duration: 0.35), value: focus.checks.isEmpty)
    }

    @ViewBuilder private var content: some View {
        if !ScreenAccess.granted {
            Image(systemName: "eye.slash").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Screen access needed").font(.callout.weight(.medium))
                Button("Open Privacy Settings") { ScreenAccess.request() }
                    .buttonStyle(.link).font(.caption)
            }
        } else {
            switch focus.model.state {
            case .downloading(let p):
                ProgressView(value: p).progressViewStyle(.circular).controlSize(.small).tint(Theme.focus)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Downloading \(focus.model.modelName)").font(.callout.weight(.medium))
                    Text("\(Int(p * 100))% · ~3 GB, first time only").font(.caption).foregroundStyle(.secondary)
                }
            case .loading, .idle:
                ProgressView().controlSize(.small)
                Text("Waking the on-device model…").font(.callout).foregroundStyle(.secondary)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.drift)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Model unavailable").font(.callout.weight(.medium))
                    Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Button("Retry") { focus.model.prepare() }.buttonStyle(.link).font(.caption)
                }
            case .ready:
                if let c = focus.current {
                    AppIconView(bundleID: c.bundleID, size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.activity.isEmpty ? c.app : c.activity)
                            .font(.callout.weight(.medium)).lineLimit(1)
                        TimelineView(.periodic(from: .now, by: 5)) { _ in
                            Text("\(c.app) · \(lastSeen)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if focus.isChecking { ProgressView().controlSize(.mini) }
                } else {
                    Image(systemName: "sparkle").foregroundStyle(Theme.focus)
                    Text("Watching quietly. You'll only hear from me if you get distracted.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Changes when what the card says changes (not on every progress tick or clock second).
    private var contentKey: String {
        if !ScreenAccess.granted { return "access" }
        switch focus.model.state {
        case .downloading: return "downloading"
        case .loading, .idle: return "loading"
        case .failed: return "failed"
        case .ready: return focus.current.map { "\($0.bundleID)|\($0.activity)" } ?? "watching"
        }
    }

    private var lastSeen: String {
        guard let d = focus.lastCheck else { return "just now" }
        let s = Int(Date().timeIntervalSince(d))
        return s < 10 ? "just now" : s < 60 ? "\(s)s ago" : "\(s / 60)m ago"
    }
}

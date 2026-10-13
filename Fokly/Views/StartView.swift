import SwiftUI

/// Idle state: set the goal, how long, and (optionally) what does and doesn't count.
struct StartView: View {
    @Environment(FocusController.self) private var focus
    @FocusState private var field: Field?
    @AppStorage(Prefs.customMinutes) private var customMinutes = 45
    @State private var contextOpen = false
    var openSettings: () -> Void
    var openInsights: () -> Void

    private enum Field { case goal, custom }
    private let presets = [25, 50, 90]

    var body: some View {
        @Bindable var focus = focus
        VStack(alignment: .leading, spacing: 18) {
            header

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: focus.editingGoal ? "Update your goal" : "What will you focus on?")
                goalField
                if showRecents {
                    recent.transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }

            contextSection

            if !focus.editingGoal {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Duration")
                    durationPicker
                }
            }

            Button(action: focus.start) {
                HStack {
                    Text(focus.editingGoal ? "Update Goal" : "Start Focus")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Image(systemName: "return").font(.system(size: 12, weight: .semibold)).opacity(0.7)
                }
                .padding(.horizontal, 6)
                .frame(height: 30)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.focus)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(focus.goal.trimmingCharacters(in: .whitespaces).isEmpty)

            if !focus.editingGoal { footer }
        }
        .padding(20)
        // Scoped to the whole screen so what sits below the recents glides up with them.
        .animation(.smooth(duration: 0.28), value: showRecents)
        .onReceive(NotificationCenter.default.publisher(for: .foklyToggleContext)) { _ in
            withAnimation(.smooth(duration: 0.3)) { contextOpen.toggle() }
        }
        .onAppear {
            field = .goal
            contextOpen = focus.editingGoal || !focus.notRelevant.isEmpty
        }
    }

    private var showRecents: Bool {
        focus.goal.isEmpty && !focus.history.recentGoals.isEmpty && !focus.editingGoal
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 8) {
            FoklyMark(size: 16)
            Text("Fokly").font(.system(size: 14, weight: .semibold, design: .rounded))
            Spacer()
            if focus.editingGoal {
                Button("Cancel") { focus.editingGoal = false }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 12) {
                    if let version = Updater.shared.available {
                        Button { Updater.shared.checkForUpdates() } label: {
                            Label("Update", systemImage: "arrow.down.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Theme.focus.opacity(0.14)))
                                .foregroundStyle(Theme.focus)
                        }
                        .help("Fokly \(version) is ready to install")
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                    Button(action: openInsights) {
                        Image(systemName: "chart.bar.xaxis").font(.system(size: 13, weight: .medium))
                            .accessibilityLabel("Insights and history")
                    }
                    .help("Insights & history  ⌘Y")
                    .keyboardShortcut("y", modifiers: .command)
                    Button(action: openSettings) {
                        Image(systemName: "gearshape").font(.system(size: 13, weight: .medium))
                            .accessibilityLabel("Settings")
                    }
                    .help("Settings  ⌘,")
                    .keyboardShortcut(",", modifiers: .command)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// A real, obviously typeable box, so it's clear where to start.
    private var goalField: some View {
        @Bindable var focus = focus
        let active = field == .goal
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "scope")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? Theme.focus : .secondary)
            TextField("e.g. Finish the Q3 report draft", text: $focus.goal, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .lineLimit(1...3)
                .focused($field, equals: .goal)
                .onSubmit { focus.start() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(active ? 0.06 : 0.045)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(active ? Theme.focus.opacity(0.7) : Color.primary.opacity(0.1), lineWidth: active ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { field = .goal }
        .animation(.easeOut(duration: 0.15), value: active)
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(focus.history.recentGoals, id: \.self) { g in
                Button {
                    focus.goal = g
                } label: {
                    Label(g, systemImage: "arrow.counterclockwise")
                        .lineLimit(1)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var durationPicker: some View {
        HStack(spacing: 6) {
            ForEach(presets, id: \.self) { m in
                chip(selected: focus.plannedMinutes == m && field != .custom, help: "\(m) minutes") {
                    focus.plannedMinutes = m
                    if field == .custom { field = nil }
                } label: {
                    Text("\(m)").font(.system(size: 14, weight: .semibold, design: .rounded))
                        + Text(" min").font(.system(size: 11, weight: .medium, design: .rounded))
                }
            }
            customChip
            chip(selected: focus.plannedMinutes == nil, help: "Open-ended — count up") {
                focus.plannedMinutes = nil
                if field == .custom { field = nil }
            } label: {
                Text("∞").font(.system(size: 15, weight: .semibold, design: .rounded))
            }
        }
    }

    /// Type any length; it's remembered for next time.
    private var customChip: some View {
        let selected = field == .custom || (focus.plannedMinutes.map { !presets.contains($0) } ?? false)
        return HStack(spacing: 1) {
            TextField("45", value: $customMinutes, format: .number)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .frame(width: 26)
                .focused($field, equals: .custom)
                .onSubmit { field = .goal }
            Text("min").font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .foregroundStyle(selected ? Theme.focus : .primary.opacity(0.75))
        .frame(maxWidth: .infinity, minHeight: 32)
        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Theme.focus.opacity(0.14) : Color.primary.opacity(0.045)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Theme.focus.opacity(0.5) : Color.primary.opacity(0.1),
                              style: StrokeStyle(lineWidth: 1, dash: selected ? [] : [3, 2]))
        )
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { field = .custom } }
        .onChange(of: field) { _, f in if f == .custom { withAnimation(.snappy) { applyCustom() } } }
        .onChange(of: customMinutes) { _, _ in if field == .custom { applyCustom() } }
        .help("Custom length — type any number of minutes")
    }

    private func applyCustom() {
        customMinutes = min(600, max(1, customMinutes))
        focus.plannedMinutes = customMinutes
    }

    private func chip<L: View>(selected: Bool, help: String, action: @escaping () -> Void,
                               @ViewBuilder label: () -> L) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            label().frame(maxWidth: .infinity, minHeight: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Theme.focus : .primary.opacity(0.75))
        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Theme.focus.opacity(0.14) : Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Theme.focus.opacity(0.5) : .clear, lineWidth: 1))
        .help(help)
    }

    /// Optional fine-tuning, folded away by default.
    private var contextSection: some View {
        @Bindable var focus = focus
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.smooth(duration: 0.3)) { contextOpen.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(contextOpen ? 90 : 0))
                    Text("What counts as on track").font(.subheadline.weight(.medium))
                    Text("optional").font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                    if !contextOpen, let summary = contextSummary {
                        Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if contextOpen {
                VStack(alignment: .leading, spacing: 12) {
                    listField(title: "Also counts", icon: "checkmark.circle", tint: Theme.focus,
                              items: $focus.alsoRelevant, placeholder: "Research, docs, Slack #team…")
                    listField(title: "Doesn't count", icon: "nosign", tint: Theme.drift,
                              items: $focus.notRelevant, placeholder: "YouTube, X, news, email…")
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
    }

    private var contextSummary: String? {
        var parts: [String] = []
        if !focus.alsoRelevant.isEmpty { parts.append("\(focus.alsoRelevant.count) counts") }
        if !focus.notRelevant.isEmpty { parts.append("\(focus.notRelevant.count) doesn't") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func listField(title: String, icon: String, tint: Color, items: Binding<[String]>,
                           placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            ChipField(items: items, placeholder: placeholder)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.045)))
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if focus.history.focusedToday > 0 {
                Image(systemName: "sun.max").foregroundStyle(Theme.focus)
                Text("\(Clock.minutes(focus.history.focusedToday)) focused today")
            } else {
                Image(systemName: "lock.shield").foregroundStyle(.secondary)
                Text("Private. Runs entirely on this Mac.")
            }
            Spacer()
            ModelBadge()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct ModelBadge: View {
    @Environment(FocusController.self) private var focus

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(focus.model.modelName)
        }
        .help("Local model · \(Prefs.d.string(forKey: Prefs.modelID) ?? "")")
    }

    private var color: Color {
        switch focus.model.state {
        case .ready: .green
        case .failed: .red
        case .idle: Color.secondary.opacity(0.5)
        default: Theme.drift
        }
    }
}

extension Notification.Name {
    /// Debug hook (`--toggle-test`) for recording the disclosure animation.
    static let foklyToggleContext = Notification.Name("FoklyToggleContext")
}

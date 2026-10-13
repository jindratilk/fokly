import ServiceManagement
import SwiftUI

/// System Settings–style window: a sidebar of panes, each a grouped form that scrolls.
struct SettingsView: View {
    @State private var pane: Pane? = .general
    /// The hosting window shows the selected pane's name, like System Settings.
    var setTitle: (String) -> Void = { _ in }

    enum Pane: String, CaseIterable, Identifiable {
        case general, awareness, appearance, model, about
        var id: Self { self }

        var title: String {
            switch self {
            case .general: "General"
            case .awareness: "Awareness"
            case .appearance: "Appearance"
            case .model: "Local Model"
            case .about: "About"
            }
        }

        var icon: String {
            switch self {
            case .general: "gearshape.fill"
            case .awareness: "eye.fill"
            case .appearance: "paintpalette.fill"
            case .model: "cpu.fill"
            case .about: "info.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .general: .gray
            case .awareness: .blue
            case .appearance: .pink
            case .model: .indigo
            case .about: .secondary
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { p in
                Label {
                    Text(p.title)
                } icon: {
                    Image(systemName: p.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6).fill(p.tint.gradient))
                }
                .padding(.vertical, 2)
                .tag(p)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch pane ?? .general {
                case .general: GeneralPane()
                case .awareness: AwarenessPane()
                case .appearance: AppearancePane()
                case .model: ModelPane()
                case .about: AboutPane()
                }
            }
            .formStyle(.grouped)
            .navigationTitle((pane ?? .general).title)
        }
        .frame(minWidth: 700, minHeight: 480)
        .onChange(of: pane, initial: true) { _, p in setTitle((p ?? .general).title) }
        #if DEVTOOLS
        .onReceive(NotificationCenter.default.publisher(for: .init("DevSettingsPane"))) { note in
            if let raw = note.object as? String, let p = Pane(rawValue: raw) { pane = p }
        }
        #endif
    }
}

// MARK: - Panes

private struct GeneralPane: View {
    @AppStorage(Prefs.defaultMinutes) private var defaultMinutes = 50
    @AppStorage(Prefs.breakMinutes) private var breakMinutes = 5
    @AppStorage(Prefs.showMiniTimer) private var showMiniTimer = true
    @AppStorage(Prefs.playSounds) private var playSounds = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Sessions") {
                Picker("Default length", selection: $defaultMinutes) {
                    Text("25 minutes").tag(25)
                    Text("50 minutes").tag(50)
                    Text("90 minutes").tag(90)
                    Text("Open-ended").tag(0)
                }
                Picker("Break length", selection: $breakMinutes) {
                    ForEach([3, 5, 10, 15], id: \.self) { Text("\($0) minutes").tag($0) }
                }
            }

            Section("Behavior") {
                Toggle(isOn: $showMiniTimer) {
                    Text("Floating timer while focusing")
                    Text("A small always-on-top timer you can drag anywhere.")
                }
                Toggle("Sounds", isOn: $playSounds)
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
            }

            Section("Keyboard") {
                LabeledContent("Show Fokly") { KeyCaps(keys: ["⌃", "⌥", "Space"]) }
                LabeledContent("Insights & history") { KeyCaps(keys: ["⌘", "Y"]) }
            }
        }
    }
}

private struct AwarenessPane: View {
    @AppStorage(Prefs.checkInterval) private var checkInterval = 20.0
    @AppStorage(Prefs.driftMinutes) private var driftMinutes = 2.0
    @AppStorage(Prefs.useVision) private var useVision = true
    @State private var confirmDelete = false
    @AppStorage(Prefs.saveBattery) private var saveBattery = true

    var body: some View {
        Form {
            Section {
                Picker("Check screen every", selection: $checkInterval) {
                    Text("10 seconds").tag(10.0)
                    Text("20 seconds").tag(20.0)
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                }
                Picker("Remind me after being distracted for", selection: $driftMinutes) {
                    Text("30 seconds").tag(0.5)
                    Text("1 minute").tag(1.0)
                    Text("2 minutes").tag(2.0)
                    Text("3 minutes").tag(3.0)
                    Text("5 minutes").tag(5.0)
                }
            } footer: {
                Text("The menu bar turns amber as soon as you get distracted; the reminder waits until it's been going on this long.")
            }

            Section {
                Toggle(isOn: $useVision) {
                    Text("Show the model a screenshot")
                    Text("More accurate on visual screens. Text and window titles are always used.")
                }
                Toggle(isOn: $saveBattery) {
                    Text("Check less often in Low Power Mode")
                    Text("Halves how often Fokly checks your screen while Low Power Mode is on.")
                }
            } footer: {
                Label("Screenshots and screen text are read in memory and discarded. Nothing is sent anywhere.",
                      systemImage: "lock.shield")
            }

            Section {
                LabeledContent("Session history") {
                    Button("Delete All…", role: .destructive) { confirmDelete = true }
                }
            } footer: {
                Text("Kept on this Mac only: goals, times and short notes such as “Watching F1 highlights”. Never screenshots or screen text.")
            }
        }
        .confirmationDialog("Delete all session history?", isPresented: $confirmDelete) {
            Button("Delete All", role: .destructive) { FocusController.shared.history.deleteAll() }
        } message: {
            Text("Insights will start from zero. This can't be undone.")
        }
    }
}

private struct AppearancePane: View {
    @AppStorage(Prefs.accentHex) private var accentHex = ""

    private static let swatches = [
        Theme.defaultFocusNS.hexString, "#FF9F0A", "#30C48D", "#0FB5BA", "#0A84FF", "#5E5CE6", "#BF5AF2", "#FF375F",
    ]

    var body: some View {
        Form {
            Section {
                preview
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }

            Section("Accent color") {
                HStack(spacing: 10) {
                    ForEach(Self.swatches, id: \.self) { hex in
                        let color = Color(nsColor: NSColor(hex: hex)!)
                        let selected = currentHex == hex
                        Button {
                            withAnimation(.snappy) { accentHex = hex == Theme.defaultFocusNS.hexString ? "" : hex }
                        } label: {
                            Circle().fill(color.gradient).frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(.white.opacity(selected ? 0.95 : 0), lineWidth: 2))
                                .overlay(Circle().strokeBorder(color.opacity(selected ? 1 : 0), lineWidth: 1.5).padding(-3))
                                .scaleEffect(selected ? 1.08 : 1)
                        }
                        .buttonStyle(.plain)
                        .help(hex)
                    }
                    Spacer()
                    ColorPicker("Custom", selection: accentBinding, supportsOpacity: false)
                        .help("Pick any color")
                }
                if !accentHex.isEmpty {
                    Button("Reset to Default") { withAnimation(.snappy) { accentHex = "" } }
                        .buttonStyle(.link)
                }
            }
        }
    }

    /// Live sample of the menu bar pill and the session ring.
    private var preview: some View {
        let tint = Color(nsColor: NSColor(hex: currentHex) ?? Theme.defaultFocusNS)
        return HStack(spacing: 28) {
            ZStack {
                ProgressRing(progress: 0.62, tint: tint, lineWidth: 7)
                Text("18:42").font(.clock(17))
            }
            .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Circle().trim(from: 0, to: 0.62)
                        .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .background(Circle().stroke(tint.opacity(0.3), lineWidth: 2))
                        .frame(width: 11, height: 11)
                    Text("18:42").font(.clock(13)).foregroundStyle(tint)
                }
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(tint.opacity(0.17)))
                Text("Start Focus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(tint))
            }
        }
        .animation(.smooth, value: currentHex)
    }

    private var currentHex: String { accentHex.isEmpty ? Theme.defaultFocusNS.hexString : accentHex.uppercased() }

    private var accentBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: Theme.focusNS) },
            set: { accentHex = NSColor($0).hexString }
        )
    }
}

private struct ModelPane: View {
    @AppStorage(Prefs.modelID) private var modelID = Prefs.defaultModelID
    @Environment(FocusController.self) private var focus
    @State private var showCustom = false

    /// Measured on the 20-screen test set and 30 live checks (Apple silicon MacBook, Oct 2026).
    static let choices: [(id: String, name: String, detail: String)] = [
        ("mlx-community/Qwen3.5-4B-4bit", "Balanced", "Qwen3.5 4B · 3 GB download · about 3.4 GB in use · 2.0 s per check"),
        ("mlx-community/Qwen3.5-2B-4bit", "Light", "Qwen3.5 2B · 1.7 GB download · about 2 GB in use · 1.1 s per check"),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(Self.choices, id: \.id) { choice in
                    Button {
                        modelID = choice.id
                        showCustom = false
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: modelID == choice.id ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 15))
                                .foregroundStyle(modelID == choice.id ? Theme.focus : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(choice.name).font(.body.weight(.medium))
                                Text(choice.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(modelID == choice.id ? .isSelected : [])
                }
                DisclosureGroup("Custom model", isExpanded: $showCustom) {
                    TextField("Hugging Face ID", text: $modelID)
                        .font(.system(.body, design: .monospaced))
                    Text("Any MLX vision-language model, e.g. mlx-community/…-4bit.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Model")
            } footer: {
                Text("Changes apply to the next session. A new model downloads once, the first time it's used.")
            }

            Section {
                LabeledContent("Status", value: statusText)
                LabeledContent("Downloaded", value: focus.model.isDownloaded ? "Yes" : "Not yet")
            }
        }
        .onAppear { showCustom = !Self.choices.contains { $0.id == modelID } }
    }

    private var statusText: String {
        switch focus.model.state {
        case .idle: "Loads when a session starts"
        case .downloading(let p): "Downloading \(Int(p * 100))%"
        case .loading: "Loading"
        case .ready: "Running"
        case .failed(let m): m
        }
    }
}

private struct AboutPane: View {
    @Bindable private var updater = Updater.shared

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Fokly").font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                .foregroundStyle(.secondary)
            Text("A calm focus companion. Everything runs on this Mac:\nno accounts, no cloud, nothing saved.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            HStack(spacing: 10) {
                Button("Check for Updates…") { Updater.shared.checkForUpdates() }
                Button("Show Welcome Tour") { NotificationCenter.default.post(name: .showWelcomeTour, object: nil) }
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(.top, 8)
            Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks)
                .toggleStyle(.checkbox)
                .padding(.top, 6)
            Text("Once a day Fokly asks fokly.app for a new version. No profile or usage data is sent.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

private struct KeyCaps: View {
    var keys: [String]
    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
            }
        }
    }
}

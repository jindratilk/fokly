#if DEVTOOLS
import AppKit
import SwiftUI

/// Debug launch modes for development: walkthroughs, stress tests, benchmarks, screenshots.
/// Compiled only into test builds (SWIFT_ACTIVE_COMPILATION_CONDITIONS += DEVTOOLS), never into a release.
@MainActor
enum DevTools {
    /// Modes that replace the normal UI. Returns true when one took over.
    static func runBeforeUI(delegate: AppDelegate) -> Bool {
        if CommandLine.arguments.contains("--preview") {
            // Debug: show the start screen and Insights in plain windows, without a menu bar item.
            for (title, view) in [("Preview", AnyView(PopoverRoot(toggleMiniTimer: {}, openSettings: {}, openInsights: {}))),
                                  ("Insights", AnyView(InsightsView().frame(width: 760, height: 900)))] {
                let window = NSWindow(contentViewController: NSHostingController(rootView: view.environment(FocusController.shared)))
                window.title = title
                window.makeKeyAndOrderFront(nil)
            }
            let status = StatusItemController()
            delegate.status = status
            status.showSettings()
            return true
        }
        if let i = CommandLine.arguments.firstIndex(of: "--tabs"), i + 1 < CommandLine.arguments.count {
            // Debug: list the tabs Fokly can see in a running app (needs Accessibility access).
            let bundleID = CommandLine.arguments[i + 1]
            print("accessibility trusted: \(WindowReturn.isTrusted)")
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
                WindowReturn.wakeAccessibility(pid: app.processIdentifier)
                Thread.sleep(forTimeInterval: 1)
                for window in WindowReturn.windows(of: app.processIdentifier) {
                    print("window: \(WindowReturn.string(window, kAXTitleAttribute as String) ?? "")")
                    for tab in WindowReturn.tabs(in: window) { print("  tab: \(tab.title)") }
                    if CommandLine.arguments.contains("--tree") { WindowReturn.dump(window) }
                }
            }
            exit(0)
        }
        if CommandLine.arguments.contains("--bad-model") {
            // Debug: what does a model that can't load look like?
            Task {
                let judge = FocusJudge()
                let t = Date()
                do { try await judge.load(id: "mlx-community/This-Model-Does-Not-Exist-4bit") { _ in }; print("unexpectedly loaded") }
                catch { print(String(format: "failed after %.1f s: %@", Date().timeIntervalSince(t), error.localizedDescription)) }
                exit(0)
            }
            return true
        }
        if CommandLine.arguments.contains("--selftest") {
            Task { await SelfTest.run() }
            return true
        }
        return false
    }

    /// Modes that drive the normal UI. Returns true when one took over.
    static func run(status: StatusItemController) -> Bool {
        if let i = CommandLine.arguments.firstIndex(of: "--film-plate"), i + 4 < CommandLine.arguments.count {
            let a = CommandLine.arguments
            Film.runPlate(kind: a[i + 1], clip: a[i + 2], out: a[i + 3], seconds: Double(a[i + 4]) ?? 10)
        } else         if let i = CommandLine.arguments.firstIndex(of: "--film"), i + 1 < CommandLine.arguments.count {
            Film.run(wallpaper: CommandLine.arguments[i + 1],
                     clip: i + 2 < CommandLine.arguments.count ? CommandLine.arguments[i + 2] : nil)
        } else         if let i = CommandLine.arguments.firstIndex(of: "--stills"), i + 1 < CommandLine.arguments.count {
            let dir = CommandLine.arguments[i + 1]
            Task { await Stills.run(dir: dir) }
        } else         if CommandLine.arguments.contains("--guide") {
            // Debug: the permissions slide, then the Settings guide for Accessibility.
            status.showWelcome(atPermissions: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { PermissionGuide.shared.request(.accessibility, from: nil) }
        } else         if CommandLine.arguments.contains("--lifecycle") {
            Task { await lifecycle() }
        } else         if let i = CommandLine.arguments.firstIndex(of: "--bench-acc"), i + 1 < CommandLine.arguments.count {
            let id = CommandLine.arguments[i + 1]
            let path = i + 2 < CommandLine.arguments.count ? CommandLine.arguments[i + 2] : nil
            Task { await StressTest.benchAccuracy(id: id, reportPath: path) }
        } else         if let i = CommandLine.arguments.firstIndex(of: "--bench"), i + 1 < CommandLine.arguments.count {
            let id = CommandLine.arguments[i + 1]
            let path = i + 2 < CommandLine.arguments.count ? CommandLine.arguments[i + 2] : nil
            Task { await StressTest.bench(id: id, reportPath: path) }
        } else         if let i = CommandLine.arguments.firstIndex(of: "--shots"), i + 1 < CommandLine.arguments.count {
            let dir = CommandLine.arguments[i + 1]
            Task { await Shots.run(status: status, dir: dir) }
        } else         if let i = CommandLine.arguments.firstIndex(of: "--stress-popover") {
            let path = i + 1 < CommandLine.arguments.count ? CommandLine.arguments[i + 1] : nil
            Task { await StressTest.popoverPace(status: status, reportPath: path) }
        } else         if let i = CommandLine.arguments.firstIndex(of: "--stress") {
            let path = i + 1 < CommandLine.arguments.count ? CommandLine.arguments[i + 1] : nil
            Task { await StressTest.run(status: status, reportPath: path) }
        } else         if CommandLine.arguments.contains("--tour") {
            runTour(status)
        } else         if CommandLine.arguments.contains("--toggle-test") {
            // Debug: open the popover and fold "What counts" open/closed every 1.5 s.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { status.showPopover() }
            Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                NotificationCenter.default.post(name: .foklyToggleContext, object: nil)
            }
        } else         if CommandLine.arguments.contains("--demo") {
            // Debug: start a session and show a sample nudge, for design review.
            let focus = FocusController.shared
            focus.goal = "Write the Q3 sales report"
            focus.alsoRelevant = ["Sales spreadsheets", "Slack #sales"]
            focus.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                focus.presentNudge?(Nudge(
                    appName: "YouTube", bundleID: "com.google.Chrome", activity: "Watching F1 highlights",
                    reminder: "You've been watching F1 highlights for 3 minutes. The Q3 report is waiting for you.",
                    goal: focus.goal))
                status.showPopover()
            }
        } else if CommandLine.arguments.contains("--welcome") || CommandLine.arguments.contains("--welcome-auto") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { status.showWelcome() }
            if CommandLine.arguments.contains("--welcome-auto") {
                for i in 1...6 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 + Double(i) * 3) {
                        NotificationCenter.default.post(name: .tourAdvance, object: nil)
                    }
                }
            }
        } else {
            return false
        }
        return true
    }

    /// Debug: sleep/wake auto-pause and unloading the model during a long pause.
    private static func lifecycle() async {
        let f = FocusController.shared
        f.debugMute = true
        f.debugUseSampleHistory(0)
        func log(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
        f.goal = "Lifecycle test"
        f.start()
        var w = 0.0
        while !f.model.isReady, w < 20 { try? await Task.sleep(for: .milliseconds(250)); w += 0.25 }
        log("started: phase \(f.phase), model \(f.model.state), \(StressTest.mb()) MB")
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        try? await Task.sleep(for: .seconds(1))
        let elapsedAtSleep = f.focusElapsed
        try? await Task.sleep(for: .seconds(3))
        log("after sleep: phase \(f.phase), clock moved \(String(format: "%.1f", f.focusElapsed - elapsedAtSleep)) s while asleep")
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try? await Task.sleep(for: .seconds(1))
        log("after wake: phase \(f.phase)")
        f.togglePause()
        log("paused by user; waiting 85 s for the model to be released…")
        try? await Task.sleep(for: .seconds(85))
        log("after long pause: model \(f.model.state), \(StressTest.mb()) MB")
        f.togglePause()
        w = 0
        while !f.model.isReady, w < 20 { try? await Task.sleep(for: .milliseconds(100)); w += 0.1 }
        log(String(format: "resumed: model ready again after %.1f s, %d MB", w, StressTest.mb()))
        f.finish()
        exit(0)
    }

    /// Debug: a scripted walk through every animated state, for screen recordings.
    private static func runTour(_ status: StatusItemController) {
        let f = FocusController.shared
        f.debugNoChecks = true
        f.goal = ""
        let steps: [(Double, () -> Void)] = [
            (0.5, { status.showPopover() }),
            (2.0, { f.goal = "W" }),
            (3.5, { f.goal = "" }),
            (5.0, { NotificationCenter.default.post(name: .foklyToggleContext, object: nil) }),
            (6.5, { withAnimation(.snappy) { f.alsoRelevant.append("Figma") } }),
            (8.0, { withAnimation(.snappy) { f.alsoRelevant.removeAll { $0 == "Figma" } } }),
            (9.0, { NotificationCenter.default.post(name: .foklyToggleContext, object: nil) }),
            (10.5, { f.goal = "Write the Q3 report"; withAnimation(.snappy) { f.plannedMinutes = 25 } }),
            (12.0, { f.start() }),
            (12.6, { if !status.miniTimer.isVisible { status.miniTimer.show() } }),
            (14.0, { status.showPopover() }),
            (16.5, { f.debugSimulate(onGoal: true, app: "Xcode", bundleID: "com.apple.dt.Xcode", activity: "Editing FocusController.swift") }),
            (18.5, { f.debugSimulate(onGoal: false, app: "YouTube", bundleID: "com.google.Chrome", activity: "Watching F1 highlights") }),
            (20.0, { f.presentNudge?(Nudge(appName: "YouTube", bundleID: "com.google.Chrome", activity: "Watching F1 highlights",
                                           reminder: "You've been watching F1 highlights for a while. The Q3 report is waiting.", goal: f.goal)) }),
            (22.5, { f.markRelevant(); f.debugSimulate(onGoal: true, app: "Xcode", bundleID: "com.apple.dt.Xcode", activity: "Editing FocusController.swift") }),
            (24.5, { f.togglePause() }),
            (26.5, { f.togglePause() }),
            (28.5, { f.editingGoal = true }),
            (30.5, { f.editingGoal = false }),
            (32.5, { f.startBreak() }),
            (35.5, { f.endBreak() }),
            (38.0, { f.finish() }),
            (42.5, { f.closeSummary() }),
        ]
        for (t, step) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: step)
        }
    }
}
#endif

#if DEVTOOLS
import AppKit

/// `Fokly --selftest`: loads the model, judges two scenarios (and the live screen if allowed), prints timings.
enum SelfTest {
    static func run() async {
        let judge = FocusJudge()
        let ctx = GoalContext(goal: "Write the Q3 sales report in Google Docs", alsoRelevant: ["sales spreadsheets"], approved: [])
        do {
            var t = Date()
            try await judge.load(id: Prefs.defaultModelID) { _ in }
            print("load: \(String(format: "%.1f", Date().timeIntervalSince(t)))s")

            let cases: [(String, ScreenSnapshot)] = [
                ("on-goal", ScreenSnapshot(appName: "Google Chrome", bundleID: "com.google.Chrome",
                    windowTitle: "Q3 Sales Report - Google Docs",
                    text: "Q3 Sales Report\nRevenue grew 12% quarter over quarter\nEMEA region summary", image: nil,
                    idleSeconds: 2, screenLocked: false)),
                ("off-goal", ScreenSnapshot(appName: "Google Chrome", bundleID: "com.google.Chrome",
                    windowTitle: "Max Verstappen best overtakes 2026 - YouTube",
                    text: "YouTube\nMax Verstappen best overtakes 2026\n2.1M views\nSubscribe\nUp next", image: nil,
                    idleSeconds: 2, screenLocked: false)),
            ]
            for (name, snap) in cases {
                t = Date()
                let v = try await judge.judge(snap, context: ctx)
                print("\(name): \(v) [\(String(format: "%.1f", Date().timeIntervalSince(t)))s]")
            }
            if ScreenAccess.granted, let live = await ScreenObserver().capture(includeImage: true) {
                t = Date()
                let v = try await judge.judge(live, context: ctx)
                print("live (\(live.appName) — \(live.windowTitle)): \(v) [\(String(format: "%.1f", Date().timeIntervalSince(t)))s, vision]")
            } else {
                print("live: skipped (no screen access)")
            }
        } catch {
            print("FAILED: \(error)")
        }
        exit(0)
    }
}
#endif

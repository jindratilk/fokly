#if DEVTOOLS
import AppKit
import SwiftUI

/// `Fokly --shots <dir>`: walks the app through its key screens with sample data and
/// captures each window in dark and light appearance (for the website). Debug only.
@MainActor
enum Shots {
    static func run(status: StatusItemController, dir: String) async {
        let f = FocusController.shared
        f.debugNoChecks = true
        f.debugMute = true
        f.debugUseSampleHistory(140)
        let saved = (f.alsoRelevant, f.notRelevant)  // these persist; give the user's back afterwards
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        for (suffix, appearance) in [("dark", NSAppearance.Name.darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            func shot(_ name: String, _ window: NSWindow?) {
                guard let window else { print("no window for \(name)"); return }
                capture(["-o", "-l", "\(window.windowNumber)"], to: "\(dir)/\(name)-\(suffix).png")
            }

            // Start screen with context filled in.
            f.goal = "Write the Q3 sales report"
            f.alsoRelevant = ["Sales spreadsheets", "Slack #sales"]
            f.notRelevant = ["YouTube", "X", "News"]
            f.plannedMinutes = 50
            status.showPopover()
            try? await Task.sleep(for: .seconds(1.0))
            if status.popoverWindowForTest == nil { status.showPopover(); try? await Task.sleep(for: .seconds(1.0)) }
            try? await Task.sleep(for: .seconds(0.6))
            shot("start", status.popoverWindowForTest)

            // A session with some history in the strip.
            f.start()
            f.debugFastForward(18 * 60 + 36)
            try? await Task.sleep(for: .seconds(1))
            for i in 0..<26 {
                let off = [9, 10, 11, 18].contains(i)
                f.debugSimulate(onGoal: !off, app: off ? "YouTube" : "Google Chrome", bundleID: "com.google.Chrome",
                                activity: off ? "Watching F1 highlights" : "Drafting the EMEA section")
            }
            status.miniTimer.show()
            status.showPopover()
            try? await Task.sleep(for: .seconds(1.8))
            shot("active", status.popoverWindowForTest)
            shot("mini", status.miniTimer.window)
            if let pill = status.statusButtonFrameForTest {
                capture(["-o", "-R", "\(Int(pill.minX) - 6),\(Int(NSScreen.screens[0].frame.maxY - pill.maxY)),\(Int(pill.width) + 12),\(Int(pill.height))"],
                        to: "\(dir)/pill-\(suffix).png")
            }

            // Drift and the nudge.
            f.debugSimulate(onGoal: false, app: "YouTube", bundleID: "com.google.Chrome", activity: "Watching F1 highlights")
            f.presentNudge?(Nudge(appName: "YouTube", bundleID: "com.google.Chrome", activity: "Watching F1 highlights",
                                  reminder: "You've been watching F1 highlights for a few minutes. The EMEA section is waiting.",
                                  goal: f.goal))
            try? await Task.sleep(for: .seconds(1.4))
            shot("nudge", status.nudgeWindowForTest)
            if let pill = status.statusButtonFrameForTest {
                capture(["-o", "-R", "\(Int(pill.minX) - 6),\(Int(NSScreen.screens[0].frame.maxY - pill.maxY)),\(Int(pill.width) + 12),\(Int(pill.height))"],
                        to: "\(dir)/pill-drift-\(suffix).png")
            }
            f.markRelevant()

            // Break.
            f.startBreak()
            try? await Task.sleep(for: .seconds(1.8))
            shot("break", status.popoverWindowForTest)
            f.endBreak()

            // Summary.
            f.debugFastForward(29 * 60)
            f.finish()
            status.miniTimer.hide()
            try? await Task.sleep(for: .seconds(2.4))
            shot("summary", status.popoverWindowForTest)
            f.closeSummary()
            status.dismissPopoverForTest()
            try? await Task.sleep(for: .seconds(0.8))

            // Insights.
            status.showInsights()
            try? await Task.sleep(for: .seconds(2.5))
            shot("insights", status.insightsWindowForTest)
            status.insightsWindowForTest?.close()
            try? await Task.sleep(for: .seconds(0.8))
        }
        // Settings panes and the welcome tour.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        status.showSettings()
        for pane in ["general", "awareness", "appearance", "model"] {
            NotificationCenter.default.post(name: .init("DevSettingsPane"), object: pane)
            try? await Task.sleep(for: .seconds(1.0))
            if let w = NSApp.windows.first(where: { $0.isVisible && $0.title != "" && $0.frame.width > 600 && $0.frame.height < 700 }) {
                capture(["-o", "-l", "\(w.windowNumber)"], to: "\(dir)/settings-\(pane).png")
            }
        }
        NSApp.windows.first { $0.isVisible && $0.frame.width > 600 && $0.frame.height < 700 }?.close()

        f.alsoRelevant = saved.0
        f.notRelevant = saved.1
        print("shots done")
        exit(0)
    }

    private static func capture(_ args: [String], to path: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = args + [path]
        try? p.run()
        p.waitUntilExit()
    }
}
#endif

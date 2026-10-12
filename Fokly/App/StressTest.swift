#if DEVTOOLS
import AppKit
import SwiftUI

/// `Fokly --stress <report path>`: hammers the app and writes a report. Debug only.
@MainActor
enum StressTest {
    private static var lines: [String] = []
    private static var reportURL = URL(fileURLWithPath: "/tmp/fokly-stress.txt")

    static func run(status: StatusItemController, reportPath: String?) async {
        if let reportPath { reportURL = URL(fileURLWithPath: reportPath) }
        let f = FocusController.shared
        f.debugNoChecks = true
        f.debugMute = true
        f.debugUseSampleHistory(20)  // in memory: the user's real history is never touched
        log("Fokly stress test · \(Date().formatted())")
        log("baseline footprint: \(mb()) MB")

        await uiFuzz(f, status)
        await panels(status)
        await insights(f, status)
        await modelLifecycle(f)
        await model()
        await timerAccuracy(f)

        log("final footprint: \(mb()) MB")
        log("DONE")
        flush()
        exit(0)
    }

    /// `--stress-popover`: open and close the popover at a human pace and time each open.
    static func popoverPace(status: StatusItemController, reportPath: String?) async {
        if let reportPath { reportURL = URL(fileURLWithPath: reportPath) }
        FocusController.shared.debugMute = true
        log("## Popover at a normal pace: 12 opens, 1.2 s apart")
        var sync: [Double] = [], frame: [Double] = []
        for i in 0..<12 {
            if i == 6 { FocusController.shared.goal = "Write the Q3 report"; FocusController.shared.start(); FocusController.shared.debugNoChecks = true }
            let t0 = Date()
            status.showPopover()
            sync.append(Date().timeIntervalSince(t0))
            let t1 = Date()
            try? await Task.sleep(for: .milliseconds(16))
            frame.append(Date().timeIntervalSince(t1) - 0.016)
            try? await Task.sleep(for: .milliseconds(600))
            status.dismissPopoverForTest()
            try? await Task.sleep(for: .milliseconds(600))
        }
        log("showPopover() blocking: " + sync.map { "\(Int($0 * 1000))" }.joined(separator: " ") + " ms")
        log("extra delay of the next frame: " + frame.map { "\(Int($0 * 1000))" }.joined(separator: " ") + " ms")
        log("(opens 1–6 idle start screen, 7–12 during a session)")
        log("DONE")
        flush()
        exit(0)
    }

    // MARK: 1. Random UI actions

    private static func uiFuzz(_ f: FocusController, _ status: StatusItemController) async {
        log("\n## 1 · UI fuzz: 600 random actions every 40 ms, floating timer setting on")
        let savedMini = Prefs.d.bool(forKey: Prefs.showMiniTimer)
        Prefs.d.set(true, forKey: Prefs.showMiniTimer)
        defer { Prefs.d.set(savedMini, forKey: Prefs.showMiniTimer) }
        let before = mb()
        status.showPopover()
        var hitches: [(Double, String)] = []
        var violations: [String] = []
        var counts: [String: Int] = [:]
        let longGoal = String(repeating: "Finish the incredibly detailed quarterly report ", count: 10)
        for i in 0..<600 {
            let roll = Int.random(in: 0..<100)
            let name: String
            switch roll {
            case 0..<10: name = "start"; if f.phase == .idle { f.goal = Bool.random() ? "Write the Q3 report" : longGoal; f.start() }
            case 10..<20: name = "pause"; f.togglePause()
            case 20..<26: name = "break"; f.startBreak(minutes: 1)
            case 26..<31: name = "endBreak"; f.endBreak()
            case 31..<37: name = "finish"; f.finish()
            case 37..<42: name = "closeSummary"; if f.phase == .finished { f.closeSummary(startAnother: Bool.random()) }
            case 42..<48: name = "editGoal"; if f.isActive { f.editingGoal.toggle() }
            case 48..<56: name = "popover"; status.togglePopover()
            case 56..<62: name = "context"; NotificationCenter.default.post(name: .foklyToggleContext, object: nil)
            case 62..<70: name = "chip+"; withAnimation(.snappy) { f.alsoRelevant.append("Item \(i)") }
            case 70..<74: name = "chip-"; withAnimation(.snappy) { if !f.alsoRelevant.isEmpty { f.alsoRelevant.removeFirst() } }
            case 74..<80: name = "typing"; if f.phase == .idle { f.goal = Bool.random() ? "" : String(longGoal.prefix(Int.random(in: 1...400))) }
            case 80..<88: name = "check"; if f.phase == .focusing {
                f.debugSimulate(onGoal: Bool.random(), app: "App \(i % 7)", bundleID: "com.apple.Safari", activity: "Activity \(i % 11)") }
            case 88..<93: name = "nudge"; f.presentNudge?(Nudge(appName: "YouTube", bundleID: "com.google.Chrome",
                activity: "Watching", reminder: "Back to it?", goal: f.goal))
            case 93..<96: name = "relevant"; if f.isActive { f.markRelevant() }
            default: name = "duration"; withAnimation(.snappy) { f.plannedMinutes = [25, 50, 90, nil, 7].randomElement()! }
            }
            counts[name, default: 0] += 1

            let t0 = Date()
            try? await Task.sleep(for: .milliseconds(40))
            let lag = Date().timeIntervalSince(t0) - 0.04
            if lag > 0.1 { hitches.append((lag, name)) }

            if f.focusElapsed < -0.01 { violations.append("#\(i) focusElapsed < 0 after \(name)") }
            if f.phase == .onBreak, f.breakRemaining <= 0, f.progress.isNaN { violations.append("#\(i) bad break state") }
            if f.progress.isNaN || f.progress < -0.01 || f.progress > 1.01 { violations.append("#\(i) progress \(f.progress) after \(name)") }
        }
        f.finish(); f.closeSummary()
        f.alsoRelevant.removeAll { $0.hasPrefix("Item ") }
        status.dismissPopoverForTest()
        try? await Task.sleep(for: .seconds(2))
        log("actions: " + counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        let byAction = Dictionary(grouping: hitches, by: \.1).mapValues { $0.count }.sorted { $0.value > $1.value }
        log("main-thread hitches >100 ms: \(hitches.count)"
            + (hitches.isEmpty ? "" : " (worst \(Int((hitches.map(\.0).max() ?? 0) * 1000)) ms) · after: "
               + byAction.map { "\($0.key) \($0.value)" }.joined(separator: ", ")))
        log("invariant violations: \(violations.count)" + violations.prefix(5).map { "\n  - \($0)" }.joined())
        log("model state after fuzz: \(f.model.state) · footprint \(before) → \(mb()) MB")
        // Give any background load that outlived its session a moment, then look again.
        try? await Task.sleep(for: .seconds(8))
        log("footprint 8 s later (no session running): \(mb()) MB · model state \(f.model.state)")
        flush()
    }

    // MARK: 2. Panels

    private static func panels(_ status: StatusItemController) async {
        log("\n## 2 · Panels: nudge and floating timer shown/hidden 100× each at 30 ms")
        let before = mb()
        let f = FocusController.shared
        for _ in 0..<100 {
            f.presentNudge?(Nudge(appName: "X", bundleID: "com.apple.Safari", activity: "Scrolling", reminder: "Back to it?", goal: "Test"))
            try? await Task.sleep(for: .milliseconds(30))
            f.dismissNudge?()
        }
        for _ in 0..<100 {
            status.miniTimer.show()
            try? await Task.sleep(for: .milliseconds(30))
            status.miniTimer.hide()
        }
        try? await Task.sleep(for: .seconds(1))
        log("footprint \(before) → \(mb()) MB · Fokly windows still on screen: \(visibleWindowCount())")
        flush()
    }

    // MARK: 3. Big history

    private static func insights(_ f: FocusController, _ status: StatusItemController) async {
        log("\n## 3 · Insights with 5,000 sessions")
        let t0 = Date()
        f.debugUseSampleHistory(5000)
        let gen = Date().timeIntervalSince(t0)
        var t = Date()
        _ = f.history.daily(days: 365); _ = f.history.streak; _ = f.history.recentGoals; _ = f.history.focusedToday
        let stats = Date().timeIntervalSince(t)
        t = Date()
        status.showInsights()
        status.insightsWindowForTest?.contentView?.layoutSubtreeIfNeeded()
        status.insightsWindowForTest?.displayIfNeeded()
        let open = Date().timeIntervalSince(t)
        log(String(format: "generate %.0f ms · stats (365 days, streak, recents) %.1f ms · open + first layout of window %.0f ms",
                   gen * 1000, stats * 1000, open * 1000))
        try? await Task.sleep(for: .seconds(2))
        status.insightsWindowForTest?.close()
        f.debugUseSampleHistory(0)
        flush()
    }

    // MARK: 4. Model lifecycle races

    private static func modelLifecycle(_ f: FocusController) async {
        log("\n## 4 · Model lifecycle: start then finish while the model is still loading, 5×")
        for round in 1...5 {
            f.goal = "Race \(round)"
            f.start()
            try? await Task.sleep(for: .milliseconds(Int.random(in: 100...1200)))
            f.finish(); f.closeSummary()
        }
        try? await Task.sleep(for: .seconds(10))
        log("10 s after the last finish: model state \(f.model.state) · footprint \(mb()) MB (≈3,000 MB extra means weights leaked)")

        log("\n## 4b · Normal start: does the model ever reach .ready?")
        f.goal = "Readiness"
        f.start()
        var waited = 0.0
        while !f.model.isReady, waited < 20 { try? await Task.sleep(for: .milliseconds(250)); waited += 0.25 }
        try? await Task.sleep(for: .seconds(1))
        log("model state after \(String(format: "%.1f", waited)) s: \(f.model.state)")
        f.finish(); f.closeSummary()
        try? await Task.sleep(for: .seconds(3))
        flush()
    }

    // MARK: 5. Model quality and speed

    private struct Case { var goal: String; var also: [String] = []; var not: [String] = []
        var app: String; var title: String; var text: String; var expected: Bool }

    private static let cases: [Case] = [
        Case(goal: "Write the Q3 sales report", app: "Google Chrome", title: "Q3 Sales Report - Google Docs", text: "Q3 Sales Report\nRevenue grew 12% QoQ\nEMEA summary", expected: true),
        Case(goal: "Write the Q3 sales report", app: "Google Chrome", title: "Max Verstappen best overtakes - YouTube", text: "YouTube\nMax Verstappen best overtakes\n2.1M views", expected: false),
        Case(goal: "Write the Q3 sales report", also: ["sales spreadsheets"], app: "Microsoft Excel", title: "Q3_pipeline.xlsx", text: "Account\tStage\tAmount\nAcme\tClosed won\t42,000", expected: true),
        Case(goal: "Write the Q3 sales report", app: "Slack", title: "#sales - Acme", text: "Anna: do we have final Q3 numbers for the report?\nTom: uploading the pipeline export now", expected: true),
        Case(goal: "Write the Q3 sales report", app: "Google Chrome", title: "Instagram", text: "Instagram\nStories\nSuggested for you\nLiked by 2,341 others", expected: false),
        Case(goal: "Write the Q3 sales report", not: ["email"], app: "Mail", title: "Inbox – Re: lunch on Friday?", text: "Re: lunch on Friday?\nSure, 12:30 works", expected: false),
        Case(goal: "Fix the login bug in our iOS app", app: "Xcode", title: "LoginViewController.swift", text: "func signIn() async throws {\n  let token = try await auth.refresh()", expected: true),
        Case(goal: "Fix the login bug in our iOS app", app: "Safari", title: "URLSession returns 401 after token refresh - Stack Overflow", text: "Stack Overflow\nURLSession 401 Unauthorized after refresh token", expected: true),
        Case(goal: "Fix the login bug in our iOS app", app: "Safari", title: "Amazon.com: running shoes", text: "Amazon\nRunning shoes for men\nAdd to cart\n4.5 stars", expected: false),
        Case(goal: "Fix the login bug in our iOS app", app: "Safari", title: "Home / X", text: "For you  Following\nWhat is happening?!\n12K reposts", expected: false),
        Case(goal: "Fix the login bug in our iOS app", app: "Terminal", title: "zsh — git log", text: "commit 4f2a9c1\nAuthor: dev\nFix token refresh race in AuthService", expected: true),
        Case(goal: "Study for the Spanish B2 exam", app: "Anki", title: "Spanish B2 vocabulary", text: "desarrollar — to develop\nShow answer\nAgain Hard Good Easy", expected: true),
        Case(goal: "Study for the Spanish B2 exam", app: "Mail", title: "Inbox (34)", text: "Newsletter: 10 gadget deals\nYour order has shipped\nWeekly digest", expected: false),
        Case(goal: "Design the onboarding screens in Figma", app: "Figma", title: "Onboarding v3 – Figma", text: "Welcome screen\nContinue\nFrame 12\nAuto layout", expected: true),
        Case(goal: "Design the onboarding screens in Figma", app: "Safari", title: "Onboarding inspiration – Dribbble", text: "Dribbble\nOnboarding UI inspiration\nMobile app onboarding", expected: true),
        Case(goal: "Design the onboarding screens in Figma", app: "Arc", title: "r/formula1 – Reddit", text: "r/formula1\nRace thread: Monza GP\n2.4k comments", expected: false),
        Case(goal: "Plan the week", app: "Calendar", title: "Calendar – Week 42", text: "Mon 9:00 Standup\nTue 14:00 Design review\nThu Focus block", expected: true),
        Case(goal: "Plan the week", app: "Notion", title: "Weekly plan", text: "Weekly plan\nTop 3 priorities\n1. Ship onboarding", expected: true),
        Case(goal: "Write a blog post about Rust async", app: "Code", title: "async-rust.md — blog", text: "# Understanding async in Rust\nFutures are lazy", expected: true),
        Case(goal: "Write a blog post about Rust async", app: "Safari", title: "Hacker News", text: "Hacker News\n1. Show HN: a new database\n2. Apple announces", expected: false),
        // Harder ones: goals in Czech, "research" on unrelated topics, tech that isn't the task.
        Case(goal: "Kytary.cz a frontman agent projekt dokončit", also: ["Práce v codexu (chatgpt)"], app: "Zen", title: "Counter-Strike 2 – Counter-Strike Wiki", text: "Counter-Strike Wiki\nCounter-Strike 2\nMaps\nWeapons\nAK-47 damage per shot", expected: false),
        Case(goal: "Kytary.cz a frontman agent projekt dokončit", also: ["Práce v codexu (chatgpt)"], app: "TickTick", title: "frontman agent", text: "Frontman agent\n☐ dokončit onboarding agenta\n☐ napojit API", expected: true),
        Case(goal: "Kytary.cz a frontman agent projekt dokončit", also: ["Práce v codexu (chatgpt)"], app: "ChatGPT", title: "Codex – kytary-cz", text: "Codex\nkytary-cz repository\nReviewing platform status\nFix product feed import", expected: true),
        Case(goal: "Kytary.cz a frontman agent projekt dokončit", app: "Zen", title: "Kytary.cz – kytary, baskytary, bicí", text: "Kytary.cz\nElektrické kytary\nAkustické kytary\nKošík", expected: true),
        Case(goal: "Kytary.cz a frontman agent projekt dokončit", app: "Zen", title: "iDNES.cz – Zprávy", text: "iDNES.cz\nZprávy\nSport\nPočasí\nVolby 2026", expected: false),
        Case(goal: "Write the Q3 sales report", app: "Safari", title: "Roman Empire - Wikipedia", text: "Roman Empire\nFrom Wikipedia, the free encyclopedia\nThe Roman Empire was the post-Republican state", expected: false),
        Case(goal: "Fix the login bug in our iOS app", app: "Safari", title: "The best mechanical keyboards of 2026 - The Verge", text: "The Verge\nThe best mechanical keyboards\nReviews", expected: false),
        Case(goal: "Design the onboarding screens in Figma", app: "Messages", title: "Messages – Mom", text: "Mom: are you coming on Sunday?\nMe: yes!", expected: false),
        Case(goal: "Studovat na zkoušku z účetnictví", app: "Safari", title: "Rozvaha a výkaz zisku a ztráty – Účetnictví", text: "Rozvaha\nAktiva\nPasiva\nVýkaz zisku a ztráty", expected: true),
        Case(goal: "Studovat na zkoušku z účetnictví", app: "Safari", title: "Netflix", text: "Netflix\nContinue watching\nStranger Things", expected: false),
        Case(goal: "Write a blog post about Rust async", app: "Finder", title: "Downloads", text: "Downloads\nscreenshot.png\ninvoice.pdf", expected: true),
        Case(goal: "Plan the week", app: "Safari", title: "Counter-Strike 2 on Steam", text: "Steam\nCounter-Strike 2\nPlay Game\nRecent reviews: Very Positive", expected: false),
        // Held out: none of these echo the examples in the instructions.
        Case(goal: "Write the Q3 sales report", app: "Safari", title: "Booking.com – Hotels in Lisbon", text: "Booking.com\nLisbon: 1,204 properties found\nBreakfast included", expected: false),
        Case(goal: "Fix the login bug in our iOS app", app: "Discord", title: "#general – Gaming Crew", text: "anyone up for ranked tonight?\nlol that clutch", expected: false),
        Case(goal: "Plan the week", app: "Spotify", title: "Discover Weekly", text: "Discover Weekly\nYour weekly mixtape of fresh music", expected: false),
        Case(goal: "Kytary.cz a frontman agent projekt dokončit", app: "Visual Studio Code", title: "index.ts — frontman-agent", text: "export async function runAgent(task: Task) {\n  const plan = await planner.next(task)", expected: true),
        Case(goal: "Studovat na zkoušku z účetnictví", app: "Safari", title: "Účetnictví pro začátečníky: rozvaha - YouTube", text: "YouTube\nÚčetnictví pro začátečníky: rozvaha\nAktiva a pasiva vysvětleno", expected: true),
        Case(goal: "Design the onboarding screens in Figma", app: "Figma", title: "Figma Community – Onboarding UI kit", text: "Figma Community\nOnboarding UI kit\n24 screens\nDuplicate", expected: true),
    ]

    /// `--bench-acc <model id> <report>`: only the labeled screens, for tuning the instructions.
    static func benchAccuracy(id: String, reportPath: String?) async {
        if let reportPath { reportURL = URL(fileURLWithPath: reportPath) }
        log("Accuracy · \(id)")
        let judge = FocusJudge()
        do { try await judge.load(id: id) { _ in } } catch { log("LOAD FAILED: \(error)"); flush(); exit(1) }
        var correct = 0, falseOn = 0, falseOff = 0
        for (i, c) in cases.enumerated() {
            let snap = ScreenSnapshot(appName: c.app, bundleID: "", windowTitle: c.title, text: c.text, image: nil,
                                      idleSeconds: 1, screenLocked: false)
            do {
                let v = try await judge.judge(snap, context: GoalContext(goal: c.goal, alsoRelevant: c.also, notRelevant: c.not, approved: []))
                if v.relevant == c.expected { correct += 1 } else {
                    if v.relevant { falseOn += 1 } else { falseOff += 1 }
                    log("  ✗ #\(i + 1) \(c.title) → relevant \(v.relevant), expected \(c.expected) · \(v.activity)")
                }
            } catch { log("  ! #\(i + 1) \(error)") }
        }
        log("accuracy \(correct)/\(cases.count) · missed distractions \(falseOn) · false alarms \(falseOff)")
        flush()
        exit(0)
    }

    /// `--bench <model id> <report>`: just the model section, for comparing models.
    static func bench(id: String, reportPath: String?) async {
        if let reportPath { reportURL = URL(fileURLWithPath: reportPath) }
        log("Bench · \(id)")
        await model(id: id)
        log("peak footprint: \(peakMB()) MB")
        log("DONE")
        flush()
        exit(0)
    }

    private static func model(id: String = Prefs.defaultModelID) async {
        log("\n## 5 · Model: accuracy on 20 labeled screens, then 30 live screen checks")
        let judge = FocusJudge()
        var t = Date()
        do { try await judge.load(id: id) { _ in } } catch { log("LOAD FAILED: \(error)"); return }
        log(String(format: "load %.1f s · footprint %d MB", Date().timeIntervalSince(t), mb()))

        var correct = 0, failures = 0
        var latencies: [Double] = []
        for (i, c) in cases.enumerated() {
            let snap = ScreenSnapshot(appName: c.app, bundleID: "", windowTitle: c.title, text: c.text, image: nil,
                                      idleSeconds: 1, screenLocked: false)
            t = Date()
            do {
                let v = try await judge.judge(snap, context: GoalContext(goal: c.goal, alsoRelevant: c.also, notRelevant: c.not, approved: []))
                latencies.append(Date().timeIntervalSince(t))
                                let offGoal = !v.relevant
                if offGoal != c.expected { correct += 1 } else {
                    log("  ✗ #\(i + 1) \(c.title) → relevant \(v.relevant) (\(v.confidence)), expected \(c.expected)")
                }
            } catch { failures += 1; log("  ! #\(i + 1) \(error)") }
        }
        log("accuracy \(correct)/\(cases.count) · errors \(failures) · text-only latency \(summary(latencies))")
        flush()

        // Fokly ignores itself; hand the foreground back to whatever the user was in.
        NSApp.hide(nil)
        try? await Task.sleep(for: .seconds(1))
        let observer = ScreenObserver()
        var live: [Double] = [], capture: [Double] = []
        var mems: [Int] = []
        let ctx = GoalContext(goal: "Build the Fokly focus app", alsoRelevant: ["Claude", "Xcode"], approved: [])
        for i in 0..<30 {
            t = Date()
            guard let snap = await observer.capture(includeImage: true) else { log("  capture \(i) returned nil"); continue }
            capture.append(Date().timeIntervalSince(t))
            t = Date()
            do { _ = try await judge.judge(snap, context: ctx); live.append(Date().timeIntervalSince(t)) }
            catch { failures += 1; log("  ! live \(i) \(error)") }
            if i % 10 == 9 { mems.append(mb()) }
        }
        log("live screen capture + OCR \(summary(capture)) · vision judgement \(summary(live))")
        log("footprint after 10/20/30 live checks: \(mems.map(String.init).joined(separator: " / ")) MB")

        log("\n## 5b · 5 concurrent judgements, then unload in the middle of one")
        t = Date()
        await withTaskGroup(of: Bool.self) { group in
            for c in cases.prefix(5) {
                group.addTask {
                    let snap = ScreenSnapshot(appName: c.app, bundleID: "", windowTitle: c.title, text: c.text, image: nil, idleSeconds: 1, screenLocked: false)
                    return (try? await judge.judge(snap, context: GoalContext(goal: c.goal, alsoRelevant: [], approved: []))) != nil
                }
            }
            var ok = 0
            for await r in group where r { ok += 1 }
            log(String(format: "concurrent: %d/5 succeeded in %.1f s", ok, Date().timeIntervalSince(t)))
        }
        let inFlight = Task {
            try await judge.judge(ScreenSnapshot(appName: "Xcode", bundleID: "", windowTitle: "x.swift", text: "code", image: nil,
                                                 idleSeconds: 1, screenLocked: false), context: ctx)
        }
        try? await Task.sleep(for: .milliseconds(150))
        await judge.unload()
        let r = await inFlight.result
        log("unload during judgement: \(String(describing: r).prefix(80)) · no crash")
        try? await Task.sleep(for: .seconds(2))
        log("footprint after unload: \(mb()) MB")
        flush()
    }

    // MARK: 6. Timer

    private static func timerAccuracy(_ f: FocusController) async {
        log("\n## 6 · Timer: a real 1-minute session")
        f.goal = "Timer accuracy"
        f.plannedMinutes = 1
        let t0 = Date()
        f.start()
        while f.phase == .focusing, Date().timeIntervalSince(t0) < 75 { try? await Task.sleep(for: .milliseconds(100)) }
        let took = Date().timeIntervalSince(t0)
        log(String(format: "finished after %.2f s of wall time (expected 60) · phase %@", took, "\(f.phase)"))
        f.closeSummary()
        f.plannedMinutes = Prefs.d.integer(forKey: Prefs.defaultMinutes).nonZero
        flush()
    }

    // MARK: Helpers

    private static func summary(_ xs: [Double]) -> String {
        guard !xs.isEmpty else { return "n/a" }
        let s = xs.sorted()
        func p(_ q: Double) -> Double { s[min(s.count - 1, Int(Double(s.count - 1) * q))] }
        return String(format: "p50 %.2f s · p95 %.2f s · max %.2f s (n=%d)", p(0.5), p(0.95), s.last!, s.count)
    }

    static func peakMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Int(info.ledger_phys_footprint_peak / 1_048_576) : -1
    }

    static func mb() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }

    private static func visibleWindowCount() -> String {
        let w = NSApp.windows.filter { $0.isVisible && $0.alphaValue > 0.01 }
        return "\(w.count) [" + w.map { String(describing: type(of: $0)) }.joined(separator: ", ") + "]"
    }

    private static func log(_ s: String) { lines.append(s); print(s) }
    private static func flush() { try? lines.joined(separator: "\n").write(to: reportURL, atomically: true, encoding: .utf8) }
}
#endif

import AppKit
import Observation
import UserNotifications

/// A reminder ready to be shown.
struct Nudge: Equatable {
    var appName: String
    var bundleID: String
    var activity: String
    var reminder: String
    var goal: String
}

/// Owns the focus session: the clock, the observe → judge loop and drift detection.
@MainActor @Observable
final class FocusController {
    static let shared = FocusController()

    // Session
    private(set) var phase: Phase = .idle
    var goal = ""
    /// Research and side tasks that count as on track. Remembered between sessions.
    var alsoRelevant: [String] = [] { didSet { Prefs.d.set(alsoRelevant, forKey: Prefs.alsoRelevant) } }
    /// Things that never count, however related they look. Remembered between sessions.
    var notRelevant: [String] = [] { didSet { Prefs.d.set(notRelevant, forKey: Prefs.notRelevant) } }
    private(set) var approved: [String] = []
    var plannedMinutes: Int? = 50

    // Awareness
    private(set) var attention: Attention = .unknown
    private(set) var checks: [CheckRecord] = []
    private(set) var current: (app: String, bundleID: String, activity: String)?
    private(set) var lastCheck: Date?
    private(set) var isChecking = false
    private(set) var nudges = 0
    private(set) var lastError: String?

    // UI
    var editingGoal = false
    private(set) var now = Date()
    private(set) var breakEndsAt: Date?
    private(set) var summary: SessionRecord?

    let model = ModelManager()
    private(set) var history = HistoryStore()

    /// Debug: swap in an in-memory sample history (stress test, screenshots). Never saved.
    func debugUseSampleHistory(_ count: Int) { history = HistoryStore(sampleSessions: count) }

    /// Hooks the AppKit layer fills in.
    var presentNudge: ((Nudge) -> Void)?
    var dismissNudge: (() -> Void)?

    private var accumulated: TimeInterval = 0
    private var segmentStart: Date?
    private var sessionStart: Date?
    private var ticker: Timer?
    private var monitor: Task<Void, Never>?
    private var offTrackSince: Date?
    private var lastNudgeAt: Date?
    /// The last window judged on-goal: where "Take me back" returns to.
    private var lastOnGoal: (pid: pid_t, title: String)?
    private let observer = ScreenObserver()
    /// Paused by sleep or a locked screen rather than by the user.
    private var autoPaused = false
    /// When the current pause or break began; the model is unloaded if it lasts.
    private var restingSince: Date?
    /// Opts out of App Nap during a session: Fokly is almost always in the background, and a
    /// napping app's timers drift, which would make the clock and the screen checks late.
    private var napGuard: NSObjectProtocol?
    /// Debug (`--tour`): stop real screen checks so a scripted walkthrough stays deterministic.
    var debugNoChecks = false
    /// Debug (`--stress`): no sounds or notifications.
    var debugMute = false

    private init() {
        plannedMinutes = Prefs.d.integer(forKey: Prefs.defaultMinutes).nonZero
        alsoRelevant = Prefs.d.stringArray(forKey: Prefs.alsoRelevant) ?? []
        notRelevant = Prefs.d.stringArray(forKey: Prefs.notRelevant) ?? []
        observeSleepAndLock()
    }

    /// Sleep and a locked screen pause the clock, so a closed lid never counts as focus time.
    private func observeSleepAndLock() {
        let ws = NSWorkspace.shared.notificationCenter
        let dnc = DistributedNotificationCenter.default()
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { FocusController.shared.autoPause() }
            }
        }
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { FocusController.shared.autoPause() }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { FocusController.shared.autoResume() }
            }
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { FocusController.shared.autoResume() }
        }
    }

    private func autoPause() {
        guard phase == .focusing else { return }
        togglePause()
        autoPaused = true
    }

    private func autoResume() {
        // Waking the screen while it's still locked isn't "back"; wait for the unlock.
        guard autoPaused, phase == .paused, !ScreenObserver.isScreenLocked() else { return }
        autoPaused = false
        togglePause()
    }

    // MARK: - Derived

    var isActive: Bool { phase == .focusing || phase == .paused || phase == .onBreak }

    var focusElapsed: TimeInterval {
        accumulated + (segmentStart.map { now.timeIntervalSince($0) } ?? 0)
    }

    var remaining: TimeInterval? {
        plannedMinutes.map { TimeInterval($0 * 60) - focusElapsed }
    }

    /// The number the clock shows: counts down with a plan, up without one.
    var clock: TimeInterval { remaining ?? focusElapsed }

    var progress: Double {
        if phase == .onBreak, let end = breakEndsAt {
            let total = TimeInterval(Prefs.d.integer(forKey: Prefs.breakMinutes) * 60)
            return total > 0 ? 1 - end.timeIntervalSince(now) / total : 0
        }
        guard let planned = plannedMinutes else { return (focusElapsed.truncatingRemainder(dividingBy: 3600)) / 3600 }
        return min(1, focusElapsed / TimeInterval(planned * 60))
    }

    var breakRemaining: TimeInterval { max(0, breakEndsAt?.timeIntervalSince(now) ?? 0) }

    var onGoalRatio: Double? {
        let judged = checks.filter { $0.status != .away }
        guard judged.count >= 3 else { return nil }
        return Double(judged.filter { $0.status == .onGoal }.count) / Double(judged.count)
    }

    var context: GoalContext {
        GoalContext(goal: goal, alsoRelevant: alsoRelevant, notRelevant: notRelevant, approved: approved)
    }

    /// The most frequent off-goal activities this session.
    var topDistractions: [String] {
        let off = checks.filter { $0.status == .offGoal }
        let counts = Dictionary(grouping: off) { $0.activity.isEmpty ? $0.appName : "\($0.activity) · \($0.appName)" }
        return counts.sorted { $0.value.count > $1.value.count }.prefix(3).map(\.key)
    }

    // MARK: - Lifecycle

    func start() {
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        goal = trimmed
        if editingGoal {
            editingGoal = false
            offTrackSince = nil
            return
        }
        reset()
        restingSince = nil
        autoPaused = false
        now = Date()  // `now` only ticks while a session runs; don't start from a stale value
        sessionStart = now
        segmentStart = now
        phase = .focusing
        attention = model.isReady ? .onTrack : .warmingUp
        model.prepare()
        if napGuard == nil {
            napGuard = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep, reason: "Focus session in progress")
        }
        startTicker()
        startMonitor()
        requestNotificationPermission()
        sound("Pop")
    }

    func togglePause() {
        autoPaused = false
        switch phase {
        case .focusing:
            accumulated = focusElapsed
            segmentStart = nil
            restingSince = Date()
            phase = .paused
        case .paused:
            now = Date()
            segmentStart = now
            restingSince = nil
            model.prepare()
            phase = .focusing
        default: break
        }
    }

    func startBreak(minutes: Int? = nil) {
        guard phase == .focusing || phase == .paused else { return }
        let m = minutes ?? Prefs.d.integer(forKey: Prefs.breakMinutes)
        accumulated = focusElapsed
        segmentStart = nil
        now = Date()
        breakEndsAt = now.addingTimeInterval(TimeInterval(max(1, m) * 60))
        restingSince = restingSince ?? now
        phase = .onBreak
        offTrackSince = nil
        dismissNudge?()
    }

    func extendBreak(minutes: Int = 5) {
        breakEndsAt = (breakEndsAt ?? Date()).addingTimeInterval(TimeInterval(minutes * 60))
    }

    func endBreak() {
        guard phase == .onBreak else { return }
        breakEndsAt = nil
        now = Date()
        segmentStart = now
        restingSince = nil
        model.prepare()
        phase = .focusing
        attention = .onTrack
    }

    func finish() {
        guard isActive else { return }
        accumulated = focusElapsed
        segmentStart = nil
        let record = SessionRecord(
            goal: goal, start: sessionStart ?? Date(), end: Date(),
            focused: accumulated, onGoalRatio: onGoalRatio, nudges: nudges,
            distractions: topDistractions)
        history.add(record)
        summary = record
        phase = .finished
        stopLoops()
        dismissNudge?()
        model.unload()
        sound("Glass")
    }

    func closeSummary(startAnother: Bool = false) {
        phase = .idle
        summary = nil
        if !startAnother { goal = "" }
    }

    private func reset() {
        accumulated = 0
        checks = []
        approved = []
        nudges = 0
        current = nil
        lastCheck = nil
        offTrackSince = nil
        lastNudgeAt = nil
        lastOnGoal = nil
        summary = nil
        lastError = nil
    }

    // MARK: - Nudge responses

    func markRelevant() {
        if let c = current {
            let note = c.activity.isEmpty ? c.app : "\(c.activity) (\(c.app))"
            if !approved.contains(note) { approved.append(note) }
        }
        offTrackSince = nil
        attention = .onTrack
        dismissNudge?()
    }

    func breakFromNudge() { startBreak() }

    func takeMeBack() {
        dismissNudge?()
        offTrackSince = nil
        attention = .onTrack
        if let target = lastOnGoal { WindowReturn.go(pid: target.pid, title: target.title) }
    }

    // MARK: - Loops

    private func startTicker() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { _ in
            Task { @MainActor in FocusController.shared.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        now = Date()
        if phase == .focusing, let r = remaining, r <= 0 {
            notify(title: "Session complete", body: "\(Clock.minutes(focusElapsed)) on “\(goal)”. Nice work.")
            finish()
        } else if phase == .onBreak, breakRemaining <= 0 {
            notify(title: "Break's over", body: "Back to: \(goal)")
            sound("Ping")
            endBreak()
        }
    }

    private func startMonitor() {
        monitor?.cancel()
        monitor = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            while !Task.isCancelled {
                guard let self else { return }
                if let since = self.restingSince, Date().timeIntervalSince(since) > 60,
                    self.model.state != .idle
                {
                    // A pause or break that lasts: hand the ~3 GB back; it reloads in about a second.
                    self.model.unload()
                }
                if self.debugNoChecks {
                    // scripted walkthrough drives attention itself
                } else if self.phase == .focusing, self.model.isReady, ScreenAccess.granted {
                    await self.check()
                } else if self.phase == .focusing, !self.model.isReady {
                    self.attention = .warmingUp
                }
                var interval = max(8, Prefs.d.double(forKey: Prefs.checkInterval))
                if ProcessInfo.processInfo.isLowPowerModeEnabled, Prefs.d.bool(forKey: Prefs.saveBattery) { interval *= 2 }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func stopLoops() {
        if let napGuard { ProcessInfo.processInfo.endActivity(napGuard) }
        napGuard = nil
        ticker?.invalidate()
        ticker = nil
        monitor?.cancel()
        monitor = nil
        isChecking = false
    }

    // MARK: - Judgement

    private func check() async {
        isChecking = true
        defer { isChecking = false }

        let useVision = Prefs.d.bool(forKey: Prefs.useVision)
        guard let obs = await observer.capture(includeImage: useVision), phase == .focusing else { return }

        // Away means really gone: a locked screen or 20 minutes without input. Sitting still in front
        // of a video is exactly the drift Fokly should catch, so short idle stretches are still judged.
        if obs.screenLocked || obs.idleSeconds > 1200 {
            record(.away, app: obs.appName, activity: "Away")
            attention = .away
            offTrackSince = nil
            return
        }

        // Every glance is judged fresh: a window title can stay the same while the page changes.
        let verdict: Verdict
        do {
            verdict = try await model.judge(obs, context: context)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            return
        }
        guard phase == .focusing else { return }

        lastCheck = Date()
        current = (obs.appName, obs.bundleID, verdict.activity)
        // The verdict alone decides; small models use "confidence" inconsistently. One wrong call
        // can't nudge anyone: drift has to last across several checks first.
        let offGoal = !verdict.relevant
        record(offGoal ? .offGoal : .onGoal, app: obs.appName, activity: verdict.activity)

        guard offGoal else {
            lastOnGoal = (obs.pid, obs.windowTitle)
            offTrackSince = nil
            attention = .onTrack
            return
        }

        // Show it right away (chip, menu bar); the nudge waits until the drift is sustained.
        attention = .drifting
        let since = offTrackSince ?? Date()
        offTrackSince = since
        let threshold = max(30, Prefs.d.double(forKey: Prefs.driftMinutes) * 60)
        guard Date().timeIntervalSince(since) >= threshold else { return }

        let cooledDown = lastNudgeAt.map { Date().timeIntervalSince($0) > max(180, threshold) } ?? true
        guard cooledDown else { return }

        lastNudgeAt = Date()
        nudges += 1
        let reminder = verdict.reminder.isEmpty
            ? "You've been on \(obs.appName) for a while. Ready to get back to it?"
            : verdict.reminder
        presentNudge?(Nudge(
            appName: obs.appName, bundleID: obs.bundleID, activity: verdict.activity,
            reminder: reminder, goal: goal))
        sound("Tink")
    }

    /// Debug (`--shots`): pretend more of the session has passed.
    func debugFastForward(_ seconds: TimeInterval) { accumulated += seconds }

    /// Debug (`--tour`): pretend a check just happened.
    func debugSimulate(onGoal: Bool, app: String, bundleID: String, activity: String) {
        lastCheck = Date()
        current = (app, bundleID, activity)
        record(onGoal ? .onGoal : .offGoal, app: app, activity: activity)
        attention = onGoal ? .onTrack : .drifting
    }

    private func record(_ status: CheckRecord.Status, app: String, activity: String) {
        checks.append(CheckRecord(date: Date(), status: status, appName: app, activity: activity))
        if checks.count > 400 { checks.removeFirst() }
    }

    // MARK: - Feedback

    private func sound(_ name: String) {
        guard Prefs.d.bool(forKey: Prefs.playSounds), !debugMute else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        guard !debugMute else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

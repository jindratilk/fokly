import Foundation
import Observation

/// Finished sessions, kept as a small JSON file in Application Support.
@MainActor @Observable
final class HistoryStore {
    private(set) var sessions: [SessionRecord] = []
    /// Sample stores (stress test, screenshots) never touch the user's file.
    private var persists = true

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fokly", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    init() {
        guard let data = try? Data(contentsOf: url) else { return }
        if let decoded = try? JSONDecoder().decode([SessionRecord].self, from: data) {
            sessions = decoded
        } else {
            // Never let the next save overwrite a file we couldn't read: keep it aside.
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try? FileManager.default.moveItem(at: url, to: url.deletingLastPathComponent()
                .appendingPathComponent("history-unreadable-\(stamp).json"))
        }
    }

    /// An in-memory store of `count` realistic sessions spread over the past weeks.
    init(sampleSessions count: Int) {
        persists = false
        let goals = ["Write the Q3 sales report", "Design onboarding in Figma", "Fix the login bug",
                     "Study for the Spanish exam", "Plan the week", "Draft the investor update"]
        let distractions = ["YouTube · Chrome", "X · Safari", "Reddit · Arc", "News · Safari", "Instagram · Chrome"]
        var rng = SystemRandomNumberGenerator()
        let now = Date()
        sessions = (0..<count).map { i in
            let daysBack = Double(Int.random(in: 0..<max(1, min(365, count / 3)), using: &rng))
            let start = now.addingTimeInterval(-daysBack * 86_400 - Double.random(in: 0..<36_000, using: &rng))
            let focused = Double([25, 25, 50, 50, 90, 15, 35].randomElement(using: &rng)!) * 60
            return SessionRecord(goal: goals[i % goals.count], start: start, end: start.addingTimeInterval(focused + 60),
                                 focused: focused, onGoalRatio: Double.random(in: 0.55...1, using: &rng),
                                 nudges: Int.random(in: 0...4, using: &rng),
                                 distractions: Array(distractions.shuffled(using: &rng).prefix(Int.random(in: 0...2, using: &rng))))
        }.sorted { $0.start < $1.start }
    }

    func add(_ record: SessionRecord) {
        guard record.focused >= 60 else { return }
        sessions.append(record)
        if sessions.count > 5000, persists { sessions.removeFirst(sessions.count - 5000) }
        save()
    }

    func delete(_ id: SessionRecord.ID) {
        sessions.removeAll { $0.id == id }
        save()
    }

    func deleteAll() {
        sessions.removeAll()
        save()
    }

    private func save() {
        guard persists else { return }
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: url, options: .atomic)
        // Goals and short activity notes are personal: readable by this user only.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    var today: [SessionRecord] {
        sessions.filter { Calendar.current.isDateInToday($0.start) }
    }

    var focusedToday: TimeInterval { today.reduce(0) { $0 + $1.focused } }

    /// Most recent distinct goals, newest first.
    var recentGoals: [String] {
        var seen = Set<String>()
        return sessions.reversed().map(\.goal).filter { seen.insert($0.lowercased()).inserted }.prefix(2).map { $0 }
    }

    // MARK: - Insights

    func sessions(since start: Date?) -> [SessionRecord] {
        guard let start else { return sessions }
        return sessions.filter { $0.start >= start }
    }

    /// Focused seconds per calendar day for the last `days` days, oldest first, including empty days.
    func daily(days: Int) -> [(day: Date, focused: TimeInterval)] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let byDay = Dictionary(grouping: sessions) { cal.startOfDay(for: $0.start) }
        return (0..<days).reversed().compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: todayStart) else { return nil }
            return (day, byDay[day]?.reduce(0) { $0 + $1.focused } ?? 0)
        }
    }

    /// Consecutive days, ending today or yesterday, with at least one session.
    var streak: Int {
        let cal = Calendar.current
        let days = Set(sessions.map { cal.startOfDay(for: $0.start) })
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while days.contains(day) {
            count += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }
}

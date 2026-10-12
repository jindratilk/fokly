import Charts
import SwiftUI

/// Statistics and the full session history.
struct InsightsView: View {
    @Environment(FocusController.self) private var focus
    @AppStorage(Prefs.accentHex) private var accent = ""
    @State private var range: Span = .week
    @State private var selectedDay: Date?
    /// Drives the grow-in of bars on open and on every period change.
    @State private var grown = false

    enum Span: String, CaseIterable, Identifiable {
        case week = "7 days", month = "30 days", year = "12 months", all = "All time"
        var id: Self { self }
        var days: Int? {
            switch self {
            case .week: 7
            case .month: 30
            case .year: 365
            case .all: nil
            }
        }
    }

    private var history: HistoryStore { focus.history }

    private var rangeStart: Date? {
        range.days.flatMap { Calendar.current.date(byAdding: .day, value: -($0 - 1), to: Calendar.current.startOfDay(for: Date())) }
    }

    private var inRange: [SessionRecord] { history.sessions(since: rangeStart) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if history.sessions.isEmpty {
                    emptyState
                } else {
                    tiles
                    chartCard
                    HStack(alignment: .top, spacing: 16) {
                        rankCard(title: "Top goals", icon: "scope", tint: Theme.focus, rows: topGoals,
                                 empty: "No sessions in this period.")
                        rankCard(title: "Top distractions", icon: "arrow.uturn.backward", tint: Theme.drift,
                                 rows: topDistractions, empty: "Nothing pulled you away. Nice.")
                    }
                    historySection
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 34)
            .padding(.bottom, 28)
        }
        .frame(minWidth: 620, minHeight: 520)
        .id(accent)
        .onAppear { grow() }
        .onChange(of: range) { _, _ in
            selectedDay = nil
            grown = false
            grow()
        }
    }

    private func grow() {
        withAnimation(Motion.reduced ? nil : .spring(response: 0.75, dampingFraction: 0.82).delay(0.08)) { grown = true }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Insights").font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Where your attention went.").foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Period", selection: $range) {
                ForEach(Span.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 330)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            FoklyMark(size: 44)
            Text("No sessions yet").font(.title3.weight(.semibold))
            Text("Finish a focus session and your stats will show up here.").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    // MARK: - Tiles

    private var tiles: some View {
        let sessions = inRange
        let focused = sessions.reduce(0) { $0 + $1.focused }
        let dayCount = Double(range.days ?? max(1, daysSinceFirst))
        let judged = sessions.filter { $0.onGoalRatio != nil }
        let judgedTime = judged.reduce(0) { $0 + $1.focused }
        let onGoal = judgedTime > 0 ? judged.reduce(0) { $0 + ($1.onGoalRatio ?? 0) * $1.focused } / judgedTime : nil
        let nudges = sessions.reduce(0) { $0 + $1.nudges }

        return HStack(spacing: 12) {
            tile("Focused", Clock.minutes(focused), "≈ \(Clock.minutes(focused / dayCount)) a day")
            tile("Sessions", "\(sessions.count)",
                 sessions.isEmpty ? "—" : "avg \(Clock.minutes(focused / Double(sessions.count)))")
            tile("On goal", onGoal.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                 "\(nudges) \(nudges == 1 ? "reminder" : "reminders")")
            tile("Streak", "\(history.streak) \(history.streak == 1 ? "day" : "days")", "in a row")
        }
    }

    private func tile(_ label: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(value).font(.clock(24, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(card)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.045))
    }

    private var daysSinceFirst: Int {
        guard let first = history.sessions.map(\.start).min() else { return 1 }
        return (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: first), to: Date()).day ?? 0) + 1
    }

    // MARK: - Chart

    private var chartDays: [(day: Date, focused: TimeInterval)] {
        history.daily(days: min(range.days ?? daysSinceFirst, range == .year || range == .all ? 365 : 30))
    }

    private var chartCard: some View {
        let data = chartDays
        let selected = selectedDay.flatMap { d in data.first { Calendar.current.isDate($0.day, inSameDayAs: d) } }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Focus time per day").font(.headline)
                Spacer()
                if let selected {
                    Text("\(selected.day.formatted(.dateTime.weekday(.wide).day().month())) · \(Clock.minutes(selected.focused))")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Chart(data, id: \.day) { item in
                BarMark(
                    x: .value("Day", item.day, unit: .day),
                    y: .value("Minutes", grown ? item.focused / 60 : 0)
                )
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                .foregroundStyle(Theme.focus.opacity(selected == nil || selected?.day == item.day ? 1 : 0.35))
            }
            .chartXSelection(value: $selectedDay)
            .animation(.easeOut(duration: 0.18), value: selectedDay)
            .chartYScale(domain: 0...max(10, (data.map(\.focused).max() ?? 0) / 60 * 1.1))
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel { if let m = value.as(Double.self) { Text("\(Int(m))m") } }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: data.count <= 7 ? 7 : 6)) { _ in
                    AxisValueLabel(format: data.count <= 7 ? .dateTime.weekday(.abbreviated) : .dateTime.day().month(.abbreviated), centered: true)
                }
            }
            .frame(height: 180)
        }
        .padding(16)
        .background(card)
    }

    // MARK: - Rankings

    private var topGoals: [(String, Double, String)] {
        let groups = Dictionary(grouping: inRange) { $0.goal.lowercased() }
        let rows = groups.map { (_, items) in (items.last!.goal, items.reduce(0) { $0 + $1.focused }) }
            .sorted { $0.1 > $1.1 }.prefix(5)
        let maxValue = rows.first?.1 ?? 1
        return rows.map { ($0.0, $0.1 / maxValue, Clock.minutes($0.1)) }
    }

    private var topDistractions: [(String, Double, String)] {
        var counts: [String: Int] = [:]
        for s in inRange { for d in s.distractions ?? [] { counts[d, default: 0] += 1 } }
        let rows = counts.sorted { $0.value > $1.value }.prefix(5)
        let maxValue = Double(rows.first?.value ?? 1)
        return rows.map { ($0.key, Double($0.value) / maxValue, "\($0.value)×") }
    }

    private func rankCard(title: String, icon: String, tint: Color, rows: [(String, Double, String)],
                          empty: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.headline)
            if rows.isEmpty {
                Text(empty).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(rows.enumerated()), id: \.element.0) { index, row in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(row.0).lineLimit(1)
                        Spacer()
                        Text(row.2).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.callout)
                    GeometryReader { geo in
                        Capsule().fill(Color.primary.opacity(0.06))
                            .overlay(alignment: .leading) {
                                Capsule().fill(tint)
                                    .frame(width: max(4, geo.size.width * (grown ? row.1 : 0)))
                                    .animation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.12 + Double(index) * 0.05),
                                               value: grown)
                            }
                    }
                    .frame(height: 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(card)
    }

    // MARK: - History

    private var historySection: some View {
        let days = Dictionary(grouping: history.sessions) { Calendar.current.startOfDay(for: $0.start) }
            .sorted { $0.key > $1.key }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("History").font(.title3.weight(.semibold))
                Text("\(history.sessions.count) sessions").foregroundStyle(.secondary)
            }
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(days, id: \.key) { day, sessions in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(dayTitle(day)).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(Clock.minutes(sessions.reduce(0) { $0 + $1.focused }))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        VStack(spacing: 0) {
                            ForEach(sessions.sorted { $0.start > $1.start }) { s in
                                HistoryRow(session: s) {
                                    withAnimation(.smooth) { focus.history.delete(s.id) }
                                }
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                                if s.id != sessions.min(by: { $0.start < $1.start })?.id {
                                    Divider().padding(.leading, 14)
                                }
                            }
                        }
                        .background(card)
                    }
                }
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }
}

private struct HistoryRow: View {
    var session: SessionRecord
    var delete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            Text("\(session.start.formatted(date: .omitted, time: .shortened))–\(session.end.formatted(date: .omitted, time: .shortened))")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.goal).lineLimit(1)
                if let d = session.distractions, !d.isEmpty {
                    Text("Distracted by \(d.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if session.nudges > 0 {
                Label("\(session.nudges)", systemImage: "bell")
                    .font(.caption).foregroundStyle(.secondary)
                    .help("\(session.nudges) \(session.nudges == 1 ? "reminder" : "reminders")")
            }
            if let r = session.onGoalRatio {
                Text("\(Int((r * 100).rounded()))%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(r >= 0.75 ? Theme.focus : Theme.drift)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill((r >= 0.75 ? Theme.focus : Theme.drift).opacity(0.14)))
                    .help("On goal")
            }
            Text(Clock.minutes(session.focused))
                .font(.callout.monospacedDigit())
                .frame(width: 70, alignment: .trailing)
            Button(role: .destructive, action: delete) {
                Image(systemName: "trash").font(.caption)
            }
            .buttonStyle(.borderless)
            .opacity(hovering ? 1 : 0)
            .help("Delete session")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { Button("Delete Session", role: .destructive, action: delete) }
    }
}

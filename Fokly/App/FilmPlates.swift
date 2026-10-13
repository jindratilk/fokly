#if DEVTOOLS
import AppKit
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

/// Windows for the launch video, rebuilt from screenshots of the real apps (ChatGPT Codex, X in Zen).
/// Each runs its own little script on `PlateClock`, so one recording covers the whole scene.
@MainActor @Observable
final class PlateClock {
    var t: Double = 0
    private var start: Date?

    /// Frame-by-frame rendering sets the time directly.
    func set(_ time: Double) { t = time }

    func run() {
        start = Date()
        Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { _ in
            MainActor.assumeIsolated { [self] in t = Date().timeIntervalSince(start ?? Date()) }
        }
    }
}

private func ease(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
private func progress(_ t: Double, _ a: Double, _ b: Double) -> Double { min(1, max(0, (t - a) / (b - a))) }
/// A gentler curve for scrolling: eases in and out without the cubic's sudden middle.
private func smooth(_ x: Double) -> Double { 0.5 - cos(x * .pi) / 2 }

// MARK: - ChatGPT Codex

struct CodexWindow: View {
    var clock: PlateClock
    private let message = "Add a last slide for the two permissions, AskForPermission style."
    private let answer = "Added a permissions slide at the end of the tour: Screen Recording and Accessibility, each with its own switch and a short why. The tour can't finish until both are on."

    private let ink = Color(white: 0.1), soft = Color(white: 0.45), faint = Color(white: 0.62)
    private let sideBG = Color(white: 0.965), line = Color(white: 0.9)

    var body: some View {
        let t = clock.t
        HStack(spacing: 0) {
            rail
            sidebar
            Rectangle().fill(line).frame(width: 1)
            VStack(spacing: 0) {
                titleBar
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 18) { history; live(t) }
                        .frame(width: 600, alignment: .leading)
                        .padding(.top, 18)
                        .frame(maxWidth: .infinity)
                }
                .scrollDisabled(true)
                .defaultScrollAnchor(.bottom)
                composer(t)
            }
            .background(Color.white)
        }
        .background(Color.white)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 8) {
                ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.79, blue: 0.25)], id: \.self) {
                    Circle().fill($0).frame(width: 12, height: 12)
                }
            }
            .padding(.leading, 14).padding(.top, 14)
        }
    }

    private var rail: some View {
        VStack(spacing: 18) {
            Color.clear.frame(height: 34)
            Image(systemName: "house.fill").font(.system(size: 15)).frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.9)))
            ForEach(["doc.on.doc", "clock", "at", "ellipsis"], id: \.self) {
                Image(systemName: $0).font(.system(size: 14)).foregroundStyle(soft)
            }
            Rectangle().fill(line).frame(width: 20, height: 1)
            ForEach(["arrow.triangle.branch", "square.grid.2x2"], id: \.self) {
                Image(systemName: $0).font(.system(size: 14)).foregroundStyle(soft)
            }
            Spacer()
            Circle().fill(Color(red: 0.25, green: 0.47, blue: 0.85)).frame(width: 24, height: 24)
                .overlay(Text("JT").font(.system(size: 9, weight: .bold)).foregroundStyle(.white))
                .padding(.bottom, 14)
        }
        .foregroundStyle(ink)
        .frame(width: 50)
        .background(sideBG)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 30)
            HStack {
                Text("Codex").font(.system(size: 17, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(soft)
                Spacer()
                Image(systemName: "bell").font(.system(size: 12)).foregroundStyle(soft)
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(soft).padding(.leading, 8)
            }
            .padding(.bottom, 14)
            row("square.and.pencil", "New chat").padding(.bottom, 16)
            section("Pinned")
            row(nil, "Launch video")
            row(nil, "Landing page copy").padding(.bottom, 16)
            HStack(spacing: 6) {
                Image(systemName: "folder").font(.system(size: 11)).foregroundStyle(soft)
                Text("fokly").font(.system(size: 13))
                Text("macbook").font(.system(size: 11)).foregroundStyle(faint)
                Spacer()
                Circle().fill(Color(red: 0.2, green: 0.7, blue: 0.35)).frame(width: 7, height: 7)
            }
            .padding(.vertical, 6)
            Group {
                row(nil, "Build Fokly's onboarding", selected: true)
                row(nil, "Fix the popover resize crash")
                row(nil, "Tune the judge prompt")
                row(nil, "Release v1.0")
            }
            .padding(.leading, 18)
            Spacer()
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 12)
        .frame(width: 236)
        .background(sideBG)
    }

    private func section(_ s: String) -> some View {
        Text(s).font(.system(size: 12, weight: .medium)).foregroundStyle(faint).padding(.bottom, 6)
    }

    private func row(_ icon: String?, _ s: String, selected: Bool = false) -> some View {
        HStack(spacing: 8) {
            if let icon { Image(systemName: icon).font(.system(size: 12)).foregroundStyle(soft) }
            Text(s).font(.system(size: 13)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color(white: 0.9) : .clear))
        .padding(.horizontal, -8)
    }

    private var titleBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.left").foregroundStyle(soft)
            Image(systemName: "chevron.right").foregroundStyle(faint)
            Image(systemName: "sidebar.left").foregroundStyle(soft).padding(.trailing, 6)
            Image(systemName: "folder").foregroundStyle(soft)
            Text("Build Fokly's onboarding").font(.system(size: 13, weight: .medium)).foregroundStyle(ink)
            Spacer()
            Image(systemName: "ellipsis").foregroundStyle(soft)
            Image(systemName: "list.bullet.indent").foregroundStyle(soft)
            Image(systemName: "plus.square").foregroundStyle(soft)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .frame(height: 42)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("The tour now has five slides: your goal, the checks, the reminder, privacy, and where Fokly lives in the menu bar. Each slide uses the real views, so it always matches the app.")
                .font(.system(size: 14)).foregroundStyle(ink).lineSpacing(4)
            HStack { Spacer(); bubble("nice. run it") }
            VStack(alignment: .leading, spacing: 8) {
                Text("Done. It opens on the first launch and after a reset in Settings.")
                    .font(.system(size: 14)).foregroundStyle(ink)
                diffChip("WelcomeTour.swift", "+212", "−40")
            }
        }
    }

    @ViewBuilder private func live(_ t: Double) -> some View {
        if t >= 1.85 {
            HStack { Spacer(); bubble(message) }
                .transition(.opacity)
        }
        if t >= 2.0 {
            VStack(alignment: .leading, spacing: 9) {
                if t < 13 {
                    HStack(spacing: 7) {
                        Circle().trim(from: 0, to: 0.7).stroke(soft, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                            .frame(width: 11, height: 11).rotationEffect(.degrees(t * 360))
                        Text("Working · \(Int(t - 2) + 1)s").font(.system(size: 13, weight: .medium))
                            .foregroundStyle(soft)
                    }
                }
                ForEach(Array(steps.enumerated()), id: \.offset) { _, s in
                    if t >= s.0 {
                        HStack(spacing: 7) {
                            Image(systemName: s.1).font(.system(size: 11)).foregroundStyle(faint).frame(width: 14)
                            Text(s.2).font(.system(size: 13)).foregroundStyle(soft)
                        }
                    }
                }
                if t >= 13 {
                    let n = Int(Double(answer.count) * progress(t, 13, 15.2))
                    Text(String(answer.prefix(n))).font(.system(size: 14)).foregroundStyle(ink).lineSpacing(4)
                        .padding(.top, 6)
                    if t >= 15.4 { diffChip("WelcomeTour.swift", "+86", "−12") }
                }
            }
        }
    }

    private let steps: [(Double, String, String)] = [
        (2.6, "doc.text", "Read WelcomeTour.swift"),
        (3.4, "doc.text", "Read PermissionGuide.swift"),
        (4.6, "magnifyingglass", "Searched for \"permission\" in 6 files"),
        (6.2, "pencil", "Edited WelcomeTour.swift"),
        (8.4, "pencil", "Edited PermissionGuide.swift"),
        (10.6, "hammer", "Built Fokly · succeeded"),
    ]

    private func bubble(_ s: String) -> some View {
        Text(s).font(.system(size: 14)).foregroundStyle(ink)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.94)))
            .frame(maxWidth: 420, alignment: .trailing)
    }

    private func diffChip(_ file: String, _ add: String, _ del: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.badge.gearshape").font(.system(size: 11)).foregroundStyle(soft)
            Text(file).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(ink)
            Text(add).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color(red: 0.12, green: 0.6, blue: 0.3))
            Text(del).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color(red: 0.85, green: 0.25, blue: 0.2))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(line))
    }

    private func composer(_ t: Double) -> some View {
        let typed = t < 1.85 ? String(message.prefix(Int(Double(message.count) * progress(t, 0.4, 1.7)))) : ""
        let working = t >= 1.85 && t < 15.2
        return VStack(alignment: .leading, spacing: 14) {
            Group {
                if typed.isEmpty { Text("Ask Codex anything").foregroundStyle(faint) }
                else { Text(typed).foregroundStyle(ink) + Text("|").foregroundStyle(Color.accentColor) }
            }
            .font(.system(size: 14))
            HStack(spacing: 12) {
                Image(systemName: "plus").font(.system(size: 14)).foregroundStyle(soft)
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 11))
                    Text("Full access").font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color(red: 0.88, green: 0.45, blue: 0.1))
                Spacer()
                Text("GPT-6.1 Sol").font(.system(size: 12, weight: .medium)).foregroundStyle(ink)
                    + Text(" High").font(.system(size: 12)).foregroundStyle(faint)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(faint)
                Image(systemName: "mic").font(.system(size: 13)).foregroundStyle(soft)
                Circle().fill(ink).frame(width: 28, height: 28)
                    .overlay(Image(systemName: working ? "stop.fill" : "arrow.up")
                        .font(.system(size: working ? 9 : 12, weight: .bold)).foregroundStyle(.white))
            }
        }
        .padding(14)
        .frame(width: 600)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white).shadow(color: .black.opacity(0.06), radius: 10, y: 2))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(line))
        .padding(.bottom, 18)
    }
}

// MARK: - X in Zen

struct XFeedWindow: View {
    var clock: PlateClock
    private let ink = Color(white: 0.06), soft = Color(white: 0.42), line = Color(white: 0.92)
    private let blue = Color(red: 0.11, green: 0.61, blue: 0.94)

    /// Plate timeline: browse the search, click the first post (1.7 s), scroll down its replies
    /// into "Discover more", where the Blue Angels video lands and plays (~3.1 s).
    static let clickAt = 1.75
    /// When the video in "Discover more" starts playing, as it scrolls into view.
    static let videoStart = 3.9

    var body: some View {
        let t = clock.t
        let onPost = t >= Self.clickAt
        let searchScroll = 70 * smooth(progress(t, 0.4, 1.6))
        let threadScroll = 790 * smooth(progress(t, 2.05, 4.25))
        HStack(alignment: .top, spacing: 0) {
            nav(onHome: false)
            VStack(spacing: 0) {
                if onPost { postHeader } else { searchHeader }
                // An overlay never sizes its parent, so the long thread can't stretch the window.
                Color.white.overlay(alignment: .top) {
                    if onPost {
                        VStack(spacing: 0) { thread }.fixedSize(horizontal: false, vertical: true).offset(y: -threadScroll)
                    } else {
                        VStack(spacing: 0) { searchResults }.fixedSize(horizontal: false, vertical: true).offset(y: -searchScroll)
                    }
                }
                .clipped()
            }
            .frame(width: 520)
            .overlay(alignment: .leading) { Rectangle().fill(line).frame(width: 1) }
            .overlay(alignment: .trailing) { Rectangle().fill(line).frame(width: 1) }
            sidebar.padding(.leading, 22)
            Spacer(minLength: 0)
        }
        .foregroundStyle(ink)
        .background(Color.white)
        .clipShape(.rect(cornerRadius: 10))
        .padding(6)
        .background(Color(white: 0.9))   // Zen's frame around the page
    }

    private var postHeader: some View {
        HStack(spacing: 22) {
            Image(systemName: "arrow.left").font(.system(size: 15))
            Text("Post").font(.system(size: 18, weight: .bold))
            Spacer()
            Text("Reply").font(.system(size: 13, weight: .bold)).padding(.horizontal, 14).frame(height: 30)
                .overlay(Capsule().strokeBorder(Color(white: 0.85)))
        }
        .padding(.horizontal, 16).frame(height: 54)
        .background(Color.white)
        .overlay(alignment: .bottom) { Rectangle().fill(line).frame(height: 1) }
    }

    @ViewBuilder private var thread: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle().fill(Color.pink.opacity(0.85)).frame(width: 40, height: 40)
                    .overlay(Text("M").font(.system(size: 16, weight: .bold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text("Mia Chen").font(.system(size: 14, weight: .bold))
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 12)).foregroundStyle(blue)
                    }
                    Text("@miachen_design").font(.system(size: 13)).foregroundStyle(soft)
                }
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 12)).foregroundStyle(soft)
            }
            Text("5 onboarding styles that actually work. 🧵\n1/ the progressive one: ask for one thing per screen").font(.system(size: 16)).lineSpacing(4)
            phones(dark: false)
            Text("9:41 AM · Oct 13, 2026 · 182K Views").font(.system(size: 13)).foregroundStyle(soft)
            Rectangle().fill(line).frame(height: 1)
            HStack {
                statIcon("bubble.left", "48"); Spacer(); statIcon("arrow.2.squarepath", "212"); Spacer()
                statIcon("heart", "3.1K"); Spacer(); statIcon("bookmark", "940"); Spacer()
                Image(systemName: "square.and.arrow.up").font(.system(size: 12)).foregroundStyle(soft)
            }
            Rectangle().fill(line).frame(height: 1)
            HStack(spacing: 10) {
                Circle().fill(Color(red: 0.95, green: 0.55, blue: 0.35)).frame(width: 34, height: 34)
                    .overlay(Text("J").font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
                Text("Post your reply").font(.system(size: 16)).foregroundStyle(soft)
                Spacer()
                Text("Reply").font(.system(size: 13, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 14).frame(height: 30)
                    .background(Capsule().fill(ink.opacity(0.5)))
            }
        }
        .padding(16)
        .overlay(alignment: .bottom) { Rectangle().fill(line).frame(height: 1) }
        reply("Ben Ortiz", "benortiz", "1h", "saving this for my onboarding redesign", .cyan)
        reply("Yuki Sato", "yuki_makes", "1h", "the progressive one is so underrated. fewer screens isn't always better", .mint)
        reply("Chris Webb", "chriswebb", "54m", "what did you use to make these?", .brown)
        reply("Nora Lind", "noralind", "40m", "4/ is the one everyone skips and regrets", .red)
        VStack(alignment: .leading, spacing: 2) {
            Text("Discover more").font(.system(size: 18, weight: .heavy))
            Text("Sourced from across X").font(.system(size: 13)).foregroundStyle(soft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .overlay(alignment: .bottom) { Rectangle().fill(line).frame(height: 1) }
        post(name: "SF Aviation", handle: "sfaviation", time: "4h", text: "Blue Angels over the Golden Gate this morning 🔥 #FleetWeek", color: Color(red: 0.1, green: 0.22, blue: 0.5),
             stats: ("812", "4.6K", "38K", "2.1M")) {
            ZStack(alignment: .bottomLeading) {
                if let frame = PlateFrames.clipFrame(at: clock.t - Self.videoStart) {
                    Image(nsImage: frame).resizable().aspectRatio(contentMode: .fill)
                } else if let player = Film.clip { ClipView(player: player) } else { Color(white: 0.1) }
                Text("0:24").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.65))).padding(10)
            }
            .frame(height: 252)
            .clipShape(.rect(cornerRadius: 14))
        }
        post(name: "Sam Rivera", handle: "samrivera_dev", time: "1h", text: "Opus 5.5 just refactored our whole payments module in one go. all tests green. a little scared tbh", color: .orange,
             stats: ("220", "1.1K", "9.8K", "604K")) { EmptyView() }
    }

    private func reply(_ name: String, _ handle: String, _ time: String, _ text: String, _ color: Color) -> some View {
        post(name: name, handle: handle, time: time, text: text, color: color,
             stats: ("\(text.count % 9)", "\(text.count % 5)", "\(text.count * 3)", "\(text.count / 4)K")) { EmptyView() }
    }

    private func nav(onHome: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("𝕏").font(.system(size: 28, weight: .black)).padding(.leading, 12).padding(.vertical, 8)
            navItem(onHome ? "house.fill" : "house", "Home", bold: onHome)
            navItem("magnifyingglass", "Explore", bold: !onHome)
            navItem("bell", "Notifications")
            navItem("envelope", "Messages")
            navItem("bookmark", "Bookmarks")
            navItem("person.2", "Communities")
            navItem("checkmark.seal", "Premium")
            navItem("person", "Profile")
            navItem("ellipsis.circle", "More")
            Text("Post").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(width: 180, height: 44).background(Capsule().fill(ink)).padding(.top, 10)
            Spacer()
            HStack(spacing: 8) {
                Circle().fill(Color(red: 0.95, green: 0.55, blue: 0.35)).frame(width: 34, height: 34)
                    .overlay(Text("J").font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text("Jindra Tilkovský").font(.system(size: 13, weight: .bold))
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 11)).foregroundStyle(blue)
                    }
                    Text("@tilkovsky").font(.system(size: 13)).foregroundStyle(soft)
                }
            }
            .padding(.bottom, 14)
        }
        .padding(.leading, 30)
        .frame(width: 250, alignment: .leading)
    }

    private func navItem(_ icon: String, _ title: String, bold: Bool = false) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 19, weight: bold ? .bold : .regular)).frame(width: 26)
            Text(title).font(.system(size: 17, weight: bold ? .bold : .regular))
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    private var searchHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.left").font(.system(size: 15))
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(soft)
                    Text("onboarding styles").font(.system(size: 14))
                    Spacer()
                }
                .padding(.horizontal, 14).frame(height: 38)
                .overlay(Capsule().strokeBorder(Color(white: 0.85)))
                Image(systemName: "ellipsis").font(.system(size: 14))
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            tabs(["Top", "Latest", "People", "Media", "Lists"])
        }
        .background(Color.white)
    }

    private func tabs(_ names: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(names.enumerated()), id: \.offset) { i, n in
                VStack(spacing: 10) {
                    Text(n).font(.system(size: 14, weight: i == 0 ? .bold : .medium)).foregroundStyle(i == 0 ? ink : soft)
                    Capsule().fill(i == 0 ? blue : .clear).frame(width: 56, height: 4)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(line).frame(height: 1) }
    }

    @ViewBuilder private var searchResults: some View {
        post(name: "Mia Chen", handle: "miachen_design", time: "2h", text: "5 onboarding styles that actually work. 🧵\n1/ the progressive one: ask for one thing per screen", color: .pink,
             stats: ("48", "212", "3.1K", "182K")) { phones(dark: false) }
        post(name: "Leo Park", handle: "leobuilds", time: "5h", text: "an onboarding should feel like a conversation, not a form", color: .indigo,
             stats: ("12", "64", "890", "41K")) { phones(dark: true) }
        post(name: "Ana Ruiz", handle: "anaruiz_ux", time: "8h", text: "permission screens are where most onboardings lose people. explain the why first.", color: .teal,
             stats: ("31", "120", "1.4K", "77K")) { EmptyView() }
        post(name: "Priya Nair", handle: "priyaships", time: "2h", text: "everyone is shipping onboardings with Opus 5.5 this week. show me yours", color: .purple,
             stats: ("1.4K", "380", "4.2K", "390K")) { EmptyView() }
    }

    private func post<Media: View>(name: String, handle: String, time: String, text: String, color: Color,
                                   stats: (String, String, String, String), @ViewBuilder media: () -> Media) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(color.opacity(0.85)).frame(width: 38, height: 38)
                .overlay(Text(String(name.prefix(1))).font(.system(size: 15, weight: .bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(name).font(.system(size: 14, weight: .bold))
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 12)).foregroundStyle(blue)
                    Text("@\(handle) · \(time)").font(.system(size: 14)).foregroundStyle(soft)
                    Spacer()
                    Image(systemName: "ellipsis").font(.system(size: 12)).foregroundStyle(soft)
                }
                Text(text).font(.system(size: 14)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                media()
                HStack {
                    statIcon("bubble.left", stats.0); Spacer()
                    statIcon("arrow.2.squarepath", stats.1); Spacer()
                    statIcon("heart", stats.2); Spacer()
                    statIcon("chart.bar", stats.3); Spacer()
                    Image(systemName: "bookmark").font(.system(size: 12)).foregroundStyle(soft)
                    Image(systemName: "square.and.arrow.up").font(.system(size: 12)).foregroundStyle(soft).padding(.leading, 10)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(line).frame(height: 1) }
    }

    private func statIcon(_ icon: String, _ n: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 12))
            Text(n).font(.system(size: 12))
        }
        .foregroundStyle(soft)
    }

    /// Onboarding screens, the kind of thing people post when they talk about onboarding.
    private func phones(dark: Bool) -> some View {
        HStack(spacing: 10) {
            ForEach(0..<3) { i in
                let titles = ["Welcome", "Pick a goal", "You're set"]
                RoundedRectangle(cornerRadius: 16)
                    .fill(dark ? Color(white: 0.08) : [Color(red: 1, green: 0.93, blue: 0.88), Color(red: 0.9, green: 0.94, blue: 1), Color(red: 0.9, green: 0.98, blue: 0.92)][i])
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 8) {
                            Capsule().fill((dark ? Color.white : ink).opacity(0.15)).frame(width: 30, height: 4).padding(.bottom, 18)
                            Text(titles[i]).font(.system(size: 15, weight: .bold)).foregroundStyle(dark ? .white : ink)
                            RoundedRectangle(cornerRadius: 3).fill((dark ? Color.white : ink).opacity(0.12)).frame(width: 90, height: 6)
                            RoundedRectangle(cornerRadius: 3).fill((dark ? Color.white : ink).opacity(0.12)).frame(width: 70, height: 6)
                            Spacer()
                            Capsule().fill(dark ? Color.white : ink).frame(height: 24)
                                .overlay(Text("Continue").font(.system(size: 10, weight: .semibold)).foregroundStyle(dark ? ink : .white))
                        }
                        .padding(12)
                    }
                    .frame(height: 200)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: dark ? 0.93 : 0.97)))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(soft)
                Text("Search").font(.system(size: 14)).foregroundStyle(soft)
                Spacer()
            }
            .padding(.horizontal, 14).frame(height: 38)
            .background(Capsule().fill(Color(white: 0.94)))
            .padding(.top, 8)
            VStack(alignment: .leading, spacing: 14) {
                Text("What's happening").font(.system(size: 18, weight: .heavy))
                trend("Technology · Trending", "Opus 5.5", "128K posts")
                trend("Trending in Technology", "#macOS27", "41.2K posts")
                trend("Sports · Trending", "Fleet Week", "22.6K posts")
                trend("Technology · Trending", "Xcode 27", "18.9K posts")
                Text("Show more").font(.system(size: 13)).foregroundStyle(blue)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).strokeBorder(line))
            Spacer()
        }
        .frame(width: 270)
    }

    private func trend(_ kicker: String, _ title: String, _ count: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kicker).font(.system(size: 12)).foregroundStyle(soft)
                Text(title).font(.system(size: 14, weight: .bold))
                Text(count).font(.system(size: 12)).foregroundStyle(soft)
            }
            Spacer()
            Image(systemName: "ellipsis").font(.system(size: 11)).foregroundStyle(soft)
        }
    }
}

/// `Fokly --film-frames codex|x <clip frames dir> <out dir> <seconds>`: renders a plate frame by
/// frame at exactly 60 fps (a live recording drops and bunches frames, which shows as judder).
@MainActor
enum PlateFrames {
    static var clipDir: String?

    static func clipFrame(at t: Double) -> NSImage? {
        guard let clipDir, t >= 0 else { return nil }
        let i = min(Int(t * 60) + 1, 449)
        return NSImage(contentsOfFile: String(format: "%@/%05d.jpg", clipDir, i))
    }

    static func run(kind: String, clipFrames: String, outDir: String, seconds: Double) {
        clipDir = clipFrames
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        let clock = PlateClock()
        let size = NSSize(width: 1100, height: 660)
        let root: AnyView = kind == "codex"
            ? AnyView(CodexWindow(clock: clock).frame(width: size.width, height: size.height))
            : AnyView(XFeedWindow(clock: clock).frame(width: size.width, height: size.height))
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = NSHostingView(rootView: root.environment(\.colorScheme, .light).transaction { $0.disablesAnimations = true })
        w.level = .screenSaver
        w.hasShadow = false
        w.backgroundColor = .white
        let screen = NSScreen.screens[0].frame
        w.setFrameOrigin(NSPoint(x: (screen.width - size.width) / 2, y: 80))
        w.orderFrontRegardless()
        Task {
            try? await Task.sleep(for: .seconds(1.0))
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
                  let target = content.windows.first(where: { $0.windowID == CGWindowID(w.windowNumber) }) else {
                print("FRAMES_ERROR window not found"); exit(1)
            }
            let config = SCStreamConfiguration()
            config.width = Int(size.width * 2)
            config.height = Int(size.height * 2)
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            let filter = SCContentFilter(desktopIndependentWindow: target)
            let count = Int(seconds * 60)
            for i in 0..<count {
                clock.set(Double(i) / 60)
                try? await Task.sleep(for: .milliseconds(24))
                guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { continue }
                let url = URL(fileURLWithPath: String(format: "%@/%05d.jpg", outDir, i + 1))
                if let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
                    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.94] as CFDictionary)
                    CGImageDestinationFinalize(dest)
                }
            }
            print("FRAMES_DONE \(count)")
            exit(0)
        }
    }
}
#endif

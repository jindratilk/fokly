#if DEVTOOLS
import AVFoundation
import AppKit
import ScreenCaptureKit
import SwiftUI

/// `Fokly --film <wallpaper.jpg> [clip.mp4]`: a staged desktop for the website video. The Fokly
/// parts are the real views (session popover, menu bar pill artwork, reminder), driven through a
/// scripted drift and return. It all lives in one window, so nothing else on screen is recorded.
/// Thumbnails for the video page are read from `thumb*.jpg` next to the clip.
@MainActor
enum Film {
    static let size = NSSize(width: 1280, height: 800)
    private static var window: NSWindow?
    static var clip: AVPlayer?
    /// `--light`: menu bar, Dock, popover and reminder in light appearance (for bright wallpapers).
    static let scheme: ColorScheme = CommandLine.arguments.contains("--light") ? .light : .dark
    private static var stream: SCStream?
    private static var recording: SCRecordingOutput?
    static var thumbs: [NSImage] = []

    // Layout shared by the views and the cursor script, so clicks land exactly on their targets.
    static let nudgeOrigin = CGPoint(x: size.width - 424 - 8, y: 30)
    /// Centre of "Take me back": nudge panel padding 12 + content padding 16, first of three buttons.
    static var takeMeBack: CGPoint {
        let contentX = nudgeOrigin.x + 12 + 16, contentW: CGFloat = 400 - 32
        let buttonW = (contentW - 16) / 3
        return CGPoint(x: contentX + buttonW / 2, y: nudgeButtonsY)
    }
    static var nudgeButtonsY: CGFloat = 0  // measured from the live layout
    static let dockApps = ["/System/Library/CoreServices/Finder.app", "/Applications/Safari.app", "/Applications/Pages.app",
                           "/System/Applications/Mail.app", "/System/Applications/Notes.app"]
    static let dockIcon: CGFloat = 52, dockGap: CGFloat = 10, dockPad: CGFloat = 10
    static var dockWidth: CGFloat { CGFloat(dockApps.count) * dockIcon + CGFloat(dockApps.count - 1) * dockGap + dockPad * 2 }
    static var dockY: CGFloat { size.height - 10 - (dockIcon + dockPad * 2) / 2 }
    static func dockCenter(_ i: Int) -> CGPoint {
        let x0 = (size.width - dockWidth) / 2 + dockPad
        return CGPoint(x: x0 + CGFloat(i) * (dockIcon + dockGap) + dockIcon / 2, y: dockY)
    }

    static func run(wallpaper: String, clip clipPath: String?) {
        if let clipPath {
            let player = AVPlayer(url: URL(fileURLWithPath: clipPath))
            player.isMuted = true
            clip = player
            let dir = URL(fileURLWithPath: clipPath).deletingLastPathComponent()
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            thumbs = names.filter { $0.hasPrefix("thumb") && $0.hasSuffix(".jpg") }.sorted()
                .compactMap { NSImage(contentsOf: dir.appendingPathComponent($0)) }
        }
        let f = FocusController.shared
        f.debugNoChecks = true
        f.debugMute = true
        f.debugUseSampleHistory(0)
        f.goal = "Write the Q3 sales report"
        f.alsoRelevant = []
        f.notRelevant = []
        f.plannedMinutes = 50
        f.start()
        f.debugFastForward(18 * 60 + 38)
        for i in 0..<22 {
            f.debugSimulate(onGoal: !(9...11).contains(i), app: "Pages", bundleID: "com.apple.iWork.Pages",
                            activity: "Drafting the EMEA section")
        }

        let director = Director()
        let view = Stage(director: director, wallpaper: NSImage(contentsOfFile: wallpaper)).environment(f)
        let w = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = NSHostingView(rootView: view)
        w.level = .screenSaver
        w.hasShadow = false
        let screen = NSScreen.screens[0].frame
        w.setFrame(NSRect(x: (screen.width - size.width) / 2, y: 60, width: size.width, height: size.height), display: true)
        w.orderFrontRegardless()
        window = w
        if let i = CommandLine.arguments.firstIndex(of: "--record"), i + 1 < CommandLine.arguments.count {
            // Record the window itself: no mouse pointer, nothing else on screen.
            let out = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                await record(window: w, to: out, seconds: 26) { director.start() }
                exit(0)
            }
        } else {
            director.start()
        }
    }
}

/// `Fokly --film-plate doc|yt <clip.mp4> <out.mov> <seconds>`: one window on its own, no shadow, filling the
/// recording, so the launch video can composite and animate it freely.
@MainActor @Observable
final class PlateTyping { var typed = 42 }

extension Film {
    static func runPlate(kind: String, clip clipPath: String, out: String, seconds: Double) {
        let player = AVPlayer(url: URL(fileURLWithPath: clipPath))
        player.isMuted = true
        clip = player
        let dir = URL(fileURLWithPath: clipPath).deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        thumbs = names.filter { $0.hasPrefix("thumb") && $0.hasSuffix(".jpg") }.sorted()
            .compactMap { NSImage(contentsOf: dir.appendingPathComponent($0)) }
        let typing = PlateTyping()
        let size = kind == "doc" ? NSSize(width: 700, height: 560) : NSSize(width: 1060, height: 640)
        let root: AnyView = switch kind {
        case "doc": AnyView(PlateDoc(typing: typing).frame(width: size.width, height: size.height))
        case "ig": AnyView(InstagramWindow().frame(width: size.width, height: size.height))
        default: AnyView(YouTubeWindow(shadow: false).frame(width: size.width, height: size.height))
        }
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = NSHostingView(rootView: root.environment(\.colorScheme, .light))
        w.level = .screenSaver
        w.hasShadow = false
        w.backgroundColor = .white
        let screen = NSScreen.screens[0].frame
        w.setFrameOrigin(NSPoint(x: (screen.width - size.width) / 2, y: 80))
        w.orderFrontRegardless()
        window = w
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await record(window: w, to: URL(fileURLWithPath: out), seconds: seconds) {
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                player.play()
                Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { _ in
                    MainActor.assumeIsolated { typing.typed = min(typing.typed + 1, 400) }
                }
            }
            exit(0)
        }
    }

    static func record(window: NSWindow, to url: URL, seconds: Double, onStart: @escaping () -> Void) async {
        do {
            try? FileManager.default.removeItem(at: url)
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
                print("FILM_ERROR window not found"); return
            }
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * 2)
            config.height = Int(window.frame.height * 2)
            config.showsCursor = false
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.ignoreShadowsSingleWindow = true
            let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: target), configuration: config, delegate: nil)
            let rc = SCRecordingOutputConfiguration()
            rc.outputURL = url
            rc.outputFileType = .mov
            rc.videoCodecType = .h264
            let rec = SCRecordingOutput(configuration: rc, delegate: RecordingDelegate.shared)
            try stream.addRecordingOutput(rec)
            try await stream.startCapture()
            self.stream = stream
            self.recording = rec
            try? await Task.sleep(for: .seconds(0.4))
            onStart()
            try? await Task.sleep(for: .seconds(seconds))
            try await stream.stopCapture()
            try? await Task.sleep(for: .seconds(1.5))
            print("FILM_DONE \(url.path)")
        } catch {
            print("FILM_ERROR \(error)")
        }
    }
}

private final class RecordingDelegate: NSObject, SCRecordingOutputDelegate {
    static let shared = RecordingDelegate()
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) { print("FILM_ERROR \(error)") }
}

/// The script, in seconds. One loop is 12 s and ends exactly where it began.
@MainActor @Observable
final class Director {
    var popoverOpen = true
    var onVideo = false
    var drifting = false
    var nudge = false
    var cursor = CGPoint(x: 520, y: 430)
    var pressing = false
    var typed = 0

    func start() {
        let loop: [(Double, () -> Void)] = [
            (0.0, { [self] in reset() }),
            (2.0, { [self] in popoverOpen = false; move(Film.dockCenter(1)) }),
            (3.2, { [self] in
                click()
                onVideo = true
                Film.clip?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                Film.clip?.play()
            }),
            (3.7, { [self] in move(CGPoint(x: 470, y: 380)) }),
            (5.0, { [self] in drifting = true; drift(true) }),
            (6.6, { [self] in nudge = true }),
            (7.1, { [self] in move(Film.takeMeBack) }),
            (8.6, { [self] in click() }),
            (8.8, { [self] in nudge = false; onVideo = false; drifting = false; drift(false); move(CGPoint(x: 520, y: 430)) }),
            (9.6, { Film.clip?.pause() }),
            (10.2, { [self] in popoverOpen = true }),
        ]
        func schedule() {
            for (t, step) in loop {
                DispatchQueue.main.asyncAfter(deadline: .now() + t) { withAnimation(.smooth(duration: 0.55)) { step() } }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { schedule() }
        }
        schedule()
        Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { _ in
            MainActor.assumeIsolated { [self] in if !onVideo { typed = min(typed + 1, 400) } }
        }
    }

    private func reset() {
        popoverOpen = true; onVideo = false; drifting = false; nudge = false; typed = 0
        cursor = CGPoint(x: 520, y: 430)
    }

    private func move(_ p: CGPoint) {
        withAnimation(.timingCurve(0.45, 0, 0.25, 1, duration: 0.9)) { cursor = p }
    }

    private func click() {
        withAnimation(.easeOut(duration: 0.08)) { pressing = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { withAnimation(.easeOut(duration: 0.12)) { self.pressing = false } }
    }

    private func drift(_ on: Bool) {
        FocusController.shared.debugSimulate(
            onGoal: !on, app: on ? "YouTube" : "Pages", bundleID: on ? "com.apple.Safari" : "com.apple.iWork.Pages",
            activity: on ? "Watching the Blue Angels" : "Drafting the EMEA section")
    }
}

private struct Stage: View {
    var director: Director
    var wallpaper: NSImage?
    @Environment(FocusController.self) private var focus

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let wallpaper { Image(nsImage: wallpaper).resizable().aspectRatio(contentMode: .fill) }
                else { LinearGradient(colors: [.pink, .orange], startPoint: .top, endPoint: .bottom) }
            }
            .frame(width: Film.size.width, height: Film.size.height)
            .clipped()

            DocWindow(typed: director.typed)
                .frame(width: 700, height: 560)
                .offset(x: 120, y: 92)
                .opacity(director.onVideo ? 0 : 1)
                .scaleEffect(director.onVideo ? 0.98 : 1)

            YouTubeWindow()
                .frame(width: 1060, height: 640)
                .offset(x: 46, y: 50)
                .opacity(director.onVideo ? 1 : 0)
                .scaleEffect(director.onVideo ? 1 : 0.97, anchor: .bottom)

            Dock(active: director.onVideo ? 1 : 2)

            MenuBar(drifting: director.drifting, app: director.onVideo ? "Safari" : "Pages")

            ActiveView(toggleMiniTimer: {}, openSettings: {})
                .frame(width: 340)
                .background(Color(white: Film.scheme == .dark ? 0.12 : 0.97).opacity(0.85), in: .rect(cornerRadius: 16))
                .background(.ultraThickMaterial, in: .rect(cornerRadius: 16))
                .environment(\.colorScheme, Film.scheme)
                .shadow(color: .black.opacity(0.3), radius: 30, y: 16)
                .scaleEffect(director.popoverOpen ? 1 : 0.94, anchor: .topTrailing)
                .opacity(director.popoverOpen ? 1 : 0)
                .offset(x: Film.size.width - 340 - 92, y: 34)

            NudgeView(nudge: Nudge(appName: "YouTube", bundleID: "com.apple.Safari", activity: "Watching the Blue Angels",
                                   reminder: "You've been watching the Blue Angels for a few minutes. The EMEA section is waiting.",
                                   goal: focus.goal),
                      takeMeBack: {}, relevant: {}, takeBreak: {}, close: {})
                .environment(\.colorScheme, Film.scheme)
                .background(GeometryReader { g in
                    // The buttons sit 16 pt above the content's bottom edge (panel padding 12 + content 16 − half a 30 pt button).
                    Color.clear.onAppear { Film.nudgeButtonsY = Film.nudgeOrigin.y + g.size.height - 12 - 16 - 15 }
                })
                .offset(x: Film.nudgeOrigin.x, y: Film.nudgeOrigin.y)
                .offset(x: director.nudge ? 0 : 40)
                .opacity(director.nudge ? 1 : 0)

            Pointer(pressing: director.pressing)
                .offset(x: director.cursor.x, y: director.cursor.y)
        }
        .frame(width: Film.size.width, height: Film.size.height, alignment: .topLeading)
        .clipped()
    }
}

/// The macOS arrow, drawn so its tip is the view's origin: offsetting it to a point puts the tip there.
private struct Pointer: View {
    var pressing: Bool
    var body: some View {
        Path { p in
            p.move(to: .zero)
            p.addLine(to: CGPoint(x: 0, y: 22))
            p.addLine(to: CGPoint(x: 5.5, y: 16.8))
            p.addLine(to: CGPoint(x: 9.6, y: 26))
            p.addLine(to: CGPoint(x: 13.2, y: 24.4))
            p.addLine(to: CGPoint(x: 9.2, y: 15.4))
            p.addLine(to: CGPoint(x: 16.4, y: 15.4))
            p.closeSubpath()
        }
        .fill(.black)
        .overlay(Path { p in
            p.move(to: .zero)
            p.addLine(to: CGPoint(x: 0, y: 22)); p.addLine(to: CGPoint(x: 5.5, y: 16.8)); p.addLine(to: CGPoint(x: 9.6, y: 26))
            p.addLine(to: CGPoint(x: 13.2, y: 24.4)); p.addLine(to: CGPoint(x: 9.2, y: 15.4)); p.addLine(to: CGPoint(x: 16.4, y: 15.4))
            p.closeSubpath()
        }.stroke(.white, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round)))
        .frame(width: 18, height: 27, alignment: .topLeading)
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        .scaleEffect(pressing ? 0.85 : 1, anchor: .topLeading)
    }
}

private struct MenuBar: View {
    var drifting: Bool
    var app: String
    @Environment(FocusController.self) private var focus

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "apple.logo").font(.system(size: 14))
            Text(app).font(.system(size: 13, weight: .bold))
            ForEach(["File", "Edit", "View", "Window"], id: \.self) { Text($0).font(.system(size: 13)) }
            Spacer()
            Image(systemName: "wifi").font(.system(size: 13))
            Image(systemName: "battery.75percent").font(.system(size: 15))
            Image(nsImage: StatusArt.pill(text: Clock.string(focus.clock), progress: focus.progress,
                                          tint: drifting ? Theme.driftNS : Theme.focusNS, glyph: .ring))
            Text("Tue 10:24").font(.system(size: 13, weight: .medium)).monospacedDigit()
        }
        .foregroundStyle(Film.scheme == .dark ? Color.white : Color.black)
        .padding(.horizontal, 16)
        .frame(width: Film.size.width, height: 30)
        .background(Film.scheme == .dark ? Color.black.opacity(0.32) : Color.white.opacity(0.35))
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, Film.scheme)
    }
}

private struct Dock: View {
    var active: Int
    var body: some View {
        HStack(spacing: Film.dockGap) {
            ForEach(Array(Film.dockApps.enumerated()), id: \.offset) { i, path in
                VStack(spacing: 3) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: Film.dockIcon, height: Film.dockIcon)
                    Circle().fill((Film.scheme == .dark ? Color.white : Color.black).opacity(i == active || i == 0 ? 0.7 : 0)).frame(width: 4, height: 4)
                }
                .frame(width: Film.dockIcon)
            }
        }
        .padding(.horizontal, Film.dockPad)
        .padding(.top, Film.dockPad)
        .padding(.bottom, Film.dockPad - 7)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
        .environment(\.colorScheme, Film.scheme)
        .frame(width: Film.dockWidth)
        .position(x: Film.size.width / 2, y: Film.dockY)
    }
}

struct DocWindow: View {
    var typed: Int
    var shadow = true
    private let text = "EMEA closed the quarter 12% ahead of plan. Germany and the Nordics carried most of the growth, while the UK held steady after a slow July. Renewals rose to 94%, the best result in two years."

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TitleBar(title: "Q3 Sales Report", dark: false)
            VStack(alignment: .leading, spacing: 16) {
                Text("Q3 Sales Report").font(.system(size: 30, weight: .bold))
                Text("Revenue grew 12% quarter over quarter, led by renewals and two new enterprise accounts in the Nordics.")
                    .font(.system(size: 15)).foregroundStyle(.secondary)
                Text("EMEA").font(.system(size: 20, weight: .semibold)).padding(.top, 6)
                (Text(String(text.prefix(typed))) + Text("|").foregroundColor(Color(nsColor: Theme.focusNS)))
                    .font(.system(size: 15))
                Spacer()
            }
            .padding(36)
            .foregroundStyle(.black)
        }
        .background(Color.white)
        .clipShape(.rect(cornerRadius: 12))
        .shadow(color: .black.opacity(shadow ? 0.28 : 0), radius: 30, y: 18)
    }
}

private struct PlateDoc: View {
    var typing: PlateTyping
    var body: some View { DocWindow(typed: typing.typed, shadow: false) }
}

// MARK: - Instagram Reels in Safari (dark theme), for the launch video

struct InstagramWindow: View {
    private let ink = Color(white: 0.96), soft = Color(white: 0.62), bg = Color.black

    var body: some View {
        VStack(spacing: 0) {
            SafariBar(url: "instagram.com/reels/C9fleetweek")
            HStack(spacing: 0) {
                sidebar
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 18) {
                    reel.frame(width: 322, height: 572)
                    actions.padding(.bottom, 6)
                }
                .padding(.top, 14)
                Spacer(minLength: 0)
                Color.clear.frame(width: 72)
            }
            Spacer(minLength: 0)
        }
        .background(bg)
    }

    private var sidebar: some View {
        VStack(spacing: 26) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).strokeBorder(ink, lineWidth: 2.2).frame(width: 25, height: 25)
                Circle().strokeBorder(ink, lineWidth: 2.2).frame(width: 11, height: 11)
                Circle().fill(ink).frame(width: 3, height: 3).offset(x: 6.5, y: -6.5)
            }
            .padding(.top, 26).padding(.bottom, 10)
            ForEach(["house", "magnifyingglass", "safari", "play.square.stack.fill", "paperplane", "heart", "plus.app"], id: \.self) { name in
                Image(systemName: name).font(.system(size: 21, weight: name.hasSuffix("fill") ? .bold : .regular)).foregroundStyle(ink)
                    .frame(width: 26, height: 26)
            }
            Circle().fill(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom)).frame(width: 26, height: 26)
                .overlay(Text("J").font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
            Spacer()
            Image(systemName: "line.3.horizontal").font(.system(size: 21)).foregroundStyle(ink).padding(.bottom, 22)
        }
        .frame(width: 72)
        .overlay(alignment: .trailing) { Rectangle().fill(Color(white: 0.15)).frame(width: 1) }
    }

    private var reel: some View {
        ZStack(alignment: .bottomLeading) {
            if let player = Film.clip { ClipView(player: player) } else { Color(white: 0.1) }
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Circle().fill(Color(red: 0.1, green: 0.22, blue: 0.5)).frame(width: 30, height: 30)
                        .overlay(Image(systemName: "anchor").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(red: 0.95, green: 0.8, blue: 0.3)))
                    Text("usnavy").font(.system(size: 13, weight: .semibold))
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 11)).foregroundStyle(Color(red: 0.25, green: 0.6, blue: 1))
                    Text("Follow").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 9).frame(height: 24)
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.7), lineWidth: 1))
                }
                Text("Blue Angels over the Golden Gate. Fleet Week never gets old #FleetWeek #BlueAngels")
                    .font(.system(size: 12)).lineLimit(2)
                HStack(spacing: 5) {
                    Image(systemName: "music.note").font(.system(size: 10, weight: .semibold))
                    Text("usnavy · Original audio").font(.system(size: 11))
                }
            }
            .foregroundStyle(.white)
            .padding(14)
            Image(systemName: "speaker.wave.2.fill").font(.system(size: 11)).foregroundStyle(.white)
                .frame(width: 28, height: 28).background(Circle().fill(.black.opacity(0.45)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(12)
        }
        .clipShape(.rect(cornerRadius: 10))
    }

    private var actions: some View {
        VStack(spacing: 20) {
            ForEach([("heart", "48.2K"), ("bubble.right", "1,204"), ("paperplane", "8,931"), ("bookmark", "")], id: \.0) { icon, count in
                VStack(spacing: 4) {
                    Image(systemName: icon).font(.system(size: 22)).foregroundStyle(ink)
                    if !count.isEmpty { Text(count).font(.system(size: 11, weight: .medium)).foregroundStyle(ink) }
                }
            }
            Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold)).foregroundStyle(ink).padding(.vertical, 4)
            RoundedRectangle(cornerRadius: 5).strokeBorder(ink, lineWidth: 1.5).frame(width: 24, height: 24)
                .overlay(Group { if let t = Film.thumbs.first { Image(nsImage: t).resizable().aspectRatio(contentMode: .fill) } }
                    .frame(width: 21, height: 21).clipShape(.rect(cornerRadius: 4)))
        }
        .frame(width: 44)
    }
}

// MARK: - A convincing YouTube watch page (dark theme)

struct YouTubeWindow: View {
    var shadow = true
    private let ink = Color(white: 0.95), soft = Color(white: 0.67), chip = Color(white: 0.15), bg = Color(white: 0.06)

    var body: some View {
        VStack(spacing: 0) {
            SafariBar(url: "youtube.com/watch?v=sffw-blue-angels")
            header
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    player.frame(width: 660, height: 371)
                    Text("Blue Angels over the Golden Gate | San Francisco Fleet Week")
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(ink).lineLimit(1)
                    channelRow
                    description
                }
                .frame(width: 660)
                upNext
            }
            .padding(.horizontal, 22)
            .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .background(bg)
        .clipShape(.rect(cornerRadius: 12))
        .shadow(color: .black.opacity(shadow ? 0.4 : 0), radius: 34, y: 20)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "line.3.horizontal").font(.system(size: 16)).foregroundStyle(ink)
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 5).fill(Color(red: 1, green: 0, blue: 0.05)).frame(width: 26, height: 18)
                    .overlay(Image(systemName: "play.fill").font(.system(size: 8)).foregroundStyle(.white))
                Text("YouTube").font(.system(size: 17, weight: .bold)).tracking(-0.6).foregroundStyle(ink)
            }
            Spacer()
            HStack(spacing: 0) {
                Text("fleet week blue angels").font(.system(size: 13)).foregroundStyle(ink).padding(.leading, 14)
                Spacer()
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(ink)
                    .frame(width: 52, height: 32).background(chip)
            }
            .frame(width: 400, height: 32)
            .background(Capsule().strokeBorder(Color(white: 0.2)))
            .clipShape(Capsule())
            Image(systemName: "mic.fill").font(.system(size: 13)).foregroundStyle(ink)
                .frame(width: 32, height: 32).background(Circle().fill(chip))
            Spacer()
            Image(systemName: "bell").font(.system(size: 15)).foregroundStyle(ink)
            Circle().fill(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom))
                .frame(width: 26, height: 26).overlay(Text("J").font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
        }
        .padding(.horizontal, 20)
        .frame(height: 50)
    }

    private var player: some View {
        ZStack(alignment: .bottom) {
            if let player = Film.clip { ClipView(player: player) } else { Color.black }
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom).frame(height: 80)
            VStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.3)).frame(height: 3)
                    Capsule().fill(.white.opacity(0.45)).frame(width: 420, height: 3)
                    Capsule().fill(Color.red).frame(width: 236, height: 3)
                    Circle().fill(Color.red).frame(width: 12, height: 12).offset(x: 230)
                }
                HStack(spacing: 16) {
                    Image(systemName: "pause.fill")
                    Image(systemName: "forward.end.fill")
                    Image(systemName: "speaker.wave.2.fill")
                    Text("1:24 / 6:12").font(.system(size: 12, weight: .medium)).monospacedDigit()
                    Spacer()
                    Image(systemName: "captions.bubble")
                    Image(systemName: "gearshape.fill")
                    Image(systemName: "rectangle.inset.filled")
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .font(.system(size: 13))
                .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 9)
        }
        .clipShape(.rect(cornerRadius: 12))
    }

    private var channelRow: some View {
        HStack(spacing: 10) {
            Circle().fill(Color(red: 0.1, green: 0.22, blue: 0.5)).frame(width: 38, height: 38)
                .overlay(Image(systemName: "anchor").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color(red: 0.95, green: 0.8, blue: 0.3)))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("U.S. Navy").font(.system(size: 14, weight: .semibold)).foregroundStyle(ink)
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(soft)
                }
                Text("1.2M subscribers").font(.system(size: 11)).foregroundStyle(soft)
            }
            Text("Subscribe").font(.system(size: 13, weight: .semibold)).foregroundStyle(.black)
                .padding(.horizontal, 15).frame(height: 34).background(Capsule().fill(ink))
                .padding(.leading, 8)
            Spacer()
            HStack(spacing: 0) {
                Label("48K", systemImage: "hand.thumbsup").padding(.horizontal, 14)
                Rectangle().fill(Color(white: 0.3)).frame(width: 1, height: 20)
                Image(systemName: "hand.thumbsdown").padding(.horizontal, 14)
            }
            .frame(height: 34).background(Capsule().fill(chip))
            Label("Share", systemImage: "arrowshape.turn.up.right").padding(.horizontal, 14).frame(height: 34).background(Capsule().fill(chip))
            Image(systemName: "ellipsis").frame(width: 34, height: 34).background(Circle().fill(chip))
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(ink)
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("1,408,226 views  ·  Oct 12, 2026  ·  #FleetWeek #BlueAngels #SanFrancisco")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
            Text("The U.S. Navy Flight Demonstration Squadron performs over the San Francisco Bay during Fleet Week…")
                .font(.system(size: 12)).foregroundStyle(ink).lineLimit(1)
            Text("...more").font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(chip))
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(Array(["All", "From U.S. Navy", "Air shows"].enumerated()), id: \.offset) { i, t in
                    Text(t).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(i == 0 ? .black : ink)
                        .padding(.horizontal, 11).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(i == 0 ? ink : chip))
                }
            }
            ForEach(Array(upNextItems.enumerated()), id: \.offset) { i, item in
                HStack(alignment: .top, spacing: 9) {
                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if i < Film.thumbs.count { Image(nsImage: Film.thumbs[i]).resizable().aspectRatio(contentMode: .fill) }
                            else { Color(white: 0.2) }
                        }
                        .frame(width: 150, height: 84).clipped()
                        Text(item.3).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.8))).padding(4)
                    }
                    .clipShape(.rect(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.0).font(.system(size: 12, weight: .semibold)).foregroundStyle(ink).lineLimit(2)
                        Text(item.1).font(.system(size: 11)).foregroundStyle(soft)
                        Text(item.2).font(.system(size: 11)).foregroundStyle(soft)
                    }
                }
            }
        }
        .frame(width: 330, alignment: .leading)
    }

    private let upNextItems = [
        ("Diamond formation over Alcatraz", "U.S. Navy", "820K views · 1 day ago", "4:51"),
        ("Fat Albert takes off at SFO", "Fleet Week SF", "312K views · 3 days ago", "2:07"),
        ("Cockpit view: the Delta Break", "U.S. Navy", "2.4M views · 1 year ago", "9:16"),
        ("Fleet Week 2026 full air show", "KQED", "96K views · 5 hours ago", "1:12:40"),
    ]
}

private struct SafariBar: View {
    var url: String
    var body: some View {
        HStack(spacing: 8) {
            ForEach([Color.red, .yellow, .green], id: \.self) { c in Circle().fill(c.opacity(0.85)).frame(width: 12, height: 12) }
            Image(systemName: "sidebar.left").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5)).padding(.leading, 14)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 10))
                Text(url).font(.system(size: 12))
            }
            .foregroundStyle(.white.opacity(0.75))
            .frame(width: 420, height: 26)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.2)))
            Spacer()
            Image(systemName: "square.and.arrow.up").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
            Image(systemName: "plus").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Color(white: 0.11))
    }
}

private struct ClipView: NSViewRepresentable {
    var player: AVPlayer
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        v.layer = layer
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct TitleBar: View {
    var title: String
    var dark: Bool
    var body: some View {
        HStack(spacing: 8) {
            ForEach([Color.red, .yellow, .green], id: \.self) { c in Circle().fill(c.opacity(0.85)).frame(width: 12, height: 12) }
            Text(title).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(dark ? .white.opacity(0.6) : .black.opacity(0.55)).padding(.leading, 10)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(dark ? Color(white: 0.12) : Color(white: 0.96))
    }
}
#endif

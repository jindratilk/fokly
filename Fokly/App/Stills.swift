#if DEVTOOLS
import AppKit
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

/// `Fokly --stills <dir>`: renders the real views one by one for the launch video, each captured
/// twice, over white and over grey, so the video tooling can recover a clean alpha channel
/// (glass, shadows and all). Also writes the menu bar pill artwork at 8x. Debug only.
@MainActor
enum Stills {
    @MainActor @Observable
    final class Model {
        var background = Color.white
        var item: Item = .none
        var nudge = Nudge(appName: "Instagram", bundleID: "com.apple.Safari", activity: "Watching Instagram reels",
                          reminder: "You've been watching Instagram reels for a few minutes. The EMEA section is waiting.",
                          goal: Stills.goal)
    }

    enum Item { case none, start, active, nudge }

    static let canvas = NSSize(width: 600, height: 1000)
    static let goal = "Write the Q3 sales report"

    static func run(dir: String) async {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        NSApp.appearance = NSAppearance(named: .aqua)
        let f = FocusController.shared
        f.debugNoChecks = true
        f.debugMute = true
        f.debugUseSampleHistory(0)
        let saved = (f.alsoRelevant, f.notRelevant)
        f.alsoRelevant = []
        f.notRelevant = []
        f.plannedMinutes = 50
        f.goal = ""

        let model = Model()
        let w = KeyWindow(contentRect: NSRect(origin: .zero, size: canvas), styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = NSHostingView(rootView: Root(model: model).environment(f))
        w.level = .screenSaver
        w.hasShadow = false
        let screen = NSScreen.screens[0].frame
        w.setFrameOrigin(NSPoint(x: screen.maxX - canvas.width - 40, y: screen.minY + 40))
        w.orderFrontRegardless()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)  // controls render in their active look only in the key window
        try? await Task.sleep(for: .seconds(0.8))
        print("STILLS key=\(w.isKeyWindow) active=\(NSApp.isActive)")

        func shoot(_ name: String) async {
            for (suffix, bg) in [("w", Color.white), ("g", Color(white: 0.55))] {
                model.background = bg
                try? await Task.sleep(for: .seconds(0.35))
                await capture(w, to: "\(dir)/\(name)_\(suffix).png")
            }
        }

        // Typing the goal, one character at a time.
        model.item = .start
        try? await Task.sleep(for: .seconds(1.0))
        for n in 0...goal.count {
            f.goal = String(goal.prefix(n))
            try? await Task.sleep(for: .seconds(0.15))
            await shoot(String(format: "start_%02d", n))
        }

        // The session running, a few seconds of clock. Wait for the model so the card shows what it sees.
        f.start()
        for _ in 0..<120 where f.model.state != .ready { try? await Task.sleep(for: .seconds(0.5)) }
        f.debugFastForward(60 + 48)
        f.debugSimulate(onGoal: true, app: "Pages", bundleID: "com.apple.iWork.Pages", activity: "Drafting the EMEA section")
        model.item = .active
        try? await Task.sleep(for: .seconds(2.5))

        /// Shoots right after the clock ticks, so both backgrounds see the same second.
        func shootOnTick(_ name: String) async -> TimeInterval {
            let shown = Clock.string(f.clock)
            while Clock.string(f.clock) == shown { try? await Task.sleep(for: .milliseconds(10)) }
            let t = f.clock
            for (suffix, bg) in [("w", Color.white), ("g", Color(white: 0.55))] {
                model.background = bg
                try? await Task.sleep(for: .seconds(0.06))
                await capture(w, to: "\(dir)/\(name)_\(suffix).png")
            }
            return t
        }
        var focusTimes: [TimeInterval] = []
        for i in 0..<4 { focusTimes.append(await shootOnTick("active_\(i)")) }

        // Drifting.
        f.debugSimulate(onGoal: false, app: "YouTube", bundleID: "com.apple.Safari", activity: "Watching the Blue Angels")
        try? await Task.sleep(for: .seconds(0.5))
        _ = await shootOnTick("active_drift")

        model.item = .nudge
        try? await Task.sleep(for: .seconds(1.0))
        await shoot("nudge")

        // Other ways to drift, for a quick montage.
        let others: [(String, String, String, String)] = [
            ("news", "News", "com.apple.news", "You've been reading the news for a few minutes."),
            ("messages", "Messages", "com.apple.MobileSMS", "You've been chatting in Messages for a while."),
            ("x", "X", "com.apple.Safari", "You've been scrolling X for a few minutes."),
            ("youtube", "YouTube", "com.apple.Safari", "You've been watching YouTube for a few minutes."),
            ("music", "Music", "com.apple.Music", "You've been building a playlist for a few minutes."),
        ]
        for (name, app, bundle, line) in others {
            model.nudge = Nudge(appName: app, bundleID: bundle, activity: line, reminder: line + " The EMEA section is waiting.", goal: Stills.goal)
            try? await Task.sleep(for: .seconds(0.6))
            await shoot("nudge_\(name)")
        }

        // Menu bar pills matching the card's clock, one per second, in both tints.
        for i in 0..<8 {
            // Drift pills pick up where the desktop film's clock is when it drifts (31:01).
            let t = focusTimes[0] - Double(i), d = Double(31 * 60 + 1 - i)
            writePill(StatusArt.pill(text: Clock.string(t), progress: 1 - t / 3000, tint: Theme.focusNS, glyph: .ring),
                      to: "\(dir)/pill_focus_\(i).png")
            writePill(StatusArt.pill(text: Clock.string(d), progress: 1 - d / 3000, tint: Theme.driftNS, glyph: .ring),
                      to: "\(dir)/pill_drift_\(i).png")
        }
        print("STILLS clocks \(focusTimes.map { Clock.string($0) })")

        f.finish()
        f.closeSummary()
        (f.alsoRelevant, f.notRelevant) = saved
        print("STILLS_DONE \(dir)")
        exit(0)
    }

    private final class KeyWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }

    private static func capture(_ window: NSWindow, to path: String) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
                print("STILLS_ERROR window not found"); return
            }
            let config = SCStreamConfiguration()
            config.width = Int(canvas.width * 2)
            config.height = Int(canvas.height * 2)
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: config)
            writePNG(image, to: path)
        } catch {
            print("STILLS_ERROR \(error)")
        }
    }

    private static func writePill(_ image: NSImage, to path: String) {
        let scale: CGFloat = 8
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * scale),
                                         pixelsHigh: Int(image.size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return }
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        if let cg = rep.cgImage { writePNG(cg, to: path) }
    }

    private static func writePNG(_ image: CGImage, to path: String) {
        guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    private struct Root: View {
        var model: Model

        var body: some View {
            ZStack(alignment: .top) {
                model.background
                Group {
                    switch model.item {
                    case .none: EmptyView()
                    case .start: card { StartView(openSettings: {}, openInsights: {}) }
                    case .active: card { ActiveView(toggleMiniTimer: {}, openSettings: {}) }
                    case .nudge:
                        NudgeView(nudge: model.nudge, takeMeBack: {}, relevant: {}, takeBreak: {}, close: {})
                    }
                }
                .padding(.top, 60)
            }
            .frame(width: Stills.canvas.width, height: Stills.canvas.height)
            .environment(\.colorScheme, .light)
            .transaction { $0.disablesAnimations = true }  // no half-rolled digits in a still
        }

        private func card(@ViewBuilder _ content: () -> some View) -> some View {
            content()
                .frame(width: 340)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.985)))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.16), radius: 30, y: 14)
        }
    }
}
#endif

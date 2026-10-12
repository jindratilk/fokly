import AppKit
import CoreImage
import ScreenCaptureKit
import Vision

/// A snapshot of what the user is doing right now. Lives only in memory.
struct ScreenSnapshot: @unchecked Sendable {
    var appName: String
    var bundleID: String
    var windowTitle: String
    var text: String
    var image: CIImage?
    var idleSeconds: TimeInterval
    var screenLocked: Bool
    var pid: pid_t = 0

}

enum ScreenAccess {
    static var granted: Bool { CGPreflightScreenCaptureAccess() }

    static func request() {
        if !CGRequestScreenCaptureAccess(),
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        {
            NSWorkspace.shared.open(url)
        }
    }
}

final class ScreenObserver: @unchecked Sendable {
    private let ownBundleID = Bundle.main.bundleIdentifier ?? "app.fokly.Fokly"

    func capture(includeImage: Bool) async -> ScreenSnapshot? {
        let (app, idle, locked) = await MainActor.run {
            (NSWorkspace.shared.frontmostApplication, Self.idleSeconds(), Self.isScreenLocked())
        }
        guard let app, app.bundleIdentifier != ownBundleID else { return nil }

        var obs = ScreenSnapshot(
            appName: app.localizedName ?? "Unknown app",
            bundleID: app.bundleIdentifier ?? "",
            windowTitle: "",
            text: "",
            image: nil,
            idleSeconds: idle,
            screenLocked: locked,
            pid: app.processIdentifier
        )
        if locked { return obs }

        guard let front = Self.frontWindow(pid: app.processIdentifier) else { return obs }
        obs.windowTitle = front.title

        guard ScreenAccess.granted,
            let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
            let window = content.windows.first(where: { $0.windowID == front.id })
        else { return obs }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        // Retina where it fits, but never more than 1440 px on the long side.
        let scale = min(2, 1440 / max(window.frame.width, window.frame.height))
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true

        guard let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        else { return obs }

        obs.text = await Self.recognizeText(in: cg)
        if includeImage { obs.image = CIImage(cgImage: cg) }
        return obs
    }

    // MARK: - Helpers

    private static func frontWindow(pid: pid_t) -> (id: CGWindowID, title: String)? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        // The list is ordered front to back.
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                (info[kCGWindowLayer as String] as? Int) == 0,
                let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                (bounds["Width"] ?? 0) > 120, (bounds["Height"] ?? 0) > 80,
                let id = info[kCGWindowNumber as String] as? CGWindowID
            else { continue }
            return (id, info[kCGWindowName as String] as? String ?? "")
        }
        return nil
    }

    private static func recognizeText(in image: CGImage) async -> String {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                request.automaticallyDetectsLanguage = true
                try? VNImageRequestHandler(cgImage: image).perform([request])
                let lines = (request.results ?? [])
                    .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
                    .compactMap { $0.topCandidates(1).first?.string }
                    .filter { $0.count > 2 }
                var text = ""
                for line in lines {
                    if text.count + line.count > 1800 { break }
                    text += line + "\n"
                }
                cont.resume(returning: text)
            }
        }
    }

    @MainActor static func idleSeconds() -> TimeInterval {
        let anyInput = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    @MainActor static func isScreenLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}

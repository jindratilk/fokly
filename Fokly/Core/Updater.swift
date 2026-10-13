import AppKit
import Observation
import Sparkle

/// Updates through Sparkle: the feed at fokly.app/appcast.xml is checked once a day and every
/// release is verified against the EdDSA key in Info.plist before it's installed.
///
/// A focus app shouldn't interrupt focus with its own news, so a scheduled check never opens a
/// window. It only marks the update as available (a small button in the popover and an item in
/// the menu); the update window opens when you click it.
@MainActor
@Observable
final class Updater: NSObject {
    static let shared = Updater()

    /// Version of an update a scheduled check found, until you open it or it's installed.
    private(set) var available: String?

    @ObservationIgnored private var controller: SPUStandardUpdaterController!

    override private init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
    }

    func start() { controller.startUpdater() }

    func checkForUpdates() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    /// The daily check (Settings → About). Sparkle keeps the setting.
    var automaticallyChecks = true {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }
}

extension Updater: SPUUpdaterDelegate {
    #if DEVTOOLS
    /// Debug: FOKLY_FEED points the updater at a local appcast to try an update end to end.
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? { ProcessInfo.processInfo.environment["FOKLY_FEED"] }
    #endif
}

extension Updater: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !state.userInitiated { available = update.displayVersionString }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        available = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        available = nil
    }
}

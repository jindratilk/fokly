import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
struct FoklyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Fokly lives in the menu bar; settings get their own window.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var status: StatusItemController?
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Migration.run()
        Prefs.register()
        FocusJudge.configureMemory()
        #if DEVTOOLS
        if DevTools.runBeforeUI(delegate: self) { return }
        #endif
        let status = StatusItemController()
        self.status = status

        hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)) {
            status.togglePopover()
        }

        #if DEVTOOLS
        if DevTools.run(status: status) { return }
        #endif
        if !Prefs.d.bool(forKey: Prefs.onboarded) {
            let resume = Prefs.d.bool(forKey: Prefs.tourAtPermissions)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { status.showWelcome(atPermissions: resume) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        status?.showPopover()
        return false
    }
}

/// System-wide shortcut via Carbon, which needs no extra permissions.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let me = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { me.action() }
                return noErr
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: OSType(0x464F_4B4C), id: 1),
                            GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

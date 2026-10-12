import AppKit
import ApplicationServices

/// Brings the user back to the window — or browser tab — they were last working in.
///
/// Works through the Accessibility API, so it needs no per-app scripting and covers
/// Safari, Chrome, Arc, Brave, Edge, Firefox and Zen alike: browsers expose their tabs
/// as accessibility elements, and pressing one selects it.
enum WindowReturn {
    @MainActor static func go(pid: pid_t, title: String) {
        guard let app = NSRunningApplication(processIdentifier: pid), let url = app.bundleURL else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { restore(pid: pid, title: title) }
        }
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    @MainActor private static func restore(pid: pid_t, title: String, attempt: Int = 0) {
        guard !title.isEmpty else { return }
        guard isTrusted else {
            if !askedForAccessibility {
                askedForAccessibility = true
                requestTrust()
            }
            return
        }
        if attempt == 0 { wakeAccessibility(pid: pid) }
        let windows = windows(of: pid)

        // 1. The window itself still carries that title (most apps, or the tab is still frontmost).
        if let window = windows.first(where: { string($0, kAXTitleAttribute) == title }) {
            raise(window)
            sleepAccessibility(pid: pid)
            return
        }

        // 2. A browser whose window title moved on with another tab: find the tab and press it.
        var best: (window: AXUIElement, tab: AXUIElement, score: Int)?
        for window in windows {
            for tab in tabs(in: window) {
                let score = match(tabTitle: tab.title, windowTitle: title)
                if score > (best?.score ?? 0) { best = (window, tab.element, score) }
            }
        }
        if let best {
            raise(best.window)
            AXUIElementPerformAction(best.tab, kAXPressAction as CFString)
            sleepAccessibility(pid: pid)
        } else if attempt < 8 {
            // The browser may still be building its accessibility tree.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { restore(pid: pid, title: title, attempt: attempt + 1) }
        } else {
            sleepAccessibility(pid: pid)
        }
    }

    /// How well a tab title explains a remembered window title. 0 = no match.
    /// Browsers title windows "<page title>" or "<page title> — <Browser name>".
    static func match(tabTitle: String, windowTitle: String) -> Int {
        let tab = tabTitle.trimmingCharacters(in: .whitespaces)
        guard tab.count >= 2 else { return 0 }
        if tab == windowTitle { return 10_000 }
        if windowTitle.hasPrefix(tab) { return tab.count }
        return 0
    }

    // MARK: - Accessibility helpers

    /// Chromium and Gecko browsers build their accessibility tree lazily; ask them to expose it.
    static func wakeAccessibility(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        var current: CFTypeRef?
        AXUIElementCopyAttributeValue(app, "AXEnhancedUserInterface" as CFString, &current)
        // Remember whether something else (VoiceOver, say) already had it on.
        enhancedWasOn[pid] = (current as? Bool) ?? false
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    static func sleepAccessibility(pid: pid_t) {
        // Enhanced UI slows window animations in some apps, so switch it back off — but only if
        // it was off before we came along; assistive apps may rely on it.
        guard enhancedWasOn.removeValue(forKey: pid) == false else { return }
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
    }

    nonisolated(unsafe) private static var enhancedWasOn: [pid_t: Bool] = [:]

    static func windows(of pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    /// Tab-like elements in a window: tab buttons, radio buttons in tab strips, tab-group children.
    static func tabs(in window: AXUIElement) -> [(element: AXUIElement, title: String)] {
        var found: [(AXUIElement, String)] = []
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var visited = 0
        while !queue.isEmpty, visited < 6000 {
            let (element, depth) = queue.removeFirst()
            visited += 1
            let role = string(element, kAXRoleAttribute)
            let subrole = string(element, kAXSubroleAttribute)
            if subrole == "AXTabButton" || role == kAXRadioButtonRole as String || role == "AXTab" {
                let title = string(element, kAXTitleAttribute) ?? string(element, kAXDescriptionAttribute) ?? ""
                if !title.isEmpty { found.append((element, title)) }
                continue
            }
            // Web content is huge and never contains the tab strip.
            if role == "AXWebArea" || depth > 22 { continue }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
                let kids = children as? [AXUIElement]
            {
                queue.append(contentsOf: kids.map { ($0, depth + 1) })
            }
        }
        return found
    }

    static func dump(_ element: AXUIElement, depth: Int = 0) {
        guard depth < 18 else { return }
        let role = string(element, kAXRoleAttribute) ?? ""
        print(String(repeating: "  ", count: depth) + "\(role) [\(string(element, kAXSubroleAttribute) ?? "")] t=\(string(element, kAXTitleAttribute) ?? "") d=\(string(element, kAXDescriptionAttribute) ?? "") v=\((string(element, kAXValueAttribute) ?? "").prefix(40))")
        if role == "AXWebArea" { return }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        for kid in children as? [AXUIElement] ?? [] { dump(kid, depth: depth + 1) }
    }

    private static func raise(_ window: AXUIElement) {
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    @MainActor private static var askedForAccessibility = false
}

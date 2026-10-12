import Foundation

/// The app used to be called Tether. On first launch as Fokly, carry over its settings and
/// session history so nothing is lost. Runs once.
enum Migration {
    private static let done = "migratedFromTether"
    private static let oldDomain = "app.tether.Tether"

    static func run() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: done) else { return }
        defer { d.set(true, forKey: done) }

        // Settings: copy every key Fokly doesn't have yet (window positions included).
        if let old = d.persistentDomain(forName: oldDomain) {
            let current = d.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
            for (key, value) in old where current[key] == nil { d.set(value, forKey: key) }
        }

        // History: move Application Support/Tether to Application Support/Fokly.
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let from = support.appendingPathComponent("Tether", isDirectory: true)
        let to = support.appendingPathComponent("Fokly", isDirectory: true)
        let toHistory = to.appendingPathComponent("history.json")
        guard fm.fileExists(atPath: from.appendingPathComponent("history.json").path),
            !fm.fileExists(atPath: toHistory.path)
        else { return }
        try? fm.createDirectory(at: to, withIntermediateDirectories: true)
        try? fm.moveItem(at: from.appendingPathComponent("history.json"), to: toHistory)
        try? fm.removeItem(at: from)
    }
}

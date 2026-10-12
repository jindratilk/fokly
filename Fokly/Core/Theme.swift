import AppKit
import SwiftUI

/// Design tokens. One warm accent for focus, a cool one for rest, amber for drift.
enum Theme {
    static let defaultFocusNS = NSColor(srgbRed: 0.98, green: 0.40, blue: 0.32, alpha: 1)

    /// The user's accent (Settings → Accent color), defaulting to warm coral.
    static var focusNS: NSColor {
        Prefs.d.string(forKey: Prefs.accentHex).flatMap(NSColor.init(hex:)) ?? defaultFocusNS
    }
    static let restNS = NSColor(srgbRed: 0.19, green: 0.76, blue: 0.62, alpha: 1)
    static let driftNS = NSColor(srgbRed: 1.00, green: 0.68, blue: 0.18, alpha: 1)

    static var focus: Color { Color(nsColor: focusNS) }
    static let rest = Color(nsColor: restNS)
    static let drift = Color(nsColor: driftNS)

    static let popoverWidth: CGFloat = 340
    static let corner: CGFloat = 18
}

extension Font {
    /// Rounded, tabular digits so the clock never jitters.
    static func clock(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

enum Clock {
    static func string(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func minutes(_ interval: TimeInterval) -> String {
        let m = Int(interval / 60)
        if m < 60 { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min"
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}

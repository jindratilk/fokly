import AppKit
import SwiftUI

/// Borderless, non-activating glass panel that hosts SwiftUI.
/// It never steals focus from the app the user is working in.
protocol Unconstrainable: AnyObject { var unconstrained: Bool { get set } }

final class FloatingPanel<Content: View>: NSPanel, Unconstrainable {
    init(movable: Bool, @ViewBuilder content: () -> Content) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false  // the glass draws its own
        isMovableByWindowBackground = movable
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .utilityWindow

        let host = NSHostingView(rootView: content())
        host.sizingOptions = [.intrinsicContentSize]
        contentView = host
        setContentSize(host.fittingSize)
    }

    /// Normally a window can't move above the menu bar; the tour's flight into it needs to.
    var unconstrained = false
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        unconstrained ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

extension NSScreen {
    /// The screen with the menu bar the user is looking at.
    static var active: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? main
    }
}

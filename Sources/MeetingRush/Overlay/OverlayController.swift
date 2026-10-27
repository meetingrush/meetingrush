import AppKit
import MeetingRushCore
import SwiftUI

struct OverlayActions {
    /// Nil when the meeting has no join link.
    let join: (() -> Void)?
    let snooze: (Date) -> Void
    let dismiss: () -> Void
}

/// Covers every screen, including full-screen apps on other Spaces, with the meeting alert.
@MainActor
final class OverlayController {
    private var panels: [NSPanel] = []

    func show(_ meeting: Meeting, actions: OverlayActions) {
        hide()
        let screens = NSScreen.screens.sorted { lhs, _ in lhs == NSScreen.main }
        panels = screens.map { screen in
            // Non-activating, so the alert takes keyboard focus even when macOS declines to activate the app,
            // which it does while the user is working in another app.
            let panel = OverlayPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            // Panels hide when their app deactivates by default, which would drop the alert on the first click elsewhere.
            panel.hidesOnDeactivate = false
            panel.contentView = NSHostingView(rootView: OverlayView(meeting: meeting, actions: actions))
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            return panel
        }
        panels.first?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panels.forEach { $0.close() }
        panels = []
    }
}

/// Borderless panels refuse key status by default, which would leave the keyboard shortcuts dead.
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

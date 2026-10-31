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
    private var shown: (meeting: Meeting, actions: OverlayActions)?
    private var screenObserver: NSObjectProtocol?
    /// Screen frames the panels were built for, main screen first.
    private var screenFrames: [CGRect] = []

    func show(_ meeting: Meeting, actions: OverlayActions) {
        shown = (meeting, actions)
        buildPanels()
        // A panel keeps its old frame when its display goes away or changes resolution, cutting the alert off.
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refitPanels() }
            }
        }
    }

    func hide() {
        closePanels()
        shown = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
    }

    /// Rebuilds only when the screens really changed, as macOS posts the notification several times per change.
    private func refitPanels() {
        guard Self.sortedScreens().map(\.frame) != screenFrames else { return }
        buildPanels()
    }

    private static func sortedScreens() -> [NSScreen] {
        NSScreen.screens.sorted { lhs, _ in lhs == NSScreen.main }
    }

    /// Covers each current screen with a fresh panel, the key one on the main screen.
    private func buildPanels() {
        guard let (meeting, actions) = shown else { return }
        closePanels()
        let screens = Self.sortedScreens()
        screenFrames = screens.map(\.frame)
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

    private func closePanels() {
        panels.forEach { $0.close() }
        panels = []
    }
}

/// Borderless panels refuse key status by default, which would leave the keyboard shortcuts dead.
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(rootView: SettingsView) {
        window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
        window.title = "MeetingRush Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("Settings")
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

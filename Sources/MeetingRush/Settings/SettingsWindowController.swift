import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let window: NSPanel

    init(rootView: SettingsView) {
        // A non-activating panel takes keyboard focus even when macOS declines to activate the app, which it does
        // while another app is in front; a normal window would open unfocused, with its fields greyed out.
        window = NSPanel(contentRect: .zero, styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        let content = NSHostingController(rootView: rootView)
        window.contentViewController = content
        window.title = "MeetingRush Settings"
        // Keeps Settings up while the user signs in to Google in the browser.
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        // Without activation macOS won't switch Spaces, so Settings must come to the user's Space, full screen included.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // The hosting controller sizes the panel only later, so centring an unsized panel would put its corner at the centre.
        window.setContentSize(content.view.fittingSize)
        window.center()
        window.setFrameAutosaveName("Settings")
    }

    /// Opens Settings in front with keyboard focus, for when the user asked for it.
    func show() {
        // makeKeyAndOrderFront can leave a non-activating panel key but behind the frontmost app's window.
        window.orderFrontRegardless()
        window.makeKey()
    }

    /// Brings Settings back into view, if it's still open, without taking keyboard focus from the app the user is typing in.
    func bringToFront() {
        guard window.isVisible else { return }
        // Clears the focused field, so a later click on the title bar can't make the client secret the typing target.
        window.makeFirstResponder(nil)
        window.orderFrontRegardless()
    }
}

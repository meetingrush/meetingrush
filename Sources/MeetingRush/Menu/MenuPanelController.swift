import AppKit
import SwiftUI

/// The menu bar icon and the agenda panel it opens.
///
/// A hand-rolled panel rather than `MenuBarExtra(.window)`: SwiftUI offers no way to close that window
/// from code, and its corner radius can't be changed to match other windows.
@MainActor
final class MenuPanelController: NSObject {
    private static let cornerRadius: CGFloat = 16
    private static let gapBelowMenuBar: CGFloat = 6
    private static let screenMargin: CGFloat = 8

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel = MenuPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var anchor = NSPoint.zero
    private var eventMonitors: [Any] = []

    init(coordinator: AppCoordinator, openSettings: @escaping () -> Void) {
        super.init()

        if let button = statusItem.button {
            button.image = AppImages.logo
            button.target = self
            button.action = #selector(toggle)
        }

        panel.level = .popUpMenu
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        // A layer corner radius doesn't clip behind-window blur; a mask image does.
        background.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.autoresizingMask = [.width, .height]
        background.addSubview(hostingView)
        panel.contentView = background

        hostingView.rootView = AnyView(
            MenuContent(
                coordinator: coordinator,
                state: AgendaState(),
                close: { [weak self] in self?.close() },
                openSettings: openSettings
            )
            .environment(\.openURL, OpenURLAction { [weak self] url in
                self?.close()
                return .systemAction(url)
            })
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { [weak self] size in
                self?.layout(size: size)
            }
        )
    }

    @objc private func toggle() {
        if panel.isVisible {
            close()
        } else {
            open()
        }
    }

    private func open() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let itemFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        anchor = NSPoint(x: itemFrame.minX, y: itemFrame.minY - Self.gapBelowMenuBar)
        layout(size: hostingView.intrinsicContentSize)
        panel.makeKeyAndOrderFront(nil)
        button.highlight(true)

        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) {
            eventMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event } // Esc
            MainActor.assumeIsolated { self?.close() }
            return nil
        }) {
            eventMonitors.append(monitor)
        }
    }

    private func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors = []
    }

    /// Keeps the panel's top edge under the menu bar icon as its content grows or shrinks.
    private func layout(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let visible = (statusItem.button?.window?.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let x = min(max(anchor.x, visible.minX + Self.screenMargin), visible.maxX - size.width - Self.screenMargin)
        panel.setFrame(NSRect(x: x, y: anchor.y - size.height, width: size.width, height: size.height), display: true)
        panel.invalidateShadow()
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Borderless panels refuse key status by default, which would disable text selection and keyboard shortcuts.
private final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

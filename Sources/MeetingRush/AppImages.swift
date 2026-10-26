import AppKit

enum AppImages {
    /// The running-figure logo as a template image, so it takes the menu bar's or the view's foreground colour.
    /// Falls back to an SF Symbol when run outside the app bundle, e.g. with `swift run`.
    static let logo: NSImage = {
        let image = Bundle.main.image(forResource: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "figure.run", accessibilityDescription: nil)
            ?? NSImage()
        image.isTemplate = true
        image.accessibilityDescription = "MeetingRush"
        return image
    }()
}

import AppKit

@main
@MainActor
enum MeetingRushApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = AppCoordinator(providers: [EventKitCalendarProvider()])
    private var settingsWindow: SettingsWindowController?
    private var menuPanel: MenuPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsKey.registerDefaults()
        let settingsWindow = SettingsWindowController(rootView: SettingsView(coordinator: coordinator, loginItem: LoginItem()))
        self.settingsWindow = settingsWindow
        menuPanel = MenuPanelController(coordinator: coordinator, openSettings: settingsWindow.show)
        Task { await coordinator.start() }
    }
}

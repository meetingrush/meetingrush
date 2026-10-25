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
    private var appNapActivity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // With no visible windows the app qualifies for App Nap, which throttles the alert timers
        // so far that an alert can fire after the meeting has started, or not at all.
        appNapActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Meeting alerts must fire on time"
        )
        SettingsKey.registerDefaults()
        let settingsWindow = SettingsWindowController(rootView: SettingsView(coordinator: coordinator, loginItem: LoginItem()))
        self.settingsWindow = settingsWindow
        menuPanel = MenuPanelController(coordinator: coordinator, openSettings: settingsWindow.show)
        Task { await coordinator.start() }
    }
}

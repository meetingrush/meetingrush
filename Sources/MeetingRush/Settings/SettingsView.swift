import AppKit
import MeetingRushCore
import Observation
import ServiceManagement
import SwiftUI

// No @State, @Entry or @Previewable in this target: they are macros whose plugin the Command Line Tools lack,
// so a Homebrew build from source would fail. @Observable models and @AppStorage are fine.

/// Which Settings page is showing; nil is the main page.
@MainActor
@Observable
final class SettingsNavigation {
    enum Page {
        case appleCalendar, googleCalendar
    }

    var page: Page?

    func show(_ page: Page?) {
        withAnimation(.snappy(duration: 0.25)) {
            self.page = page
        }
    }
}

struct SettingsView: View {
    let coordinator: AppCoordinator
    let google: GoogleCalendarProvider
    let loginItem: LoginItem
    let navigation = SettingsNavigation()

    var body: some View {
        ZStack {
            switch navigation.page {
            case nil:
                GeneralSettings(coordinator: coordinator, google: google, loginItem: loginItem, navigation: navigation)
                    .transition(.move(edge: .leading))
            case .appleCalendar:
                SettingsSubpage(title: "Apple Calendar", back: { navigation.show(nil) }) {
                    AppleCalendarSettings(coordinator: coordinator)
                }
                .transition(.move(edge: .trailing))
            case .googleCalendar:
                SettingsSubpage(title: "Google Calendar", back: { navigation.show(nil) }) {
                    GoogleCalendarSettings(coordinator: coordinator, google: google)
                }
                .transition(.move(edge: .trailing))
            }
        }
        .frame(width: 460, height: 580)
        .clipped()
    }
}

private struct GeneralSettings: View {
    let coordinator: AppCoordinator
    let google: GoogleCalendarProvider
    let loginItem: LoginItem
    let navigation: SettingsNavigation
    @AppStorage(SettingsKey.leadTimeMinutes) private var leadTimeMinutes = 1
    @AppStorage(SettingsKey.includeAllDayEvents) private var includeAllDayEvents = false

    var body: some View {
        Form {
            Section("Alerts") {
                Picker("Alert", selection: $leadTimeMinutes) {
                    Text("When the meeting starts").tag(0)
                    ForEach([1, 2, 5, 10], id: \.self) { minutes in
                        Text("\(minutes) min before").tag(minutes)
                    }
                }
                Toggle("Alert for all-day events", isOn: $includeAllDayEvents)
            }

            Section("Calendars") {
                SourceRow(
                    title: "Apple Calendar",
                    subtitle: appleSubtitle,
                    icon: Image(nsImage: NSWorkspace.shared.icon(forFile: "/System/Applications/Calendar.app"))
                ) {
                    navigation.show(.appleCalendar)
                }
                SourceRow(
                    title: "Google Calendar",
                    subtitle: googleSubtitle,
                    icon: Image(systemName: "g.circle.fill")
                ) {
                    navigation.show(.googleCalendar)
                }
            }

            Section {
                Toggle("Launch at login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
            }
        }
        .formStyle(.grouped)
    }

    private var appleSubtitle: String {
        guard coordinator.providersWithAccess.contains(EventKitCalendarProvider.sourceID) else { return "No access" }
        return countText(source: EventKitCalendarProvider.sourceID)
    }

    private var googleSubtitle: String {
        switch google.accounts.count {
        case 0: "Not connected"
        case 1: "1 account · \(countText(source: GoogleCalendarProvider.sourceID))"
        case let count: "\(count) accounts · \(countText(source: GoogleCalendarProvider.sourceID))"
        }
    }

    private func countText(source: String) -> String {
        let calendars = coordinator.calendars.filter { $0.source == source }
        return "\(calendars.filter(coordinator.isEnabled).count) of \(calendars.count) calendars"
    }
}

/// A navigation row in the style of System Settings: icon, title, status, chevron.
private struct SourceRow: View {
    let title: String
    let subtitle: String
    let icon: Image
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.blue)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A page that slides in over the main Settings page, with a back button to return.
private struct SettingsSubpage<Content: View>: View {
    let title: String
    let back: () -> Void
    let content: Content

    init(title: String, back: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.back = back
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: back) {
                Label("Settings", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("[", modifiers: .command)
            .padding(.horizontal, 20)
            .padding(.top, 14)

            Text(title)
                .font(.title2.bold())
                .padding(.horizontal, 20)
                .padding(.top, 8)

            content
        }
    }
}

/// A section footer note. Grouped forms align footers to the trailing edge, which leaves the last line of a
/// wrapped note hanging on the right.
struct SectionNote: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Checkboxes for choosing which of `calendars` alert.
struct CalendarChecklist: View {
    let calendars: [CalendarInfo]
    let coordinator: AppCoordinator

    var body: some View {
        ForEach(calendars) { calendar in
            Toggle(isOn: Binding(get: { coordinator.isEnabled(calendar) }, set: { coordinator.setEnabled(calendar, $0) })) {
                Label {
                    Text(calendar.title)
                } icon: {
                    Circle()
                        .fill(calendar.color?.swiftUIColor ?? .secondary)
                        .frame(width: 10, height: 10)
                }
            }
            .toggleStyle(.checkbox)
        }
    }
}

@MainActor
@Observable
final class LoginItem {
    private(set) var isEnabled = SMAppService.mainApp.status == .enabled

    func setEnabled(_ enabled: Bool) {
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}

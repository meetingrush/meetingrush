import MeetingRushCore
import Observation
import ServiceManagement
import SwiftUI

// No @State, @Entry or @Previewable in this target: they are macros whose plugin the Command Line Tools lack,
// so a Homebrew build from source would fail. @Observable models and @AppStorage are fine.
struct SettingsView: View {
    let coordinator: AppCoordinator
    let loginItem: LoginItem
    @AppStorage(SettingsKey.leadTimeMinutes) private var leadTimeMinutes = 1
    @AppStorage(SettingsKey.includeAllDayEvents) private var includeAllDayEvents = false

    var body: some View {
        Form {
            Section {
                Picker("Alert", selection: $leadTimeMinutes) {
                    Text("When the meeting starts").tag(0)
                    ForEach([1, 2, 5, 10], id: \.self) { minutes in
                        Text("\(minutes) min before").tag(minutes)
                    }
                }
                Toggle("Alert for all-day events", isOn: $includeAllDayEvents)
                Toggle("Launch at login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
            }

            ForEach(accounts, id: \.self) { account in
                Section {
                    ForEach(coordinator.calendars.filter { $0.account == account }) { calendar in
                        Toggle(isOn: Binding(
                            get: { coordinator.isEnabled(calendar) },
                            set: { coordinator.setEnabled(calendar, $0) }
                        )) {
                            Label {
                                Text(calendar.title)
                            } icon: {
                                Circle()
                                    .fill(calendar.color.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? .secondary)
                                    .frame(width: 10, height: 10)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                } header: {
                    Text(account == accounts.first ? "Calendars · \(account)" : account)
                } footer: {
                    if account == accounts.last {
                        Text("Meetings in unticked calendars don't alert or appear in the menu.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 560)
    }

    private var accounts: [String] {
        coordinator.calendars.map(\.account).reduce(into: []) { result, account in
            if result.last != account { result.append(account) }
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

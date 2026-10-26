import AppKit
import MeetingRushCore
import SwiftUI

struct AppleCalendarSettings: View {
    let coordinator: AppCoordinator

    var body: some View {
        Form {
            if !coordinator.providersWithAccess.contains(EventKitCalendarProvider.sourceID) {
                Section {
                    Text("MeetingRush can't read Calendar.app. Allow access in System Settings, then come back here.")
                    Button("Open Privacy & Security…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                    }
                }
            }

            ForEach(accounts, id: \.self) { account in
                Section {
                    CalendarChecklist(calendars: calendars.filter { $0.account == account }, coordinator: coordinator)
                } header: {
                    Text(account)
                } footer: {
                    if account == accounts.last {
                        Text("Unticked calendars don't alert or appear in the menu. If an account is also connected in Google Calendar, each meeting still alerts once.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var calendars: [CalendarInfo] {
        coordinator.calendars.filter { $0.source == EventKitCalendarProvider.sourceID }
    }

    private var accounts: [String] {
        calendars.map(\.account).reduce(into: []) { result, account in
            if !result.contains(account) { result.append(account) }
        }
    }
}

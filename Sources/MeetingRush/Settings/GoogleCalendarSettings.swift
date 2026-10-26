import MeetingRushCore
import SwiftUI

struct GoogleCalendarSettings: View {
    let coordinator: AppCoordinator
    let google: GoogleCalendarProvider

    var body: some View {
        Form {
            Section {
                TextField("Client ID", text: Binding(get: { google.clientID }, set: { google.clientID = $0 }))
                SecureField("Client secret", text: Binding(get: { google.clientSecret }, set: { google.clientSecret = $0 }))
            } header: {
                Text("OAuth client")
            } footer: {
                Text("Use a Desktop app OAuth client from your own Google Cloud project. [Setup guide](https://github.com/meetingrush/meetingrush#google-calendar)")
                    .foregroundStyle(.secondary)
            }

            Section("Accounts") {
                ForEach(google.accounts, id: \.self) { account in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account)
                            if let error = google.accountErrors[account] {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        Button("Remove") { google.remove(account) }
                    }
                }

                if google.isConnecting {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Finish signing in in your browser…")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { google.cancelConnect() }
                    }
                } else {
                    Button("Connect Google Account…") { google.connect() }
                        .disabled(!google.canConnect)
                }

                if let error = google.connectError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            ForEach(google.accounts, id: \.self) { account in
                let calendars = coordinator.calendars.filter { $0.source == GoogleCalendarProvider.sourceID && $0.account == account }
                if !calendars.isEmpty {
                    Section(account) {
                        CalendarChecklist(calendars: calendars, coordinator: coordinator)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

import MeetingRushCore
import SwiftUI

struct OverlayView: View {
    let meeting: Meeting
    let actions: OverlayActions

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThickMaterial)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(startsText)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }

                Text(meeting.title)
                    .font(.system(size: 56, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                Text(details)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    if let join = actions.join, let service = meeting.joinLink?.service {
                        Button("Join \(service.rawValue)", action: join)
                            .keyboardShortcut(.defaultAction)
                    }

                    Menu("Snooze 1 min") {
                        Button("5 minutes") { actions.snooze(.now + 5 * 60) }
                        if meeting.start > .now + 60 {
                            Button("Until it starts") { actions.snooze(meeting.start) }
                        }
                    } primaryAction: {
                        actions.snooze(.now + 60)
                    }
                    .fixedSize()

                    Button("Dismiss", action: actions.dismiss)
                        .keyboardShortcut(.cancelAction)
                }
                .controlSize(.extraLarge)
                .padding(.top, 24)
            }
            .padding(48)
            .frame(maxWidth: 900)
        }
    }

    private var startsText: String {
        let relative = meeting.start.formatted(.relative(presentation: .named))
        return meeting.start > .now ? "Starts \(relative)" : "Started \(relative)"
    }

    private var details: String {
        let time = "\(meeting.start.formatted(date: .omitted, time: .shortened)) – \(meeting.end.formatted(date: .omitted, time: .shortened))"
        return [time, meeting.location, meeting.calendarName]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: "  ·  ")
    }
}

import MeetingRushCore
import SwiftUI

struct MeetingDetails: View {
    let meeting: Meeting

    private static let attendeeLimit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("clock", timeRange)
            if let location = meeting.location, !location.isEmpty, location != meeting.joinLink?.url.absoluteString {
                row("mappin.and.ellipse", location)
            }
            row("calendar", meeting.calendarName)
            if let organizer = meeting.organizer {
                row("person.crop.circle", "Organiser: \(organizer.name)")
            }

            if !attendees.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(attendees.prefix(Self.attendeeLimit), id: \.self) { attendee in
                        Label {
                            Text(attendee.isCurrentUser ? "\(attendee.name) (you)" : attendee.name)
                                .lineLimit(1)
                        } icon: {
                            Self.statusIcon(attendee.status)
                        }
                        .help(attendee.email ?? attendee.name)
                    }
                    if attendees.count > Self.attendeeLimit {
                        Text("+\(attendees.count - Self.attendeeLimit) more")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)
            }

            if !notes.isEmpty {
                Text(NotesFormatter.linkified(notes))
                    .foregroundStyle(.secondary)
                    .lineLimit(12)
                    .textSelection(.enabled)
                    .padding(.top, 4)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeRange: String {
        let start = meeting.start.formatted(date: .omitted, time: .shortened)
        let end = meeting.end.formatted(date: .omitted, time: .shortened)
        let duration = Duration.seconds(meeting.end.timeIntervalSince(meeting.start))
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        return "\(start) – \(end) (\(duration))"
    }

    /// Accepted first, declined last, so the people expected to turn up lead the list.
    private var attendees: [Participant] {
        let order: [Participant.Status] = [.accepted, .tentative, .pending, .declined]
        return meeting.attendees.sorted {
            (order.firstIndex(of: $0.status) ?? 0, $0.name) < (order.firstIndex(of: $1.status) ?? 0, $1.name)
        }
    }

    private var notes: String {
        meeting.notes.map(NotesFormatter.plainText) ?? ""
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
                .textSelection(.enabled)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
        }
    }

    private static func statusIcon(_ status: Participant.Status) -> some View {
        let (symbol, color): (String, Color) = switch status {
        case .accepted: ("checkmark.circle.fill", .green)
        case .tentative: ("questionmark.circle.fill", .orange)
        case .declined: ("xmark.circle.fill", .red)
        case .pending: ("circle", .secondary)
        }
        return Image(systemName: symbol).foregroundStyle(color)
    }
}

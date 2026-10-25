import Foundation

/// The meetings starting on one day.
public struct AgendaDay: Identifiable, Hashable, Sendable {
    /// Midnight at the start of the day.
    public let date: Date
    public let meetings: [Meeting]

    public var id: Date { date }
}

public enum Agenda {
    /// Groups meetings by the day they start, in order. Meetings already under way at `now` go under today.
    public static func days(for meetings: [Meeting], now: Date, calendar: Calendar = .current) -> [AgendaDay] {
        var days: [AgendaDay] = []
        for meeting in meetings.sorted(by: { $0.start < $1.start }) {
            let date = calendar.startOfDay(for: max(meeting.start, now))
            if let last = days.last, last.date == date {
                days[days.count - 1] = AgendaDay(date: date, meetings: last.meetings + [meeting])
            } else {
                days.append(AgendaDay(date: date, meetings: [meeting]))
            }
        }
        return days
    }
}

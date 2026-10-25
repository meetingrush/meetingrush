import Foundation
import Testing
@testable import MeetingRushCore

struct AgendaTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Adelaide")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func meeting(_ id: String, start: Date, minutes: Double = 30) -> Meeting {
        Meeting(id: id, title: id, start: start, end: start + minutes * 60, calendarID: "work", calendarName: "Work")
    }

    @Test func groupsMeetingsByStartDayInOrder() {
        let meetings = [
            meeting("tue", start: date(27, 9)),
            meeting("mon-late", start: date(26, 15)),
            meeting("mon-early", start: date(26, 9)),
        ]
        let days = Agenda.days(for: meetings, now: date(26, 8), calendar: calendar)
        #expect(days.map(\.date) == [date(26, 0), date(27, 0)])
        #expect(days.map { $0.meetings.map(\.id) } == [["mon-early", "mon-late"], ["tue"]])
    }

    @Test func listsMeetingUnderWayUnderToday() {
        let overnight = meeting("overnight", start: date(25, 23), minutes: 120)
        let days = Agenda.days(for: [overnight], now: date(26, 0, 30), calendar: calendar)
        #expect(days.map(\.date) == [date(26, 0)])
    }
}

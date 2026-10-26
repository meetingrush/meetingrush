import Foundation
import Testing
@testable import MeetingRushCore

struct GoogleCalendarAPITests {
    private let calendar = CalendarInfo(id: "google:me@example.com:work", title: "Work", account: "me@example.com", color: nil, source: "google")

    private func event(_ json: String) throws -> GoogleCalendarAPI.Event {
        try JSONDecoder().decode(GoogleCalendarAPI.Event.self, from: Data(json.utf8))
    }

    @Test func mapsATimedEventWithMeetLinkAndAttendees() throws {
        let meeting = try #require(try event("""
        {
          "id": "abc_20261026T231500Z", "iCalUID": "abc@google.com", "status": "confirmed",
          "summary": "Stand-up", "description": "<b>Daily</b> sync", "location": "Room 2",
          "start": {"dateTime": "2026-10-27T09:45:00+10:30"}, "end": {"dateTime": "2026-10-27T10:00:00+10:30"},
          "hangoutLink": "https://meet.google.com/abc-defg-hij",
          "organizer": {"email": "lead@example.com", "displayName": "Lead"},
          "attendees": [
            {"email": "lead@example.com", "displayName": "Lead", "responseStatus": "accepted", "organizer": true},
            {"email": "me@example.com", "responseStatus": "accepted", "self": true},
            {"email": "dev@example.com", "displayName": "Dev", "responseStatus": "tentative"}
          ]
        }
        """).meeting(in: calendar))

        #expect(meeting.title == "Stand-up")
        #expect(meeting.start == Date(timeIntervalSince1970: 1_793_056_500))
        #expect(meeting.end.timeIntervalSince(meeting.start) == 15 * 60)
        #expect(!meeting.isAllDay)
        #expect(meeting.calendarID == calendar.id)
        #expect(meeting.externalID == "abc@google.com")
        #expect(meeting.joinLink == MeetingLink(service: .googleMeet, url: URL(string: "https://meet.google.com/abc-defg-hij")!))
        #expect(meeting.organizer?.name == "Lead")
        #expect(meeting.attendees.map(\.name) == ["me@example.com", "Dev"])
        #expect(meeting.attendees.map(\.status) == [.accepted, .tentative])
        #expect(meeting.attendees.first?.isCurrentUser == true)
    }

    @Test func readsAllDayDatesInTheGivenTimeZone() throws {
        let adelaide = TimeZone(identifier: "Australia/Adelaide")!
        let meeting = try #require(try event("""
        {"id": "d", "summary": "Offsite", "start": {"date": "2026-10-27"}, "end": {"date": "2026-10-28"}}
        """).meeting(in: calendar, timeZone: adelaide))
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = adelaide
        #expect(meeting.isAllDay)
        #expect(meeting.start == gregorian.date(from: DateComponents(year: 2026, month: 10, day: 27)))
    }

    @Test func skipsCancelledAndDeclinedEvents() throws {
        let cancelled = try event("""
        {"id": "c", "status": "cancelled", "start": {"dateTime": "2026-10-27T09:00:00Z"}, "end": {"dateTime": "2026-10-27T10:00:00Z"}}
        """)
        let declined = try event("""
        {"id": "d", "start": {"dateTime": "2026-10-27T09:00:00Z"}, "end": {"dateTime": "2026-10-27T10:00:00Z"},
         "attendees": [{"email": "me@example.com", "responseStatus": "declined", "self": true}]}
        """)
        #expect(cancelled.meeting(in: calendar) == nil)
        #expect(declined.meeting(in: calendar) == nil)
    }

    @Test func fallsBackToConferenceEntryPointsAndNotes() throws {
        let zoom = try event("""
        {"id": "z", "start": {"dateTime": "2026-10-27T09:00:00Z"}, "end": {"dateTime": "2026-10-27T10:00:00Z"},
         "conferenceData": {"entryPoints": [{"entryPointType": "phone", "uri": "tel:+61-2-1234"},
                                            {"entryPointType": "video", "uri": "https://us02web.zoom.us/j/123"}]}}
        """).meeting(in: calendar)
        #expect(zoom?.joinLink?.service == .zoom)

        let teams = try event("""
        {"id": "t", "description": "Join https://teams.microsoft.com/l/meetup-join/abc",
         "start": {"dateTime": "2026-10-27T09:00:00Z"}, "end": {"dateTime": "2026-10-27T10:00:00Z"}}
        """).meeting(in: calendar)
        #expect(teams?.joinLink?.service == .teams)
    }

    @Test func escapesCalendarIDsInEventsURL() {
        let url = GoogleCalendarAPI.eventsURL(
            calendarID: "en.australian#holiday@group.v.calendar.google.com",
            from: Date(timeIntervalSince1970: 0),
            to: Date(timeIntervalSince1970: 86400)
        )
        #expect(url.absoluteString.hasPrefix(
            "https://www.googleapis.com/calendar/v3/calendars/en.australian%23holiday%40group.v.calendar.google.com/events?"
        ))
        #expect(url.query?.contains("timeMin=1970-01-01T00:00:00Z") == true)
        #expect(url.query?.contains("singleEvents=true") == true)
    }

    @Test func parsesHexColours() {
        #expect(CalendarInfo.Color(hex: "#ff8000") == CalendarInfo.Color(red: 1, green: 128.0 / 255, blue: 0))
        #expect(CalendarInfo.Color(hex: "nope") == nil)
    }
}

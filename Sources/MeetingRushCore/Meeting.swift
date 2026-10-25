import Foundation

/// One occurrence of a calendar event, independent of the calendar it came from.
public struct Meeting: Identifiable, Hashable, Sendable {
    /// Unique per occurrence, so each instance of a recurring event alerts separately.
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let calendarID: CalendarInfo.ID
    public let calendarName: String
    public let location: String?
    public let joinLink: MeetingLink?
    /// The event description as the calendar stores it, which may be HTML.
    public let notes: String?
    public let organizer: Participant?
    /// Invitees other than the organiser.
    public let attendees: [Participant]

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        calendarID: CalendarInfo.ID,
        calendarName: String,
        location: String? = nil,
        joinLink: MeetingLink? = nil,
        notes: String? = nil,
        organizer: Participant? = nil,
        attendees: [Participant] = []
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarID = calendarID
        self.calendarName = calendarName
        self.location = location
        self.joinLink = joinLink
        self.notes = notes
        self.organizer = organizer
        self.attendees = attendees
    }
}

public struct Participant: Hashable, Sendable {
    public enum Status: Sendable {
        case accepted, tentative, declined, pending
    }

    public let name: String
    public let email: String?
    public let status: Status
    public let isCurrentUser: Bool

    public init(name: String, email: String?, status: Status, isCurrentUser: Bool = false) {
        self.name = name
        self.email = email
        self.status = status
        self.isCurrentUser = isCurrentUser
    }
}

/// A link that joins an online meeting.
public struct MeetingLink: Hashable, Sendable {
    public enum Service: String, Sendable {
        case googleMeet = "Google Meet"
        case teams = "Teams"
        case zoom = "Zoom"
    }

    public let service: Service
    public let url: URL

    public init(service: Service, url: URL) {
        self.service = service
        self.url = url
    }

    /// A URL that opens the service's desktop app directly, or nil where `url` should be opened as is.
    public var appURL: URL? {
        guard service == .teams, url.scheme == "https" else { return nil }
        return URL(string: "msteams" + url.absoluteString.dropFirst("https".count))
    }
}

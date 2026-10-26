import Foundation

/// The parts of the Google Calendar API v3 that MeetingRush reads.
public enum GoogleCalendarAPI {
    public static func calendarListURL(pageToken: String? = nil) -> URL {
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
        components.queryItems = [
            URLQueryItem(name: "fields", value: "items(id,summary,summaryOverride,backgroundColor,primary,selected),nextPageToken"),
        ] + (pageToken.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
        return components.url!
    }

    /// Lists the single occurrences of every event in `calendarID` overlapping `start..<end`.
    public static func eventsURL(calendarID: String, from start: Date, to end: Date, pageToken: String? = nil) -> URL {
        // Calendar IDs are email-like and some contain `#`, so everything outside the unreserved set is escaped.
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encodedID = calendarID.addingPercentEncoding(withAllowedCharacters: unreserved) ?? calendarID
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedID)/events")!
        let fields = "items(id,iCalUID,status,summary,description,location,start,end,hangoutLink,"
            + "conferenceData(entryPoints(entryPointType,uri)),attendees(email,displayName,responseStatus,self,organizer),"
            + "organizer(email,displayName,self)),nextPageToken"
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: start.formatted(.iso8601)),
            URLQueryItem(name: "timeMax", value: end.formatted(.iso8601)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "250"),
            URLQueryItem(name: "fields", value: fields),
        ] + (pageToken.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
        return components.url!
    }

    public struct CalendarList: Decodable, Sendable {
        public let items: [CalendarListEntry]?
        public let nextPageToken: String?
    }

    public struct CalendarListEntry: Decodable, Sendable {
        public let id: String
        public let summary: String?
        public let summaryOverride: String?
        /// `#rrggbb`.
        public let backgroundColor: String?
        public let primary: Bool?
        /// Whether the calendar is shown in the Google Calendar UI.
        public let selected: Bool?
    }

    public struct Events: Decodable, Sendable {
        public let items: [Event]?
        public let nextPageToken: String?
    }

    public struct Event: Decodable, Sendable {
        public struct Time: Decodable, Sendable {
            /// RFC 3339, for timed events.
            public let dateTime: String?
            /// `YYYY-MM-DD`, for all-day events.
            public let date: String?
        }

        public struct Person: Decodable, Sendable {
            public let email: String?
            public let displayName: String?
            /// `needsAction`, `declined`, `tentative` or `accepted`.
            public let responseStatus: String?
            /// Whether this person is the signed-in user.
            public let isSelf: Bool?
            public let organizer: Bool?

            enum CodingKeys: String, CodingKey {
                case email, displayName, responseStatus, organizer
                case isSelf = "self"
            }
        }

        public struct ConferenceData: Decodable, Sendable {
            public struct EntryPoint: Decodable, Sendable {
                /// `video`, `phone`, `sip` or `more`.
                public let entryPointType: String?
                public let uri: String?
            }

            public let entryPoints: [EntryPoint]?
        }

        public let id: String
        public let iCalUID: String?
        /// `confirmed`, `tentative` or `cancelled`.
        public let status: String?
        public let summary: String?
        public let description: String?
        public let location: String?
        public let start: Time
        public let end: Time
        public let hangoutLink: String?
        public let conferenceData: ConferenceData?
        public let attendees: [Person]?
        public let organizer: Person?
    }
}

extension GoogleCalendarAPI.Event {
    /// The meeting this event describes in `calendar`.
    ///
    /// Returns nil for a cancelled event, one the user declined, or one whose times can't be read.
    /// All-day dates are read in `timeZone`.
    public func meeting(in calendar: CalendarInfo, timeZone: TimeZone = .current) -> Meeting? {
        guard status != "cancelled",
              attendees?.first(where: { $0.isSelf == true })?.responseStatus != "declined",
              let start = start.date(in: timeZone),
              let end = end.date(in: timeZone)
        else { return nil }

        return Meeting(
            id: "\(id)@\(start.timeIntervalSince1970)",
            title: summary ?? "Untitled event",
            start: start,
            end: end,
            isAllDay: self.start.dateTime == nil,
            calendarID: calendar.id,
            calendarName: calendar.title,
            location: location,
            joinLink: joinLink,
            notes: description,
            organizer: organizer.map(Participant.init),
            attendees: (attendees ?? []).filter { $0.organizer != true }.map(Participant.init),
            externalID: iCalUID
        )
    }

    private var joinLink: MeetingLink? {
        if let hangoutLink, let url = URL(string: hangoutLink) {
            return MeetingLink(service: .googleMeet, url: url)
        }
        let videoURIs = conferenceData?.entryPoints?.filter { $0.entryPointType == "video" }.map(\.uri) ?? []
        return MeetingLinkDetector.detect(in: videoURIs + [location, description])
    }
}

private extension GoogleCalendarAPI.Event.Time {
    func date(in timeZone: TimeZone) -> Date? {
        if let dateTime {
            return (try? Date(dateTime, strategy: .iso8601))
                ?? (try? Date(dateTime, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        guard let date else { return nil }
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

private extension Participant {
    init(_ person: GoogleCalendarAPI.Event.Person) {
        let status: Status = switch person.responseStatus {
        case "accepted": .accepted
        case "tentative": .tentative
        case "declined": .declined
        default: .pending
        }
        self.init(
            name: person.displayName ?? person.email ?? "Unknown",
            email: person.email,
            status: status,
            isCurrentUser: person.isSelf == true
        )
    }
}

extension CalendarInfo.Color {
    /// Parses `#rrggbb`.
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

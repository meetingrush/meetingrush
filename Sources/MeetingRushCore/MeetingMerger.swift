import Foundation

public enum MeetingMerger {
    /// Drops meetings that are another source's copy of an earlier one in `meetings`.
    ///
    /// Copies share an `externalID` and start time, such as a Google event read both from the Google API
    /// and from a Google account added to Calendar.app. Meetings without an `externalID` are always kept.
    public static func deduplicated(_ meetings: [Meeting]) -> [Meeting] {
        var seen: Set<String> = []
        return meetings.filter { meeting in
            guard let externalID = meeting.externalID else { return true }
            return seen.insert("\(externalID)@\(meeting.start.timeIntervalSince1970)").inserted
        }
    }
}

import Foundation

public struct AlertSettings: Equatable, Sendable {
    /// How long before a meeting starts its alert fires.
    public var leadTime: TimeInterval
    public var includeAllDay: Bool
    /// How long after a meeting starts an unsnoozed alert can still fire, e.g. after the Mac wakes from sleep.
    public var lateGrace: TimeInterval

    public init(leadTime: TimeInterval = 60, includeAllDay: Bool = false, lateGrace: TimeInterval = 10 * 60) {
        self.leadTime = leadTime
        self.includeAllDay = includeAllDay
        self.lateGrace = lateGrace
    }
}

/// Decides which meetings should alert and when, given what the user has dismissed or snoozed.
public struct AlertPlanner: Sendable {
    public var settings: AlertSettings
    private var dismissed: Set<Meeting.ID> = []
    private var snoozedUntil: [Meeting.ID: Date] = [:]

    public init(settings: AlertSettings = AlertSettings()) {
        self.settings = settings
    }

    public mutating func dismiss(_ meeting: Meeting) {
        dismissed.insert(meeting.id)
        snoozedUntil[meeting.id] = nil
    }

    public mutating func snooze(_ meeting: Meeting, until date: Date) {
        snoozedUntil[meeting.id] = date
    }

    /// When `meeting` should alert, or nil if it should not alert at all.
    public func alertDate(for meeting: Meeting) -> Date? {
        guard settings.includeAllDay || !meeting.isAllDay, !dismissed.contains(meeting.id) else {
            return nil
        }
        return snoozedUntil[meeting.id] ?? meeting.start.addingTimeInterval(-settings.leadTime)
    }

    /// The meetings whose alert is due at `now`, earliest start first.
    ///
    /// A snoozed alert stays due until the meeting ends; an unsnoozed one only until `lateGrace` after the start.
    public func dueMeetings(in meetings: [Meeting], at now: Date) -> [Meeting] {
        meetings
            .filter { meeting in
                guard let alertDate = alertDate(for: meeting), alertDate <= now, now < meeting.end else {
                    return false
                }
                return snoozedUntil[meeting.id] != nil || now <= meeting.start.addingTimeInterval(settings.lateGrace)
            }
            .sorted { $0.start < $1.start }
    }

    /// The next moment after `now` that an alert becomes due.
    public func nextAlertDate(in meetings: [Meeting], after now: Date) -> Date? {
        meetings.compactMap(alertDate(for:)).filter { $0 > now }.min()
    }

    /// Forgets dismissals and snoozes for meetings no longer in `meetings`.
    public mutating func retainState(for meetings: [Meeting]) {
        let ids = Set(meetings.map(\.id))
        dismissed.formIntersection(ids)
        snoozedUntil = snoozedUntil.filter { ids.contains($0.key) }
    }
}

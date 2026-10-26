import Foundation
import MeetingRushCore

enum SettingsKey {
    static let leadTimeMinutes = "leadTimeMinutes"
    static let includeAllDayEvents = "includeAllDayEvents"
    /// The calendars the user ticked or unticked, as `[CalendarInfo.ID: Bool]`.
    static let calendarChoices = "calendarChoices"
    /// The unticked calendars, as stored before per-provider defaults existed.
    static let legacyExcludedCalendarIDs = "excludedCalendarIDs"

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [leadTimeMinutes: 1, includeAllDayEvents: false])
    }
}

extension AlertSettings {
    static func load(from defaults: UserDefaults = .standard) -> AlertSettings {
        AlertSettings(
            leadTime: TimeInterval(defaults.integer(forKey: SettingsKey.leadTimeMinutes) * 60),
            includeAllDay: defaults.bool(forKey: SettingsKey.includeAllDayEvents)
        )
    }
}

import Foundation
import MeetingRushCore

enum SettingsKey {
    static let leadTimeMinutes = "leadTimeMinutes"
    static let includeAllDayEvents = "includeAllDayEvents"
    /// Calendars the user unticked. Stored as exclusions so newly added calendars alert by default.
    static let excludedCalendarIDs = "excludedCalendarIDs"

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

/// Which calendars the user wants alerts from.
///
/// A calendar the user hasn't chosen for follows its `enabledByDefault`.
public struct CalendarSelection: Equatable, Sendable {
    public private(set) var choices: [CalendarInfo.ID: Bool]

    public init(choices: [CalendarInfo.ID: Bool] = [:]) {
        self.choices = choices
    }

    public func isEnabled(_ calendar: CalendarInfo) -> Bool {
        choices[calendar.id] ?? calendar.enabledByDefault
    }

    public mutating func set(_ calendar: CalendarInfo, enabled: Bool) {
        choices[calendar.id] = enabled
    }
}

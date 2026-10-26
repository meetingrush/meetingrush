import Testing
@testable import MeetingRushCore

struct CalendarSelectionTests {
    private let shown = CalendarInfo(id: "a", title: "Work", account: "me", color: nil, source: "google", enabledByDefault: true)
    private let hidden = CalendarInfo(id: "b", title: "Holidays", account: "me", color: nil, source: "google", enabledByDefault: false)

    @Test func followsTheProviderDefaultUntilChosen() {
        let selection = CalendarSelection()
        #expect(selection.isEnabled(shown))
        #expect(!selection.isEnabled(hidden))
    }

    @Test func choiceOverridesTheDefault() {
        var selection = CalendarSelection()
        selection.set(shown, enabled: false)
        selection.set(hidden, enabled: true)
        #expect(!selection.isEnabled(shown))
        #expect(selection.isEnabled(hidden))
        #expect(selection.choices == ["a": false, "b": true])
    }
}

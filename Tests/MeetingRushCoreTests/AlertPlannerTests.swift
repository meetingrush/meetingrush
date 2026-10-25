import Foundation
import Testing
@testable import MeetingRushCore

struct AlertPlannerTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func meeting(_ id: String = "m", startOffset: TimeInterval = 0, allDay: Bool = false) -> Meeting {
        Meeting(
            id: id,
            title: id,
            start: start + startOffset,
            end: start + startOffset + 30 * 60,
            isAllDay: allDay,
            calendarID: "work",
            calendarName: "Work"
        )
    }

    @Test func alertsLeadTimeBeforeStart() {
        let planner = AlertPlanner(settings: AlertSettings(leadTime: 60))
        let m = meeting()
        #expect(planner.dueMeetings(in: [m], at: start - 61).isEmpty)
        #expect(planner.dueMeetings(in: [m], at: start - 60) == [m])
        #expect(planner.nextAlertDate(in: [m], after: start - 120) == start - 60)
    }

    @Test func dismissedMeetingNeverAlerts() {
        var planner = AlertPlanner()
        let m = meeting()
        planner.dismiss(m)
        #expect(planner.dueMeetings(in: [m], at: start).isEmpty)
        #expect(planner.nextAlertDate(in: [m], after: start - 3600) == nil)
    }

    @Test func snoozeMovesTheAlert() {
        var planner = AlertPlanner(settings: AlertSettings(leadTime: 60))
        let m = meeting()
        planner.snooze(m, until: start + 120)
        #expect(planner.dueMeetings(in: [m], at: start).isEmpty)
        #expect(planner.nextAlertDate(in: [m], after: start) == start + 120)
        #expect(planner.dueMeetings(in: [m], at: start + 120) == [m])
    }

    @Test func unsnoozedAlertExpiresAfterGraceButSnoozedLastsUntilEnd() {
        var planner = AlertPlanner(settings: AlertSettings(leadTime: 60, lateGrace: 10 * 60))
        let m = meeting()
        #expect(planner.dueMeetings(in: [m], at: start + 11 * 60).isEmpty)

        planner.snooze(m, until: start + 15 * 60)
        #expect(planner.dueMeetings(in: [m], at: start + 20 * 60) == [m])
        #expect(planner.dueMeetings(in: [m], at: start + 30 * 60).isEmpty)
    }

    @Test func skipsAllDayEventsUnlessEnabled() {
        let m = meeting(allDay: true)
        #expect(AlertPlanner().dueMeetings(in: [m], at: start).isEmpty)
        #expect(AlertPlanner(settings: AlertSettings(includeAllDay: true)).dueMeetings(in: [m], at: start) == [m])
    }

    @Test func dueMeetingsAreOrderedByStart() {
        let later = meeting("later", startOffset: 60)
        let earlier = meeting("earlier")
        let planner = AlertPlanner(settings: AlertSettings(leadTime: 5 * 60))
        #expect(planner.dueMeetings(in: [later, earlier], at: start) == [earlier, later])
    }

    @Test func retainStateForgetsMeetingsNoLongerFetched() {
        var planner = AlertPlanner()
        let m = meeting()
        planner.dismiss(m)
        planner.retainState(for: [])
        #expect(planner.dueMeetings(in: [m], at: start) == [m])
    }
}

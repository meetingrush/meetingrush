import Foundation
import Testing
@testable import MeetingRushCore

struct MeetingMergerTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func meeting(_ id: String, externalID: String?, offset: TimeInterval = 0) -> Meeting {
        Meeting(id: id, title: id, start: start + offset, end: start + offset + 1800, calendarID: "c", calendarName: "C", externalID: externalID)
    }

    @Test func keepsTheFirstCopyOfAnEvent() {
        let merged = MeetingMerger.deduplicated([meeting("google", externalID: "uid"), meeting("apple", externalID: "uid")])
        #expect(merged.map(\.id) == ["google"])
    }

    @Test func keepsEachOccurrenceOfARecurringEvent() {
        let merged = MeetingMerger.deduplicated([meeting("mon", externalID: "uid"), meeting("tue", externalID: "uid", offset: 86400)])
        #expect(merged.map(\.id) == ["mon", "tue"])
    }

    @Test func keepsMeetingsWithoutExternalID() {
        let merged = MeetingMerger.deduplicated([meeting("a", externalID: nil), meeting("b", externalID: nil)])
        #expect(merged.map(\.id) == ["a", "b"])
    }
}

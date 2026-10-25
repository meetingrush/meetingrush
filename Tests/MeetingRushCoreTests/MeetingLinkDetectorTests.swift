import Foundation
import Testing
@testable import MeetingRushCore

struct MeetingLinkDetectorTests {
    private let teamsURL = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%3a%22t%22%7d"

    @Test func findsTeamsLinkInNotes() {
        let notes = "Join the meeting now\n<\(teamsURL)>\nMeeting ID: 123"
        let link = MeetingLinkDetector.detect(in: [nil, nil, notes])
        #expect(link == MeetingLink(service: .teams, url: URL(string: teamsURL)!))
    }

    @Test func findsGoogleMeetLinkKeepingTheAccountSelector() {
        let notes = "Join with Google Meet: https://meet.google.com/abc-defg-hij?authuser=1\nOr dial: +61 2 1234 5678"
        let link = MeetingLinkDetector.detect(in: [nil, "Room 4.02", notes])
        #expect(link == MeetingLink(service: .googleMeet, url: URL(string: "https://meet.google.com/abc-defg-hij?authuser=1")!))
    }

    @Test func unescapesLinksFromHtmlNotes() {
        let notes = #"<a href="https://meet.google.com/abc-defg-hij?authuser=0&amp;hs=122">Join</a>"#
        #expect(MeetingLinkDetector.detect(in: [notes])?.url.absoluteString == "https://meet.google.com/abc-defg-hij?authuser=0&hs=122")
    }

    @Test func findsTeamsLiveAndShortMeetLinks() {
        #expect(MeetingLinkDetector.detect(in: ["https://teams.live.com/meet/9876543210"])?.service == .teams)
        #expect(MeetingLinkDetector.detect(in: ["https://teams.microsoft.com/meet/123456?p=abc"])?.service == .teams)
    }

    @Test func unwrapsOutlookSafeLinks() throws {
        let encoded = try #require(teamsURL.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        let notes = "Join: https://aus01.safelinks.protection.outlook.com/?url=\(encoded)&data=05%7C02&reserved=0 now"
        #expect(MeetingLinkDetector.detect(in: [notes])?.url.absoluteString == teamsURL)
    }

    @Test func trimsTrailingPunctuation() {
        let link = MeetingLinkDetector.detect(in: ["(Zoom: https://us02web.zoom.us/j/123456789?pwd=xyz)."])
        #expect(link == MeetingLink(service: .zoom, url: URL(string: "https://us02web.zoom.us/j/123456789?pwd=xyz")!))
    }

    @Test func prefersEarliestLinkWithinAField() {
        let notes = "Dial in via https://meet.google.com/abc-defg-hij or \(teamsURL)"
        #expect(MeetingLinkDetector.detect(in: [notes])?.service == .googleMeet)
    }

    @Test func prefersEarlierFields() {
        let link = MeetingLinkDetector.detect(in: ["https://meet.google.com/abc-defg-hij", "Notes: \(teamsURL)"])
        #expect(link?.service == .googleMeet)
    }

    @Test func returnsNilWithoutMeetingLink() {
        #expect(MeetingLinkDetector.detect(in: ["Room 4.02", "Agenda: https://example.com/doc", nil]) == nil)
    }

    @Test func rewritesTeamsLinksToDesktopScheme() {
        let teams = MeetingLink(service: .teams, url: URL(string: teamsURL)!)
        #expect(teams.appURL?.absoluteString == "msteams" + teamsURL.dropFirst("https".count))

        let meet = MeetingLink(service: .googleMeet, url: URL(string: "https://meet.google.com/abc-defg-hij")!)
        #expect(meet.appURL == nil)
    }
}

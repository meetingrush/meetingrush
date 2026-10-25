import Foundation
import Testing
@testable import MeetingRushCore

struct NotesFormatterTests {
    @Test func stripsHtmlAndDecodesEntities() {
        let html = #"<p>Agenda:<br>1. Q&amp;A</p><p>Join: <a href="https://meet.google.com/abc-defg-hij">meet.google.com/abc-defg-hij</a></p>"#
        #expect(NotesFormatter.plainText(html) == "Agenda:\n1. Q&A\nJoin: meet.google.com/abc-defg-hij")
    }

    @Test func keepsAngleBracketedUrls() {
        let notes = "Join the meeting <https://teams.microsoft.com/l/meetup-join/abc>"
        #expect(NotesFormatter.plainText(notes) == notes)
    }

    @Test func dropsSeparatorLinesAndRepeatedBlankLines() {
        let notes = "Hello\n\n\n-::~:~::~:~:~::-\n________________\n\nBye\n"
        #expect(NotesFormatter.plainText(notes) == "Hello\n\nBye")
    }

    @Test func linksUrlsInText() {
        let text = NotesFormatter.linkified("Agenda: <https://example.com/doc> and https://meet.google.com/abc-defg-hij")
        let links = text.runs.compactMap { run in run.link.map { ($0.absoluteString, String(text[run.range].characters)) } }
        #expect(links.map(\.0) == ["https://example.com/doc", "https://meet.google.com/abc-defg-hij"])
        #expect(links.map(\.1) == ["https://example.com/doc", "https://meet.google.com/abc-defg-hij"])
    }
}

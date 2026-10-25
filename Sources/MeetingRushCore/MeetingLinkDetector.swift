import Foundation

/// Finds online meeting links in free-text event fields.
public enum MeetingLinkDetector {
    /// Returns the first meeting link found, searching `fields` in order.
    ///
    /// Within a field, the link that appears earliest wins.
    public static func detect(in fields: [String?]) -> MeetingLink? {
        for field in fields {
            if let field, let link = firstLink(in: field) {
                return link
            }
        }
        return nil
    }

    static func firstLink(in text: String) -> MeetingLink? {
        let text = unwrappingSafeLinks(in: text)
        let candidates: [(MeetingLink.Service, Range<String.Index>)] = [
            // The query is kept because `authuser` picks which signed-in Google account joins.
            (.googleMeet, text.firstRange(of: #/https://meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}(?:\?[^\s<>"']*)?/#)),
            (.teams, text.firstRange(of: #/https://teams\.(?:microsoft|live)\.com/(?:l/meetup-join|meet)/[^\s<>"']+/#)),
            (.zoom, text.firstRange(of: #/https://(?:[\w-]+\.)?zoom\.us/(?:j|my|w)/[^\s<>"']+/#)),
        ].compactMap { service, range in range.map { (service, $0) } }

        guard let (service, range) = candidates.min(by: { $0.1.lowerBound < $1.1.lowerBound }) else {
            return nil
        }
        // Event notes synced from Google Calendar are HTML, so query separators arrive escaped.
        let raw = text[range]
            .trimmingSuffix { ".,;:!?)]}".contains($0) }
            .replacingOccurrences(of: "&amp;", with: "&")
        return URL(string: raw).map { MeetingLink(service: service, url: $0) }
    }

    /// Replaces Outlook Safe Links redirects with the URL they wrap, which M365 tenants often apply to invite bodies.
    static func unwrappingSafeLinks(in text: String) -> String {
        text.replacing(#/https://[\w.-]+\.safelinks\.protection\.outlook\.com/\?url=([^&\s<>"']+)[^\s<>"']*/#) { match in
            String(match.1).removingPercentEncoding ?? String(match.0)
        }
    }
}

private extension Substring {
    func trimmingSuffix(while predicate: (Character) -> Bool) -> Substring {
        var result = self
        while let last = result.last, predicate(last) {
            result.removeLast()
        }
        return result
    }
}

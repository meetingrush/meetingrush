import Foundation

public enum NotesFormatter {
    /// Turns event notes into readable plain text.
    ///
    /// HTML tags are removed and entities decoded. Lines of only separator characters, such as the
    /// `-::~:~::-` rules Google adds to invites, are dropped, and runs of blank lines collapse to one.
    public static func plainText(_ notes: String) -> String {
        // Named tags only: Exchange notes wrap bare URLs in angle brackets, which a generic `<[^>]+>` would delete.
        let tag = #/<\/?(?:p|br|div|span|a|b|i|u|em|strong|font|ul|ol|li|table|tbody|tr|td|h[1-6]|html|head|body)\b[^>]*>/#.ignoresCase()
        let blockEnd = #/<br\s*\/?>|<\/(?:p|div|li|tr|h[1-6])>/#.ignoresCase()

        let text = notes
            .replacing(blockEnd, with: "\n")
            .replacing(tag, with: "")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")

        var lines: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isSeparator = trimmed.count >= 5 && !trimmed.contains { $0.isLetter || $0.isNumber }
            if isSeparator || (trimmed.isEmpty && (lines.last?.isEmpty ?? true)) {
                continue
            }
            lines.append(trimmed)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Marks every URL in `text` as a link.
    public static func linkified(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return result
        }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url,
                  let stringRange = Range(match.range, in: text),
                  let range = Range(stringRange, in: result)
            else { continue }
            result[range].link = url
        }
        return result
    }
}

/// A calendar a provider can read, shown in Settings so the user can choose which ones alert.
public struct CalendarInfo: Identifiable, Hashable, Sendable {
    public struct Color: Hashable, Sendable {
        /// sRGB components in `0...1`.
        public let red, green, blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    public let id: String
    public let title: String
    /// The account the calendar belongs to, such as "iCloud" or an email address.
    public let account: String
    public let color: Color?

    public init(id: String, title: String, account: String, color: Color?) {
        self.id = id
        self.title = title
        self.account = account
        self.color = color
    }
}

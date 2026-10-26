import Foundation

/// A source of meetings, such as the macOS calendar store or a remote calendar API.
@MainActor
public protocol CalendarProvider: AnyObject {
    /// Stable identifier for this source, used to key per-source settings.
    var id: String { get }

    /// Asks the user for access if they have not been asked yet. Returns whether access is granted.
    func requestAccess() async throws -> Bool

    /// The calendars this source can read.
    func calendars() async throws -> [CalendarInfo]

    /// Meetings in `calendars` overlapping `start..<end`, excluding ones that were cancelled or that the user declined.
    func meetings(from start: Date, to end: Date, in calendars: [CalendarInfo]) async throws -> [Meeting]

    /// Registers a handler to call whenever this source's events may have changed.
    func observeChanges(_ handler: @escaping @MainActor () -> Void)
}

import AppKit
@preconcurrency import EventKit
import MeetingRushCore

/// Reads the calendars synced into Calendar.app: iCloud, Exchange/M365, Google and any other account added in System Settings.
@MainActor
final class EventKitCalendarProvider: CalendarProvider {
    let id = "apple-calendar"
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?

    func requestAccess() async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return true
        case .notDetermined:
            let granted = try await store.requestFullAccessToEvents()
            // A store created before the grant can keep returning no calendars until it is reset.
            if granted { store.reset() }
            return granted
        default:
            return false
        }
    }

    func calendars() async throws -> [CalendarInfo] {
        store.calendars(for: .event).map { calendar in
            let rgb = calendar.color?.usingColorSpace(.sRGB)
            return CalendarInfo(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                account: calendar.source?.title ?? "Other",
                color: rgb.map { CalendarInfo.Color(red: $0.redComponent, green: $0.greenComponent, blue: $0.blueComponent) }
            )
        }
    }

    func meetings(from start: Date, to end: Date) async throws -> [Meeting] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { $0.status != .canceled && !$0.isDeclinedByCurrentUser }
            .map(Meeting.init(event:))
    }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }
}

private extension EKEvent {
    var isDeclinedByCurrentUser: Bool {
        attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
    }
}

private extension Participant {
    init(_ participant: EKParticipant) {
        let email = participant.url.absoluteString.hasPrefix("mailto:") ? participant.url.absoluteString.dropFirst("mailto:".count).removingPercentEncoding : nil
        let status: Status = switch participant.participantStatus {
        case .accepted: .accepted
        case .tentative: .tentative
        case .declined: .declined
        default: .pending
        }
        self.init(name: participant.name ?? email ?? "Unknown", email: email, status: status, isCurrentUser: participant.isCurrentUser)
    }
}

private extension Meeting {
    init(event: EKEvent) {
        let organizer = event.organizer.map(Participant.init)
        self.init(
            id: "\(event.calendarItemIdentifier)@\(event.startDate.timeIntervalSince1970)",
            title: event.title ?? "Untitled event",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            calendarID: event.calendar?.calendarIdentifier ?? "",
            calendarName: event.calendar?.title ?? "",
            location: event.location,
            joinLink: MeetingLinkDetector.detect(in: [event.url?.absoluteString, event.location, event.notes]),
            notes: event.notes,
            organizer: organizer,
            // Exchange lists the organiser among the attendees as well.
            attendees: (event.attendees ?? []).map(Participant.init).filter { $0.email == nil || $0.email != organizer?.email }
        )
    }
}

import AppKit
import MeetingRushCore
import Observation
import os

/// Pulls meetings from every provider, schedules alerts and drives the overlay.
@MainActor
@Observable
final class AppCoordinator {
    private(set) var upcoming: [Meeting] = []
    private(set) var calendars: [CalendarInfo] = []
    private(set) var excludedCalendarIDs: Set<CalendarInfo.ID> = []
    private(set) var accessDenied = false

    private let providers: [any CalendarProvider]
    private let overlay = OverlayController()
    private var planner = AlertPlanner()
    private var meetings: [Meeting] = []
    private var showing: Meeting?
    private var alertTimer: Timer?
    private var heartbeat: Timer?
    private var observers: [NSObjectProtocol] = []
    private var scheduledAlertDate: Date?
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MeetingRush", category: "alerts")

    private static let lookBehind: TimeInterval = 60 * 60
    /// Long enough that the menu still lists the next few meetings after a quiet stretch.
    private static let lookAhead: TimeInterval = 30 * 24 * 60 * 60

    init(providers: [any CalendarProvider]) {
        self.providers = providers
    }

    func start() async {
        var anyGranted = false
        for provider in providers {
            anyGranted = (try? await provider.requestAccess()) == true || anyGranted
            provider.observeChanges { [weak self] in self?.refreshSoon() }
        }
        accessDenied = !anyGranted

        // The heartbeat and wake refresh catch alerts a timer missed while the Mac slept.
        heartbeat = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSoon() }
        }
        observe(NSWorkspace.didWakeNotification, on: NSWorkspace.shared.notificationCenter)
        observe(UserDefaults.didChangeNotification, on: .default)

        await refresh()
    }

    func refresh() async {
        let now = Date()
        excludedCalendarIDs = Set(UserDefaults.standard.stringArray(forKey: SettingsKey.excludedCalendarIDs) ?? [])
        var fetchedCalendars: [CalendarInfo] = []
        var fetched: [Meeting] = []
        for provider in providers {
            fetchedCalendars += (try? await provider.calendars()) ?? []
            fetched += (try? await provider.meetings(from: now - Self.lookBehind, to: now + Self.lookAhead)) ?? []
        }
        calendars = fetchedCalendars.sorted { ($0.account, $0.title) < ($1.account, $1.title) }
        meetings = fetched
            .filter { !excludedCalendarIDs.contains($0.calendarID) }
            .sorted { $0.start < $1.start }
        upcoming = meetings.filter { $0.end > now && !$0.isAllDay }
        planner.settings = .load()
        planner.retainState(for: meetings)
        evaluate()
    }

    func isEnabled(_ calendar: CalendarInfo) -> Bool {
        !excludedCalendarIDs.contains(calendar.id)
    }

    func setEnabled(_ calendar: CalendarInfo, _ enabled: Bool) {
        if enabled {
            excludedCalendarIDs.remove(calendar.id)
        } else {
            excludedCalendarIDs.insert(calendar.id)
        }
        UserDefaults.standard.set(excludedCalendarIDs.sorted(), forKey: SettingsKey.excludedCalendarIDs)
    }

    func join(_ meeting: Meeting) {
        if let link = meeting.joinLink {
            open(link)
        }
        dismiss(meeting)
    }

    func dismiss(_ meeting: Meeting) {
        log.notice("Dismissed meeting starting \(meeting.start, privacy: .public)")
        planner.dismiss(meeting)
        closeOverlay()
    }

    func snooze(_ meeting: Meeting, until date: Date) {
        log.notice("Snoozed meeting starting \(meeting.start, privacy: .public) until \(date, privacy: .public)")
        planner.snooze(meeting, until: date)
        closeOverlay()
    }

    /// Shows the overlay for the next meeting, or a sample one, without touching alert state.
    func previewAlert() {
        // The overlay holds one alert at a time; replacing a real one would leave it unanswered forever.
        guard showing == nil else { return }
        let now = Date()
        let meeting = upcoming.first ?? Meeting(
            id: "preview",
            title: "Preview meeting",
            start: now + 60,
            end: now + 31 * 60,
            calendarID: "preview",
            calendarName: "MeetingRush",
            joinLink: MeetingLink(service: .googleMeet, url: URL(string: "https://meet.google.com/abc-defg-hij")!)
        )
        overlay.show(meeting, actions: OverlayActions(
            join: meeting.joinLink.map { link in { [weak self] in self?.open(link); self?.overlay.hide() } },
            snooze: { [weak self] _ in self?.overlay.hide() },
            dismiss: { [weak self] in self?.overlay.hide() }
        ))
    }

    private func evaluate() {
        let now = Date()
        if showing == nil, let meeting = planner.dueMeetings(in: meetings, at: now).first {
            show(meeting, at: now)
        }
        scheduleAlertTimer(at: planner.nextAlertDate(in: meetings, after: now))
    }

    private func show(_ meeting: Meeting, at now: Date) {
        let lateness = planner.alertDate(for: meeting).map { now.timeIntervalSince($0) } ?? 0
        log.notice("Showing alert for meeting starting \(meeting.start, privacy: .public), \(Int(lateness), privacy: .public)s after its alert time")
        showing = meeting
        overlay.show(meeting, actions: OverlayActions(
            join: meeting.joinLink == nil ? nil : { [weak self] in self?.join(meeting) },
            snooze: { [weak self] date in self?.snooze(meeting, until: date) },
            dismiss: { [weak self] in self?.dismiss(meeting) }
        ))
    }

    private func closeOverlay() {
        overlay.hide()
        showing = nil
        evaluate()
    }

    private func open(_ link: MeetingLink) {
        if let appURL = link.appURL, NSWorkspace.shared.urlForApplication(toOpen: appURL) != nil {
            NSWorkspace.shared.open(appURL)
        } else {
            NSWorkspace.shared.open(link.url)
        }
    }

    private func scheduleAlertTimer(at date: Date?) {
        if date != scheduledAlertDate {
            log.notice("Next alert at \(date?.description ?? "none", privacy: .public) (\(self.meetings.count, privacy: .public) meetings loaded)")
            scheduledAlertDate = date
        }
        alertTimer?.invalidate()
        alertTimer = nil
        guard let date else { return }
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        alertTimer = timer
    }

    private func refreshSoon() {
        Task { await refresh() }
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSoon() }
        })
    }
}

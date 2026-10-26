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
    private(set) var selection = CalendarSelection()
    /// The `CalendarProvider.id`s of the providers that can read calendars.
    private(set) var providersWithAccess: Set<String> = []

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
        selection = Self.loadSelection()
        for provider in providers {
            provider.observeChanges { [weak self] in self?.refreshSoon() }
        }
        await updateAccess()

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
        selection = Self.loadSelection()
        await updateAccess()
        var fetchedCalendars: [CalendarInfo] = []
        var fetched: [Meeting] = []
        // Providers are listed richest first, so the copy MeetingMerger keeps comes from the better source.
        for provider in providers where providersWithAccess.contains(provider.id) {
            let providerCalendars = (try? await provider.calendars()) ?? []
            fetchedCalendars += providerCalendars
            let enabled = providerCalendars.filter(selection.isEnabled)
            fetched += (try? await provider.meetings(from: now - Self.lookBehind, to: now + Self.lookAhead, in: enabled)) ?? []
        }
        calendars = fetchedCalendars.sorted { ($0.account, $0.title) < ($1.account, $1.title) }
        meetings = MeetingMerger.deduplicated(fetched).sorted { $0.start < $1.start }
        upcoming = meetings.filter { $0.end > now && !$0.isAllDay }
        planner.settings = .load()
        planner.retainState(for: meetings)
        evaluate()
    }

    var hasCalendarAccess: Bool {
        !providersWithAccess.isEmpty
    }

    func isEnabled(_ calendar: CalendarInfo) -> Bool {
        selection.isEnabled(calendar)
    }

    func setEnabled(_ calendar: CalendarInfo, _ enabled: Bool) {
        selection.set(calendar, enabled: enabled)
        UserDefaults.standard.set(selection.choices, forKey: SettingsKey.calendarChoices)
    }

    private func updateAccess() async {
        var granted: Set<String> = []
        for provider in providers where (try? await provider.requestAccess()) == true {
            granted.insert(provider.id)
        }
        providersWithAccess = granted
    }

    private static func loadSelection() -> CalendarSelection {
        let defaults = UserDefaults.standard
        if let legacy = defaults.stringArray(forKey: SettingsKey.legacyExcludedCalendarIDs) {
            let choices = Dictionary(legacy.map { ($0, false) }, uniquingKeysWith: { first, _ in first })
            defaults.set(choices, forKey: SettingsKey.calendarChoices)
            defaults.removeObject(forKey: SettingsKey.legacyExcludedCalendarIDs)
        }
        return CalendarSelection(choices: defaults.dictionary(forKey: SettingsKey.calendarChoices) as? [String: Bool] ?? [:])
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

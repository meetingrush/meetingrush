import AppKit
import MeetingRushCore
import Observation
import SwiftUI

/// Hover and expansion state for the agenda, held outside the view because `@State` is off limits in this target.
@MainActor
@Observable
final class AgendaState {
    var hoveredID: Meeting.ID?
    var expandedID: Meeting.ID?
    var hoveredFooterButton: String?
    var contentHeight: CGFloat = 0
}

struct MenuContent: View {
    let coordinator: AppCoordinator
    let state: AgendaState
    let close: () -> Void
    let openSettings: () -> Void

    private static let meetingLimit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !coordinator.hasCalendarAccess {
                Button("Set up calendars…") {
                    close()
                    openSettings()
                }
                .padding(12)
                Divider()
            }

            if days.isEmpty {
                Text("No meetings in the next 30 days")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else {
                ScrollView {
                    agenda
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { state.contentHeight = $0 }
                }
                .frame(height: min(state.contentHeight, maxListHeight))
            }

            Divider()
            VStack(spacing: 0) {
                FooterButton(title: "Preview Alert", systemImage: "bell.badge", state: state) {
                    close()
                    coordinator.previewAlert()
                }
                FooterButton(title: "Settings…", systemImage: "gearshape", shortcut: ",", state: state) {
                    close()
                    openSettings()
                }
                FooterButton(title: "Quit MeetingRush", systemImage: "power", shortcut: "q", state: state) {
                    NSApp.terminate(nil)
                }
            }
            .padding(8)
        }
        .frame(width: 360)
    }

    private var agenda: some View {
        let colors = Dictionary(coordinator.calendars.map { ($0.id, $0.color) }, uniquingKeysWith: { first, _ in first })
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(days) { day in
                Text(Self.title(for: day.date))
                    .font(.headline)
                    .padding(.horizontal, 8)
                    .padding(.top, day == days.first ? 4 : 14)
                    .padding(.bottom, 4)

                ForEach(day.meetings) { meeting in
                    MeetingRow(
                        meeting: meeting,
                        color: colors[meeting.calendarID]??.swiftUIColor ?? .secondary,
                        state: state,
                        join: {
                            close()
                            coordinator.join(meeting)
                        }
                    )
                }
            }
        }
        .padding(8)
    }

    /// Grows to fit every meeting and only scrolls once the panel would run off the screen.
    private var maxListHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        return screenHeight - 120
    }

    private var days: [AgendaDay] {
        Agenda.days(for: Array(coordinator.upcoming.prefix(Self.meetingLimit)), now: .now)
    }

    private static func title(for day: Date) -> String {
        let date = day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        if Calendar.current.isDateInToday(day) {
            return "Today · \(date)"
        }
        if Calendar.current.isDateInTomorrow(day) {
            return "Tomorrow · \(date)"
        }
        return date
    }
}

/// A menu-item style row: a round grey icon, the title, and the keyboard shortcut on the right.
private struct FooterButton: View {
    let title: String
    let systemImage: String
    var shortcut: Character?
    let state: AgendaState
    let action: () -> Void

    private var isHovered: Bool { state.hoveredFooterButton == title }

    var body: some View {
        if let shortcut {
            button.keyboardShortcut(KeyEquivalent(shortcut))
        } else {
            button
        }
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.primary.opacity(0.1)))
                Text(title)
                Spacer()
                if let shortcut {
                    Text("⌘\(String(shortcut).uppercased())")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(MenuRowButtonStyle(isHovered: isHovered))
        .onHover { hovering in
            if hovering {
                state.hoveredFooterButton = title
            } else if isHovered {
                state.hoveredFooterButton = nil
            }
        }
    }
}

private struct MenuRowButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(shape.fill(Color.primary.opacity(configuration.isPressed ? 0.14 : isHovered ? 0.07 : 0)))
            .contentShape(shape)
    }
}

extension CalendarInfo.Color {
    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue)
    }
}

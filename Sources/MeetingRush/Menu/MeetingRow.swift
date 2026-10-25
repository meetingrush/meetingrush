import MeetingRushCore
import SwiftUI

/// One meeting in the agenda: shows a Join button on hover, and expands into its details on click.
struct MeetingRow: View {
    let meeting: Meeting
    let color: Color
    let state: AgendaState
    let join: () -> Void

    private static let widestTime = Calendar.current.date(from: DateComponents(hour: 22, minute: 58)) ?? .now

    private var isHovered: Bool { state.hoveredID == meeting.id }
    private var isExpanded: Bool { state.expandedID == meeting.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // The hidden widest time sizes the column, so titles line up whatever the locale's format.
                ZStack(alignment: .leading) {
                    widestTimeText
                        .hidden()
                    time
                }
                .lineLimit(1)
                .fixedSize()
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(meeting.title)
                    .lineLimit(isExpanded ? 3 : 1)
                    .fontWeight(isExpanded ? .semibold : .regular)
                Spacer(minLength: 4)
                if let link = meeting.joinLink {
                    if isHovered || isExpanded {
                        Button("Join", action: join)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .help("Join \(link.service.rawValue)")
                    } else {
                        Image(systemName: "video")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minHeight: 22)
            .contentShape(Rectangle())
            .onTapGesture {
                // Rows shift under the cursor as one expands and another collapses, and the mouse-exit
                // event can be lost, which would leave the previous row highlighted.
                state.hoveredID = meeting.id
                withAnimation(.snappy(duration: 0.2)) {
                    state.expandedID = isExpanded ? nil : meeting.id
                }
            }

            if isExpanded {
                HStack(alignment: .top, spacing: 8) {
                    widestTimeText
                        .hidden()
                    Color.clear
                        .frame(width: 8, height: 0)
                    MeetingDetails(meeting: meeting)
                }
                .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered || isExpanded ? Color.primary.opacity(0.07) : .clear)
        )
        .onHover { hovering in
            if hovering {
                state.hoveredID = meeting.id
            } else if isHovered {
                state.hoveredID = nil
            }
        }
    }

    private var widestTimeText: some View {
        Text(Self.widestTime, format: .dateTime.hour().minute())
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }

    @ViewBuilder
    private var time: some View {
        if meeting.start <= .now {
            Text("Now")
                .foregroundStyle(Color.accentColor)
                .fontWeight(.medium)
        } else {
            Text(meeting.start, format: .dateTime.hour().minute())
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

import AppKit
import MeetingRushCore
import SwiftUI

struct OverlayView: View {
    let meeting: Meeting
    let actions: OverlayActions

    private static let titleSize: CGFloat = 56
    /// Sizes the logo to the title's capital letters.
    private static let titleCapHeight = NSFont.systemFont(ofSize: titleSize, weight: .bold).capHeight

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThickMaterial)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(startsText)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Image(nsImage: AppImages.logo)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(height: Self.titleCapHeight)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                    Text(meeting.title)
                        .font(.system(size: Self.titleSize, weight: .bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }

                Text(details)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    if let join = actions.join, let service = meeting.joinLink?.service {
                        Button("Join \(service.rawValue)", action: join)
                            .keyboardShortcut(.defaultAction)
                    }

                    Menu("Snooze 1 min") {
                        Button("5 minutes") { actions.snooze(.now + 5 * 60) }
                        if meeting.start > .now + 60 {
                            Button("Until it starts") { actions.snooze(meeting.start) }
                        }
                    } primaryAction: {
                        actions.snooze(.now + 60)
                    }
                    .fixedSize()

                    Button("Dismiss", action: actions.dismiss)
                        .keyboardShortcut(.cancelAction)
                }
                .controlSize(.extraLarge)
                .padding(.top, 24)
            }
            .padding(48)
            .frame(maxWidth: 900)
        }
    }

    private var startsText: String {
        let relative = meeting.start.formatted(.relative(presentation: .named))
        return meeting.start > .now ? "Starts \(relative)" : "Started \(relative)"
    }

    private var details: String {
        let time = "\(meeting.start.formatted(date: .omitted, time: .shortened)) – \(meeting.end.formatted(date: .omitted, time: .shortened))"
        return [time, meeting.location, meeting.calendarName]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: "  ·  ")
    }
}

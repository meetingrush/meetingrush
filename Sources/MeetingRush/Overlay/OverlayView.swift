import AppKit
import MeetingRushCore
import SwiftUI

struct OverlayView: View {
    let meeting: Meeting
    let actions: OverlayActions

    private static let titleSize: CGFloat = 56
    /// Room added on each side of a button's label, on top of the system's own inset.
    private static let buttonExtraPadding: CGFloat = 16
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

                HStack(spacing: 12) {
                    // At its natural width the snooze split button leaves its text hard against the edge; extra width centres it.
                    EqualWidthHStack(spacing: 12, extraWidth: Self.buttonExtraPadding * 2) {
                        if let join = actions.join, let service = meeting.joinLink?.service {
                            Button(action: join) {
                                Text("Join \(service.rawValue)")
                                    .frame(maxWidth: .infinity)
                            }
                            .keyboardShortcut(.defaultAction)
                        }

                        SnoozeButton(meeting: meeting, snooze: actions.snooze)
                    }

                    Spacer(minLength: 48)

                    Button(action: actions.dismiss) {
                        Text("Dismiss")
                            .padding(.horizontal, Self.buttonExtraPadding)
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .frame(maxWidth: 640)
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

/// "Snooze 1 min" with a chevron segment that opens longer options in a menu under the whole button.
///
/// Built from a plain button rather than a SwiftUI `Menu`, whose popup opens under the chevron and can't be
/// positioned or sized.
private struct SnoozeButton: View {
    let meeting: Meeting
    let snooze: (Date) -> Void
    private let anchor = ViewReference()

    private static let chevronWidth: CGFloat = 36

    var body: some View {
        Button {
            snooze(.now + 60)
        } label: {
            Text("Snooze 1 min")
                .frame(maxWidth: .infinity)
                .padding(.trailing, Self.chevronWidth)
        }
        .background(ViewAnchor(reference: anchor))
        .overlay(alignment: .trailing) {
            HStack(spacing: 0) {
                Divider()
                    .frame(height: 22)
                Button(action: showMenu) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: Self.chevronWidth)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Out of the focus loop, or clicking the alert focuses it and draws a ring around it.
                .focusable(false)
                .accessibilityLabel("More snooze options")
            }
        }
    }

    private func showMenu() {
        guard let view = anchor.view else { return }
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(title: "5 minutes") { snooze(.now + 5 * 60) })
        if meeting.start > .now + 60 {
            menu.addItem(ClosureMenuItem(title: "Until it starts") { snooze(meeting.start) })
        }
        menu.minimumWidth = view.bounds.width
        // The bezel overhangs the view by about 4 pt, so 8 pt below the view leaves a native-looking gap under it.
        let below = view.isFlipped ? view.bounds.maxY + 8 : view.bounds.minY - 8
        menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.minX, y: below), in: view)
    }
}

/// Holds the AppKit view behind a SwiftUI view, for anchoring AppKit UI such as menus to it.
@MainActor
private final class ViewReference {
    weak var view: NSView?
}

private struct ViewAnchor: NSViewRepresentable {
    let reference: ViewReference

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        reference.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        reference.view = view
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func fire() {
        handler()
    }
}

/// Lays its children out in a row, each as wide as the widest one plus `extraWidth`.
private struct EqualWidthHStack: Layout {
    var spacing: CGFloat
    var extraWidth: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = cellSize(subviews)
        let count = CGFloat(subviews.count)
        return CGSize(width: size.width * count + spacing * max(count - 1, 0), height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let size = cellSize(subviews)
        var x = bounds.minX
        for subview in subviews {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(size))
            x += size.width + spacing
        }
    }

    private func cellSize(_ subviews: Subviews) -> CGSize {
        let natural = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(
            width: (natural.map(\.width).max() ?? 0) + extraWidth,
            height: natural.map(\.height).max() ?? 0
        )
    }
}

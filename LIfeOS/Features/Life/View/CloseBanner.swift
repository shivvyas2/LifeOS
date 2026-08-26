import SwiftUI
import DesignSystem

/// The prompt to close a month, above the sector deck.
///
/// Deliberately not `AlertBanner`. That component is red on pink with an ECG
/// glyph, and it is the app's anomaly surface: it means something is wrong
/// with your body. An unclosed month is not wrong, it is a piece of admin,
/// and borrowing the alarm styling for it spends the alarm.
///
/// Collapsed by default. The deck below is the reason anyone opens this
/// screen, and a banner that pushes it down every visit earns its space only
/// on the visit where you act on it.
struct CloseBanner: View {
    let month: Date
    let onScore: () -> Void

    @State private var isExpanded = false
    @Environment(\.colorScheme) private var scheme

    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }

    private var monthName: String {
        month.formatted(.dateTime.month(.wide).year())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Button {
                withAnimation(.snappy(duration: 0.22)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: Space.x1) {
                    Text("Close \(monthName)")
                        .font(LifeOSType.rowTitle)
                    Spacer(minLength: Space.x1)
                    Image(systemName: "chevron.down")
                        .font(LifeOSType.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .foregroundStyle(ink)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text("Score your nine sectors for the month.")
                    .font(LifeOSType.label.weight(.regular))
                    .foregroundStyle(ink.opacity(0.7))

                Button(action: onScore) {
                    Text("Score now")
                        .font(LifeOSType.label.weight(.semibold))
                        .foregroundStyle(ink)
                        .padding(.horizontal, Space.x2)
                        .padding(.vertical, Space.x1)
                        .overlay(
                            Capsule().strokeBorder(ink, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Space.x2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .strokeBorder(
                    ink,
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityHint(isExpanded ? "Collapse" : "Expand to score the month")
    }
}

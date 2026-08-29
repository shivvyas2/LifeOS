import SwiftUI

/// What LIFO said, drawn as something the app is telling you rather than as a
/// chat bubble.
///
/// A bubble is the right shape for a transcript, where the point is who spoke
/// when. It is the wrong shape for an answer that is the screen's whole
/// content: it puts the one thing worth reading inside grey packaging and
/// leaves it looking like the least important element on a screen full of
/// cards. This is the opposite arrangement, and it is deliberately the loudest
/// thing in its column.
///
/// Dashed rather than solid, which is the one piece of styling doing real
/// work: every other card in the app has a solid edge, so a broken one reads
/// as generated rather than stored, and as something that will be replaced by
/// the next thing LIFO says.
///
/// Shared with the proactive nudge, which arrives as exactly this shape.
public struct InsightCallout: View {
    private let title: String
    private let text: String
    private let systemImage: String

    @Environment(\.colorScheme) private var scheme

    public init(title: String = "LIFO", text: String, systemImage: String = "sparkles") {
        self.title = title
        self.text = text
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(LifeOSType.rowTitle)
                .foregroundStyle(LifeOSTokens.accent)
                .frame(width: 34, height: 34)
                .background(Circle().fill(LifeOSTokens.cardSurface.resolve(scheme)))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(LifeOSType.rowTitle)
                    .foregroundStyle(LifeOSTokens.accent)
                Text(text)
                    .font(LifeOSType.secondary)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LifeOSTokens.accentSoft.resolve(scheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LifeOSTokens.accent.opacity(scheme == .dark ? 0.55 : 0.40),
                            style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])
                        )
                )
        )
        // One element to VoiceOver: the badge and the title are decoration on
        // the sentence, not three things to swipe through.
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: 16) {
        InsightCallout(text: "You have three meetings stacked before noon and nothing after two. Moving the design crit later would give you a clear morning.")
        InsightCallout(title: "LIFO", text: "Nothing on the calendar tomorrow.")
    }
    .padding()
    .background(LifeOSTokens.canvas.resolve(.light))
}

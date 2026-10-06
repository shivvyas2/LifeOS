import SwiftUI

/// A tab with nothing in it yet, shown as a ghost of what it will hold.
///
/// The sample is drawn by the caller at 35% ink with hit testing off and is
/// hidden from VoiceOver: it teaches by shape, not by content. One sentence
/// says what the tab shows, one button is the action that fills it.
public struct EditorialEmptyState<Sample: View>: View {
    let sentence: String
    let action: String?
    let onAction: () -> Void
    let sample: Sample
    @Environment(\.colorScheme) private var scheme

    public init(sentence: String, action: String, onAction: @escaping () -> Void,
                @ViewBuilder sample: () -> Sample) {
        self.sentence = sentence; self.action = action; self.onAction = onAction
        self.sample = sample()
    }

    /// The ghost and the sentence alone, for a place that can show what the
    /// tab holds but cannot start the action that fills it.
    public init(sentence: String, @ViewBuilder sample: () -> Sample) {
        self.sentence = sentence; self.action = nil; self.onAction = {}
        self.sample = sample()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text("Sample").editorialEyebrow()
            sample
                .opacity(0.35)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Text(sentence)
                .font(LifeOSType.secondary)
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action: onAction) { Text(action) }
                    .buttonStyle(.editorial(.primary))
            }
        }
        .editorialCard()
    }
}

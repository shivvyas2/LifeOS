import SwiftUI
import DesignSystem

/// The app's compact in-card CTA: a capsule, never the stock bordered button.
/// Quiet is the default — soft accent fill with ink text, the same vocabulary
/// as the week strip's selected day and the agenda's date chip. `prominent`
/// is for the one action a card wants pressed, in the warm accent.
struct CapsuleButton: View {
    let title: String
    var prominent = false
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(prominent ? .white : LifeOSTokens.primaryText.resolve(scheme))
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(
                    Capsule().fill(prominent
                                   ? AnyShapeStyle(LifeOSTokens.accent)
                                   : AnyShapeStyle(LifeOSTokens.accentSoft.resolve(scheme)))
                )
        }
        .buttonStyle(.plain)
    }
}

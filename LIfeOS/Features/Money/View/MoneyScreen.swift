import SwiftUI
import DesignSystem

/// Placeholder. Money needs its own `Transaction` model before it can show
/// anything — and this app's rule is that a number is never invented, so this
/// says "nothing here yet" rather than rendering a plausible-looking zero.
struct MoneyScreen: View {
    var body: some View {
        GradientCanvas(hue: .money) {
            VStack(spacing: 10) {
                Spacer()
                HeroEmptyState(label: "Money", reason: "Income and expenses arrive in the next slice")
                    .foregroundStyle(LifeOSTokens.onGradient)
                Spacer()
                Spacer()
            }
            .padding(20)
        }
    }
}

#Preview {
    MoneyScreen()
}

import SwiftUI
import DesignSystem

/// Placeholder. Plan will hold goals, habits, notes and the content calendar,
/// built on the shared `PlanItem` shape so a block renderer can consume them
/// later without a migration.
struct PlanScreen: View {
    var body: some View {
        GradientCanvas(hue: .habits) {
            VStack(spacing: 10) {
                Spacer()
                HeroEmptyState(label: "Plan", reason: "Goals, habits and notes arrive in the next slice")
                    .foregroundStyle(LifeOSTokens.onGradient)
                Spacer()
                Spacer()
            }
            .padding(20)
        }
    }
}

#Preview {
    PlanScreen()
}

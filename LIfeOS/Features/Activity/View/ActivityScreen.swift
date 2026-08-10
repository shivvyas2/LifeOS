import SwiftUI
import DesignSystem

/// Movement for the selected day. Rendered inside `BodyHubScreen`, which owns
/// the canvas and the day strip, so this contributes content only.
struct ActivitySection: View {
    let snapshot: ActivitySnapshot

    var body: some View {
        VStack(spacing: 24) {
            if let steps = snapshot.steps {
                HeroNumeral(value: steps.formatted(), label: "Steps")
                    .foregroundStyle(LifeOSTokens.onGradient)
                    .padding(.top, 18)
            } else {
                HeroEmptyState(label: "Steps", reason: "No movement recorded")
                    .foregroundStyle(LifeOSTokens.onGradient)
                    .padding(.top, 18)
            }

            HStack(spacing: 10) {
                MetricTile(label: "Active Time",
                           value: snapshot.exerciseMinutes.map { "\($0)" }, unit: "min")
                MetricTile(label: "Calories",
                           value: snapshot.activeEnergyKcal.map { "\(Int($0))" }, unit: "kcal")
                MetricTile(label: "Resting HR",
                           value: snapshot.restingHR.map { "\(Int($0))" }, unit: "bpm")
            }
        }
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [ModuleHue.activity.top, ModuleHue.activity.bottom],
                       startPoint: .top, endPoint: .bottom)
        ActivitySection(snapshot: ActivitySnapshot(
            steps: 13143, exerciseMinutes: 72, activeEnergyKcal: 1277, restingHR: 54
        ))
        .padding()
    }
    .ignoresSafeArea()
}

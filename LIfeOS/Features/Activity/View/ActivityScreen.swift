import SwiftUI
import DesignSystem

struct ActivityScreen: View {
    let snapshot: ActivitySnapshot

    var body: some View {
        GradientCanvas(hue: .activity) {
            ScrollView {
                VStack(spacing: 28) {
                    if let steps = snapshot.steps {
                        HeroNumeral(value: steps.formatted(), unit: "steps", label: "Today")
                            .foregroundStyle(.white)
                            .padding(.top, 40)
                    } else {
                        HeroEmptyState(label: "Steps", reason: "No movement recorded today")
                            .foregroundStyle(.white)
                            .padding(.top, 40)
                    }

                    HStack(spacing: 10) {
                        GlassCard {
                            StatTile(label: "Active", value: snapshot.exerciseMinutes.map { "\($0)" }, unit: "min")
                        }
                        GlassCard {
                            StatTile(label: "Energy", value: snapshot.activeEnergyKcal.map { "\(Int($0))" }, unit: "kcal")
                        }
                        GlassCard {
                            StatTile(label: "Resting HR", value: snapshot.restingHR.map { "\(Int($0))" }, unit: "bpm")
                        }
                    }
                    .foregroundStyle(.white)
                }
                .padding(20)
                .padding(.bottom, 120)
            }
        }
    }
}

#Preview {
    ActivityScreen(snapshot: ActivitySnapshot(
        steps: 8432, exerciseMinutes: 32, activeEnergyKcal: 512, restingHR: 54
    ))
}

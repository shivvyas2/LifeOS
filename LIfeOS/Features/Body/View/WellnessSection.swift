import SwiftUI
import DesignSystem

/// Wellness reports the week, not the day — sleep and training only mean
/// something as a pattern. The verdicts come from the view model so this view
/// renders judgement rather than making it.
struct WellnessSection: View {
    let snapshot: WellnessSnapshot

    var body: some View {
        VStack(spacing: 24) {
            if let minutes = snapshot.averageSleepMinutes {
                HeroNumeral(value: "\(minutes / 60)h \(minutes % 60)m", label: "Average sleep · 7 days")
                    .foregroundStyle(LifeOSTokens.onGradient)
                    .padding(.top, 18)
            } else {
                HeroEmptyState(label: "Average sleep", reason: "No sleep recorded this week")
                    .foregroundStyle(LifeOSTokens.onGradient)
                    .padding(.top, 18)
            }

            HStack(spacing: 10) {
                MetricTile(label: "Sleep", value: snapshot.sleepVerdict)
                MetricTile(label: "Workout days",
                           value: "\(snapshot.workoutDays)", unit: "of \(snapshot.workoutTarget)")
                MetricTile(label: "Avg session",
                           value: snapshot.averageExerciseMinutes.map { "\($0)" }, unit: "min")
            }

            SolidCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TRAINING")
                        .font(.system(size: 11, weight: .semibold)).tracking(0.6).opacity(0.55)
                    HStack {
                        Text(snapshot.trainingVerdict ?? "—")
                            .font(.system(size: 22, weight: .semibold))
                        Spacer()
                        Text("\(snapshot.workoutDays)/\(snapshot.workoutTarget) days")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(LifeOSTokens.accent)
                    }
                }
            }
        }
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [ModuleHue.habits.top, ModuleHue.habits.bottom],
                       startPoint: .top, endPoint: .bottom)
        WellnessSection(snapshot: WellnessSnapshot(
            averageSleepMinutes: 450, workoutDays: 4, averageExerciseMinutes: 38,
            sleepVerdict: "Optimal", trainingVerdict: "Consistent"
        ))
        .padding()
    }
    .ignoresSafeArea()
}

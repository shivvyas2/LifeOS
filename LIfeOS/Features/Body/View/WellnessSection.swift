import SwiftUI
import DesignSystem

/// Wellness reports the week, not the day. Sleep and training only mean
/// something as a pattern. The verdicts come from the view model so this view
/// renders judgement rather than making it.
struct WellnessSection: View {
    let snapshot: WellnessSnapshot
    var onAddJournal: () -> Void = {}
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 24) {
            if let minutes = snapshot.averageSleepMinutes {
                HeroNumeral(value: "\(minutes / 60)h \(minutes % 60)m", label: "Average sleep · 7 days")
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .padding(.top, 18)
            } else {
                HeroEmptyState(label: "Average sleep", reason: "No sleep recorded this week")
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .padding(.top, 18)
            }

            HStack(spacing: 10) {
                MetricTile(label: "Sleep", value: snapshot.sleepVerdict)
                MetricTile(label: "Workout days",
                           value: "\(snapshot.workoutDays)", unit: "of \(snapshot.workoutTarget)")
                MetricTile(label: "Avg session",
                           value: snapshot.averageExerciseMinutes.map { "\($0)" }, unit: "min")
            }

            SoftCard {
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

            journalCard
        }
    }

    private var journalCard: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("JOURNAL")
                        .font(.system(size: 11, weight: .semibold)).tracking(0.6).opacity(0.55)
                    Spacer()
                    Button(snapshot.hasEntryToday ? "Add another" : "Write today") {
                        onAddJournal()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .tint(LifeOSTokens.accent)
                }

                if snapshot.journal.isEmpty {
                    Text("Nothing written yet. How did today feel?")
                        .font(.system(size: 14))
                        .opacity(0.5)
                } else {
                    ForEach(snapshot.journal.prefix(4)) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.text)
                                .font(.system(size: 15))
                                .lineLimit(3)
                            Text(entry.date.formatted(.dateTime.weekday(.abbreviated).month().day()))
                                .font(.system(size: 12))
                                .opacity(0.45)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

#Preview {
    GradientCanvas(hue: .habits) {
        WellnessSection(snapshot: WellnessSnapshot(
            averageSleepMinutes: 450, workoutDays: 4, averageExerciseMinutes: 38,
            sleepVerdict: "Optimal", trainingVerdict: "Consistent"
        ))
        .padding()
    }
}

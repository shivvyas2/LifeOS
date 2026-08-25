import SwiftUI
import DesignSystem

/// The Fitness half: output. The weekly burn, today's movement, strain, the
/// sessions themselves, and how the training week is adding up.
struct FitnessSegmentView: View {
    let activity: ActivitySnapshot
    let recovery: RecoverySnapshot
    let wellness: WellnessSnapshot
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 20) {
            caloriesCard

            HStack(spacing: 12) {
                IconBubbleTile(icon: "figure.walk", hue: .body, label: "Steps",
                               value: activity.steps.map { $0.formatted() })
                IconBubbleTile(icon: "bolt.fill", hue: .activity, label: "Active Time",
                               value: activity.exerciseMinutes.map { "\($0)" }, unit: "min")
            }

            HStack(spacing: 12) {
                IconBubbleTile(icon: "gauge.with.needle", hue: .habits, label: "Strain",
                               value: recovery.dayStrain.map { String(format: "%.1f", $0) })
                IconBubbleTile(icon: "heart.fill", hue: .recovery, label: "Avg HR",
                               value: recovery.averageHR.map { "\(Int($0))" }, unit: "bpm")
                IconBubbleTile(icon: "bolt.heart.fill", hue: .habits, label: "Max HR",
                               value: recovery.maxHR.map { "\(Int($0))" }, unit: "bpm")
            }

            if !activity.workouts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("WORKOUTS")
                        .font(.system(size: 11, weight: .bold)).tracking(1)
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    ForEach(activity.workouts) { WorkoutRow(workout: $0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            trainingCard
        }
    }

    private var caloriesCard: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Calories Burnt").font(.system(size: 16, weight: .semibold))
                        Text("This week").font(.system(size: 12))
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    }
                    Spacer()
                    let total = activity.weekCalories.compactMap(\.value).reduce(0, +)
                    Text(total > 0 ? "\(Int(total).formatted()) kcal" : "—")
                        .font(.system(size: 15, weight: .semibold))
                }
                RoundedBarChart(bars: activity.weekCalories.map {
                    RoundedBarChart.Bar(
                        id: $0.id,
                        label: $0.id.formatted(.dateTime.weekday(.abbreviated)),
                        value: $0.value
                    )
                })
            }
        }
    }

    private var trainingCard: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("TRAINING")
                    .font(.system(size: 11, weight: .semibold)).tracking(0.6).opacity(0.55)
                HStack {
                    Text(wellness.trainingVerdict ?? "—").font(.system(size: 22, weight: .semibold))
                    Spacer()
                    Text("\(wellness.workoutDays)/\(wellness.workoutTarget) days")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(LifeOSTokens.accent)
                }
                if let avg = wellness.averageExerciseMinutes {
                    Text("Avg session \(avg) min").font(.system(size: 13))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }
            }
        }
    }
}

/// One session.
///
/// Strain is deliberately NOT coloured with `RecoveryBand`. The two scales run
/// opposite ways: high recovery is good and green, high strain is hard work and
/// green would read as praise. A single accent keeps the number honest.
struct WorkoutRow: View {
    let workout: WorkoutSummary
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(workout.displaySport)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    if workout.isPartlyRecorded {
                        // Named, not silently dropped: a partly captured session
                        // has a misleadingly low strain, and the reader needs to
                        // know that before comparing it with anything.
                        Text("partial")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    }
                }

                Text(detailLine)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            if let strain = workout.strain {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "%.1f", strain))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LifeOSTokens.accent)
                    Text("strain")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LifeOSTokens.tileSurface.resolve(scheme))
        )
    }

    private var detailLine: String {
        var parts = [workout.duration]
        if let distance = workout.distance { parts.append(distance) }
        if let hr = workout.averageHR { parts.append("avg \(Int(hr)) bpm") }
        return parts.joined(separator: " · ")
    }
}

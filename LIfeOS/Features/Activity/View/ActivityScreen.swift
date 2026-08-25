import SwiftUI
import DesignSystem

/// Movement for the selected day. Rendered inside `BodyHubScreen`, which owns
/// the canvas and the day strip, so this contributes content only.
struct ActivitySection: View {
    let snapshot: ActivitySnapshot
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 24) {
            if let steps = snapshot.steps {
                HeroNumeral(value: steps.formatted(), label: "Steps")
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .padding(.top, 18)
            } else {
                HeroEmptyState(label: "Steps", reason: "No movement recorded")
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
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

            // Nothing at all on a day with no sessions. Most days have none, and
            // a permanent "No workouts" frame is noise on every one of them.
            if !snapshot.workouts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Workouts")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))

                    ForEach(snapshot.workouts) { WorkoutRow(workout: $0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

#Preview {
    GradientCanvas(hue: .activity) {
        ActivitySection(snapshot: ActivitySnapshot(
            steps: 13143, exerciseMinutes: 72, activeEnergyKcal: 1277, restingHR: 54,
            workouts: [
                WorkoutSummary(id: "a", sport: "running", durationMinutes: 52,
                               strain: 14.2, averageHR: 148, distanceMeters: 6_700,
                               percentRecorded: 100),
                WorkoutSummary(id: "b", sport: "weightlifting", durationMinutes: 41,
                               strain: 8.1, averageHR: 121, distanceMeters: nil,
                               percentRecorded: 62),
            ]
        ))
        .padding()
    }
}

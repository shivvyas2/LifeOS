import SwiftUI
import DesignSystem
import Sectors

/// The Fitness half: output. The weekly burn, today's movement, strain, the
/// sessions themselves, and how the training week is adding up.
struct FitnessSegmentView: View {
    let activity: ActivitySnapshot
    let recovery: RecoverySnapshot
    let wellness: WellnessSnapshot
    /// Nil in the design previews, which render the segment without the app's
    /// view models. The training card simply has no library row then.
    var library: WorkoutLibraryViewModel?
    /// Travels with the library: the player the library pushes records the
    /// session, so the row only appears when both are here.
    var recorder: ActivityRecorder?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 20) {
            caloriesCard

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                HealthReadingCard(icon: "figure.walk", label: "Steps",
                               value: activity.steps.map { $0.formatted() }, hue: .activity)
                HealthReadingCard(icon: "bolt.fill", label: "Active Time",
                               value: activity.exerciseMinutes.map { "\($0)" }, unit: "min", hue: .activity)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                HealthReadingCard(icon: "gauge.with.needle", label: "Strain",
                               value: recovery.dayStrain.map { String(format: "%.1f", $0) })
                HealthReadingCard(icon: "heart.fill", label: "Avg HR",
                               value: recovery.averageHR.map { "\(Int($0))" }, unit: "bpm", hue: .habits)
                HealthReadingCard(icon: "bolt.heart.fill", label: "Max HR",
                               value: recovery.maxHR.map { "\(Int($0))" }, unit: "bpm", hue: .habits)
            }

            NavigationLink { BadmintonHistoryScreen() } label: {
                Label("Badminton session reviews", systemImage: "figure.badminton").font(LifeOSType.rowTitle).frame(minHeight: 48)
            }
            if !activity.workouts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("WORKOUTS")
                        .font(LifeOSType.eyebrow.weight(.bold)).tracking(1)
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    ForEach(activity.workouts) { WorkoutRow(workout: $0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            trainingCard

            if recovery.hasAnyReading {
                NavigationLink {
                    WhoopDetailScreen(snapshot: recovery)
                } label: {
                    HStack(spacing: 6) {
                        Text("14-day trends").font(LifeOSType.label.weight(.semibold))
                        Image(systemName: "chevron.right").font(LifeOSType.caption.weight(.semibold))
                    }
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12).fill(LifeOSTokens.cardSurface.resolve(scheme)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var caloriesCard: some View {
        SoftCard(hue: .activity) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Calories Burnt").font(LifeOSType.rowTitle)
                        Text("Last 7 days").font(LifeOSType.caption)
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    }
                    Spacer()
                    let total = activity.weekCalories.compactMap(\.value).reduce(0, +)
                    Text(total > 0 ? "\(Int(total).formatted()) kcal" : "—")
                        .font(LifeOSType.rowTitle)
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
        SoftCard(hue: .activity) {
            VStack(alignment: .leading, spacing: 8) {
                Text("TRAINING")
                    .font(LifeOSType.eyebrow).tracking(0.6).opacity(0.55)
                HStack {
                    Text(wellness.trainingVerdict ?? "—").font(LifeOSType.sectionTitle)
                    Spacer()
                    Text("\(wellness.workoutDays)/\(wellness.workoutTarget) days")
                        .font(LifeOSType.label)
                        .foregroundStyle(LifeOSTokens.accent)
                }
                if let avg = wellness.averageExerciseMinutes {
                    Text("Avg session \(avg) min").font(LifeOSType.label.weight(.regular))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }
                if let library, let recorder { libraryRow(library, recorder) }
            }
        }
    }

    /// The way into the workout library, with today's plan already on it so
    /// the tap is a decision the person has already half made.
    private func libraryRow(_ library: WorkoutLibraryViewModel, _ recorder: ActivityRecorder) -> some View {
        NavigationLink {
            WorkoutLibraryScreen(model: library, recorder: recorder)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plan today's workout").font(LifeOSType.rowTitle)
                    Text(library.plan.map { "\($0.split.capitalized) · \($0.minutes) min" } ?? "Set a goal for a plan")
                        .font(LifeOSType.caption.weight(.medium))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(LifeOSType.caption.weight(.semibold))
            }
            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            .padding(.vertical, 11).padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LifeOSTokens.tileSurface.resolve(scheme)))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
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
                        .font(LifeOSType.rowTitle)
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    if let split = workout.split {
                        // The plan's own word for the session, so a pull day
                        // in the library reads as a pull day in the list.
                        Text(split.capitalized)
                            .font(LifeOSType.eyebrow.weight(.medium))
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(LifeOSTokens.cardSurface.resolve(scheme), in: Capsule())
                    }
                    if workout.isPartlyRecorded {
                        // Named, not silently dropped: a partly captured session
                        // has a misleadingly low strain, and the reader needs to
                        // know that before comparing it with anything.
                        Text("partial")
                            .font(LifeOSType.eyebrow.weight(.medium))
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    }
                }

                Text(detailLine)
                    .font(LifeOSType.caption.weight(.medium))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            if let strain = workout.strain {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "%.1f", strain))
                        .font(LifeOSType.rowTitle)
                        .foregroundStyle(LifeOSTokens.accent)
                    Text("strain")
                        .font(LifeOSType.eyebrow.weight(.medium))
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

import SwiftUI
import DesignSystem

/// The Body tab. Movement, weight, recovery and wellness sit behind one tab
/// with a segmented switcher, which keeps the tab bar free for the other life
/// domains — Life OS is not a fitness app.
struct BodyHubScreen: View {
    let activity: ActivitySnapshot
    let weight: BodySnapshot
    let recovery: RecoverySnapshot
    let wellness: WellnessSnapshot

    @Binding var section: BodySection
    @Binding var selectedDate: Date

    var body: some View {
        GradientCanvas(hue: section.hue) {
            ScrollView {
                VStack(spacing: 22) {
                    WeekStrip(selection: $selectedDate)
                        .foregroundStyle(LifeOSTokens.onGradient)
                        .padding(.top, 4)

                    SegmentedPill(
                        selection: $section,
                        options: BodySection.allCases.map { ($0, $0.title) }
                    )

                    switch section {
                    case .activity: ActivitySection(snapshot: activity)
                    case .weight:   WeightSection(snapshot: weight)
                    case .recovery: RecoverySection(snapshot: recovery)
                    case .wellness: WellnessSection(snapshot: wellness)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 130)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: section)
    }
}

#Preview {
    @Previewable @State var section = BodySection.activity
    @Previewable @State var day = Date()

    BodyHubScreen(
        activity: ActivitySnapshot(steps: 13143, exerciseMinutes: 72, activeEnergyKcal: 1277, restingHR: 54),
        weight: BodySnapshot(weightKg: 77.4, weeklyDeltaKg: -0.6),
        recovery: RecoverySnapshot(hrvMs: 62, sleepMinutes: 432),
        wellness: WellnessSnapshot(averageSleepMinutes: 450, workoutDays: 4,
                                   averageExerciseMinutes: 38,
                                   sleepVerdict: "Optimal", trainingVerdict: "Consistent"),
        section: $section,
        selectedDate: $day
    )
}

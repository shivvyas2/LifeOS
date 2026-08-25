import SwiftUI
import DesignSystem

/// The Health tab: one week strip, two halves. Health is how the body is
/// doing; Fitness is what it did. Life OS is still not a fitness app.
struct HealthHubScreen: View {
    let activity: ActivitySnapshot
    let weight: BodySnapshot
    let recovery: RecoverySnapshot
    let wellness: WellnessSnapshot
    var onAddJournal: () -> Void = {}
    var onConnectWhoop: () -> Void = {}

    @Binding var section: HealthSection
    @Binding var selectedDate: Date

    @Environment(\.layout) private var layout

    var body: some View {
        GradientCanvas(hue: section.hue) {
            ScrollView {
                VStack(spacing: 22) {
                    WeekStrip(selection: $selectedDate, progress: recovery.weekRecovery)
                        .padding(.top, 4)

                    SegmentedPill(
                        selection: $section,
                        options: HealthSection.allCases.map { ($0, $0.title) }
                    )

                    switch section {
                    case .health:
                        HealthSegmentView(recovery: recovery, weight: weight,
                                          wellness: wellness, selectedDate: selectedDate,
                                          onAddJournal: onAddJournal,
                                          onConnectWhoop: onConnectWhoop)
                    case .fitness:
                        FitnessSegmentView(activity: activity, recovery: recovery,
                                           wellness: wellness)
                    }
                }
                .frame(maxWidth: layout.maxContentWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, layout.gutter)
                .padding(.leading, layout.railInset)
                .padding(.bottom, layout.contentBottomInset)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: section)
    }
}

#Preview {
    @Previewable @State var section = HealthSection.health
    @Previewable @State var day = Date()

    HealthHubScreen(
        activity: ActivitySnapshot(steps: 13143, exerciseMinutes: 72, activeEnergyKcal: 1277, restingHR: 54),
        weight: BodySnapshot(weightKg: 77.4, weeklyDeltaKg: -0.6),
        recovery: RecoverySnapshot(
            recoveryPct: 82,
            hrvMs: 62,
            sleepMinutes: 432,
            sleepPerformancePct: 89,
            sleepEfficiencyPct: 92,
            sleepConsistencyPct: 84,
            sleepDebtMinutes: 18,
            calories: 1293,
            nights: (0..<7).map { offset in
                SleepComposition(
                    date: Calendar.current.date(byAdding: .day, value: offset - 6, to: Date())!,
                    lightMinutes: 210,
                    remMinutes: 98,
                    swsMinutes: 92,
                    awakeMinutes: 14
                )
            },
            napMinutes: 90
        ),
        wellness: WellnessSnapshot(averageSleepMinutes: 450, workoutDays: 4,
                                   averageExerciseMinutes: 38,
                                   sleepVerdict: "Optimal", trainingVerdict: "Consistent"),
        section: $section,
        selectedDate: $day
    )
}

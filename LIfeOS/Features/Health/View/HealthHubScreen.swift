import SwiftUI
import DesignSystem

/// The Health tab: one week strip, two halves. Health is how the body is
/// doing; Fitness is what it did. Almanac is still not a fitness app.
struct HealthHubScreen: View {
    let activity: ActivitySnapshot
    let weight: BodySnapshot
    let recovery: RecoverySnapshot
    let wellness: WellnessSnapshot
    var onAddJournal: () -> Void = {}
    var onConnectWhoop: () -> Void = {}

    var isWhoopConnected = false
    var onSelectMetric: (TodayMetric) -> Void = { _ in }
    /// Passed straight through to the Fitness segment's training card. Nil in
    /// the previews, which have no app view models.
    var library: WorkoutLibraryViewModel?

    @Binding var section: HealthSection
    @Binding var selectedDate: Date

    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout

    var body: some View {
        ZStack {
            LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your health").font(.largeTitle.bold()).tracking(-0.7)
                        DatePicker("Viewing date", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                            .tint(LifeOSTokens.accent)
                    }
                    WeekStrip(selection: $selectedDate)
                        .padding(.top, 4)

                    trackingLinks

                    UnderlinePicker(
                        selection: $section,
                        options: HealthSection.allCases.map { ($0, $0.title) }
                    )

                    switch section {
                    case .health:
                        HealthSegmentView(recovery: recovery, weight: weight,
                                          wellness: wellness, selectedDate: selectedDate,
                                          onAddJournal: onAddJournal,
                                          onConnectWhoop: onConnectWhoop,
                                          isWhoopConnected: isWhoopConnected)
                    case .fitness:
                        FitnessSegmentView(activity: activity, recovery: recovery,
                                           wellness: wellness, library: library)
                    }
                }
                .frame(maxWidth: layout.maxContentWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, layout.gutter)
                .padding(.leading, layout.railInset)
                .padding(.bottom, layout.contentBottomInset)
            }
        }
        .tint(LifeOSTokens.accent)
        .animation(.easeInOut(duration: 0.25), value: section)
    }

    private var trackingLinks: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            ForEach(TodayMetric.allCases) { metric in
                Button { onSelectMetric(metric) } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: metric.icon).foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                            Text(metric.title).font(.subheadline.weight(.medium))
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption2)
                        }
                        Text(value(metric)).font(.title2.bold()).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("View history").font(.caption).foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    }
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .background(scheme == .dark ? metric.hue.pastelDark : metric.hue.pastel, in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(metric.title), \(value(metric)), \(selectedDate.formatted(date: .abbreviated, time: .omitted))")
                .accessibilityHint("Opens tracking history")
            }
        }
    }

    private func value(_ metric: TodayMetric) -> String {
        let reading: Double? = switch metric {
        case .steps: activity.steps.map(Double.init)
        case .sleep: recovery.sleepMinutes.map(Double.init)
        case .weight: weight.weightKg
        case .recovery: recovery.recoveryPct
        }
        return reading.map { metric.format($0) + (metric.unit.map { " " + $0 } ?? "") } ?? "Not recorded"
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

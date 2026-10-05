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
    /// Passed through with it, for the player the library pushes.
    var recorder: ActivityRecorder?

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
                        EditorialMasthead(eyebrow: "Health · \(selectedDate.formatted(.dateTime.weekday(.wide).month().day()))",
                                          title: "Your health")
                        DatePicker("Viewing date", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                            .tint(LifeOSTokens.primaryText.resolve(scheme))
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
                                           wellness: wellness, library: library, recorder: recorder)
                    }
                }
                .frame(maxWidth: layout.maxContentWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, layout.gutter)
                .padding(.leading, layout.railInset)
                .padding(.bottom, layout.contentBottomInset)
            }
        }
        .tint(LifeOSTokens.primaryText.resolve(scheme))
        .animation(.easeInOut(duration: 0.25), value: section)
    }

    /// The four tracked readings on the screen's one gradient field, set
    /// the way the reference sets its figures: the name small on the left,
    /// the number large and light on the right, a rule between rows. Each
    /// row opens that reading's history.
    private var trackingLinks: some View {
        EditorialField(.dusk) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your readings").font(LifeOSType.eyebrow).tracking(1.2).textCase(.uppercase).opacity(0.7)
                Spacer()
                IndexPill(1)
            }
            VStack(spacing: 0) {
                ForEach(Array(TodayMetric.allCases.enumerated()), id: \.element.id) { index, metric in
                    Button { onSelectMetric(metric) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
                            Label(metric.title, systemImage: metric.icon).font(LifeOSType.secondary)
                            Spacer(minLength: Space.x1)
                            let parts = figure(metric)
                            Text(parts.value)
                                .font(Editorial.figure(parts.isEmpty ? 20 : 40))
                                .tracking(parts.isEmpty ? 0 : Editorial.figureTracking(40))
                                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                            if let unit = parts.unit { Text(unit).font(LifeOSType.label).opacity(0.7) }
                            Image(systemName: "chevron.right").font(LifeOSType.caption.weight(.semibold)).opacity(0.6)
                        }
                        .padding(.vertical, 14)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .top) {
                        if index > 0 { Rectangle().fill(.primary.opacity(0.18)).frame(height: 1) }
                    }
                    .accessibilityLabel("\(metric.title), \(value(metric)), \(selectedDate.formatted(date: .abbreviated, time: .omitted))")
                    .accessibilityHint("Opens tracking history")
                }
            }
        }
    }

    /// The reading split for setting large: the number and its unit apart.
    private func figure(_ metric: TodayMetric) -> (value: String, unit: String?, isEmpty: Bool) {
        let reading: Double? = switch metric {
        case .steps: activity.steps.map(Double.init)
        case .sleep: recovery.sleepMinutes.map(Double.init)
        case .weight: weight.weightKg
        case .recovery: recovery.recoveryPct
        }
        guard let reading else { return ("Not recorded", nil, true) }
        return (metric.format(reading), metric.unit, false)
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

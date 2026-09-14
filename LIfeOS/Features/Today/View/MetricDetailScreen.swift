import SwiftUI
import DesignSystem
import SwiftData

/// One metric, on a page of its own: the figure, the window behind it, and
/// what the window adds up to.
///
/// Pushed from a tile on Today. The tile answers "how am I doing today"; this
/// answers "is that normal for me", which a seven-bar chart on a half-width
/// card cannot. It reads the store through its own view model rather than
/// taking a snapshot from Today, because the ranges past a week are history
/// Today never loads.
struct MetricDetailScreen: View {
    let metric: TodayMetric
    @Bindable var model: MetricDetailViewModel

    @Environment(\.colorScheme) private var scheme
    var onManageConnections: () -> Void = {}
    @State private var showingReadings = false

    @Environment(\.layout) private var layout

    private var snapshot: MetricDetailSnapshot { model.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                headline
                rangePicker
                chartCard
                summary
                readings
                trackingHelp
            }
            .frame(maxWidth: layout.maxContentWidth)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, layout.gutter)
            .padding(.leading, layout.railInset)
            .padding(.top, 12)
            .padding(.bottom, layout.contentBottomInset)
        }
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
        // Reloaded on the range as well as on appear, so the picker reads the
        // store once per change rather than the body re-deriving a year of
        // buckets on every render.
        .onChange(of: model.range) { _, _ in model.load(metric) }
        .task { model.load(metric) }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in model.load(metric) }
        .tint(LifeOSTokens.accent)
    }

    /// The figure, big, with the goal under it. The icon carries the module's
    /// colour the same way the tile it was tapped from does, so the push reads
    /// as the same object opening rather than as arriving somewhere new.
    private var headline: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: metric.icon)
                .font(LifeOSType.sectionTitle)
                .foregroundStyle(LifeOSTokens.accent)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 14).fill(LifeOSTokens.accent.opacity(0.08)))

            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.latestDate.map { "Latest · " + $0.formatted(.dateTime.month().day().year()) } ?? "No reading yet")
                    .font(.caption).foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(snapshot.latest.map(metric.format) ?? "—")
                        .font(LifeOSType.numeral)
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                        .opacity(snapshot.latest == nil ? 0.4 : 1)
                    if let unit = metric.unit, snapshot.latest != nil {
                        Text(unit)
                            .font(LifeOSType.label)
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)

                Text(subtitle)
                    .font(LifeOSType.label.weight(.regular))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }

            Spacer(minLength: 0)
        }
    }

    /// The goal where there is one, and the latest reading's standing against
    /// it. A metric with no target says what the window is instead, which is
    /// the only other honest thing to put there.
    private var subtitle: String {
        guard let goal = snapshot.goal else {
            return metric == .recovery ? "Your recorded recovery score" : "Track changes over time"
        }
        let target = metric.format(goal) + (metric.unit.map { " \($0)" } ?? "")
        guard let latest = snapshot.latest else { return "Goal \(target)" }
        return latest >= goal ? "Goal \(target) · met" : "Goal \(target)"
    }

    private var rangePicker: some View {
        UnderlinePicker(
            selection: $model.range,
            options: MetricRange.allCases.map { ($0, $0.title) }
        )
    }

    @ViewBuilder
    private var chartCard: some View {
        SoftCard {
            if snapshot.isEmpty {
                // An empty window is said in words. Thirty empty tracks and
                // thirty gap markers is a lot of chart to say nothing, and the
                // page has no figure above it to fall back on either.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nothing recorded")
                        .font(LifeOSType.rowTitle)
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    Text("No \(metric.title.lowercased()) recorded in this period. Check your connected sources or choose a longer range.")
                        .font(LifeOSType.label.weight(.regular))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: chartHeight, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                Text(model.range == .year ? "Monthly averages" : "Daily readings")
                    .font(.headline)
                RoundedBarChart(
                    bars: snapshot.chartBars,
                    hue: .habits,
                    goal: snapshot.goal,
                    baseline: metric.baseline,
                    // Thirty bars share the width seven had, so the gaps have
                    // to come out of the spacing or the bars stop being bars.
                    spacing: snapshot.bars.count > 14 ? 3 : 8,
                    height: chartHeight
                )
                Text(metric == .weight ? "Scale follows the recorded weight range. Gaps mean no reading." : (snapshot.goal == nil ? "Gaps mean no reading." : "Gaps mean no reading. Faded bars are below your saved goal."))
                    .font(.caption).foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }
            }
        }
    }

    private var chartHeight: CGFloat { layout.isRegular ? 200 : 160 }

    /// What the window adds up to. Weight gets low and high rather than a
    /// best, because there is no direction it is trying to go that this app
    /// has been told about.
    private var summary: some View {
        StatGroup(title: model.range == .year ? "Monthly summary" : "Daily summary", rows: summaryRows)
    }

    private var summaryRows: [StatGroup.Row] {
        let unit = metric.unit.map { " \($0)" } ?? ""
        func figure(_ value: Double?) -> String? {
            value.map { metric.format($0) + unit }
        }

        var rows: [StatGroup.Row] = [
            StatGroup.Row(label: model.range == .year ? "Average of months" : "Daily average", value: figure(snapshot.average))
        ]
        rows.append(StatGroup.Row(label: "Lowest", value: figure(snapshot.low)))
        rows.append(StatGroup.Row(label: "Highest", value: figure(snapshot.high)))
        rows.append(StatGroup.Row(label: model.range == .year ? "Months recorded" : "Days recorded",
                                 value: "\(snapshot.readingDays) of \(model.range.buckets)"))
        if let onTarget = snapshot.onTargetDays {
            rows.append(StatGroup.Row(
                label: model.range == .year ? "Months on target" : "Days on target",
                value: "\(onTarget) of \(snapshot.readingDays)"
            ))
        }
        return rows
    }

    @ViewBuilder private var readings: some View {
        if !snapshot.isEmpty {
            DisclosureGroup(isExpanded: $showingReadings) {
                VStack(spacing: 0) {
                    ForEach(snapshot.bars.reversed()) { bar in
                        HStack(alignment: .firstTextBaseline) {
                            Text(bar.date.formatted(model.range == .year ? .dateTime.month(.wide).year() : .dateTime.month().day().weekday(.abbreviated)))
                                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                            Spacer(minLength: 12)
                            Text(bar.value.map { metric.format($0) + (metric.unit.map { " " + $0 } ?? "") } ?? "Not recorded")
                                .monospacedDigit()
                        }
                        .font(.subheadline).padding(.vertical, 12)
                        Divider()
                    }
                }
            } label: {
                Text(model.range == .year ? "Monthly values" : "All readings").font(.headline).padding(.vertical, 8)
            }
            .padding(16)
            .background(LifeOSTokens.cardSurface.resolve(scheme), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var trackingHelp: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Keep your tracking connected", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
            Text(trackingCopy).font(.subheadline).foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            Button("Manage connections", action: onManageConnections)
                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(LifeOSTokens.cardSurface.resolve(scheme), in: RoundedRectangle(cornerRadius: 16))
    }

    private var trackingCopy: String {
        switch metric {
        case .steps: "Steps sync from connected sources. Your saved daily goal is shown above, and a missing day stays blank."
        case .sleep: "Sleep duration syncs from connected sources. Open Health for sleep stages and night-by-night detail."
        case .weight: "Record a weigh-in in Apple Health or a connected scale app. LifeOS shows it after sync, without treating weight gain or loss as a score."
        case .recovery: "Recovery scores come from WHOOP. A missing score stays blank; a higher score is not a daily task to complete."
        }
    }

}

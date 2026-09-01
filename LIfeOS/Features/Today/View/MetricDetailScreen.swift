import SwiftUI
import DesignSystem

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
    @Environment(\.layout) private var layout

    private var snapshot: MetricDetailSnapshot { model.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                headline
                rangePicker
                chartCard
                summary
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
    }

    /// The figure, big, with the goal under it. The icon carries the module's
    /// colour the same way the tile it was tapped from does, so the push reads
    /// as the same object opening rather than as arriving somewhere new.
    private var headline: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: metric.icon)
                .font(LifeOSType.sectionTitle)
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .frame(width: 52, height: 52)
                .background(Circle().fill(scheme == .dark ? metric.hue.pastelDark : metric.hue.pastel))

            VStack(alignment: .leading, spacing: 2) {
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
            return "Last \(snapshot.readingDays) \(snapshot.readingDays == 1 ? "reading" : "readings")"
        }
        let target = metric.format(goal) + (metric.unit.map { " \($0)" } ?? "")
        guard let latest = snapshot.latest else { return "Goal \(target)" }
        return latest >= goal ? "Goal \(target) · met" : "Goal \(target)"
    }

    private var rangePicker: some View {
        SegmentedPill(
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
                    Text("No \(metric.title.lowercased()) in this window. It fills in as Apple Health and Whoop sync.")
                        .font(LifeOSType.label.weight(.regular))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: chartHeight, alignment: .center)
            } else {
                RoundedBarChart(
                    bars: snapshot.chartBars,
                    hue: metric.hue,
                    goal: snapshot.goal,
                    baseline: metric.baseline,
                    // Thirty bars share the width seven had, so the gaps have
                    // to come out of the spacing or the bars stop being bars.
                    spacing: snapshot.bars.count > 14 ? 3 : 8,
                    height: chartHeight
                )
            }
        }
    }

    private var chartHeight: CGFloat { layout.isRegular ? 200 : 160 }

    /// What the window adds up to. Weight gets low and high rather than a
    /// best, because there is no direction it is trying to go that this app
    /// has been told about.
    private var summary: some View {
        StatGroup(title: model.range.title, rows: summaryRows)
    }

    private var summaryRows: [StatGroup.Row] {
        let unit = metric.unit.map { " \($0)" } ?? ""
        func figure(_ value: Double?) -> String? {
            value.map { metric.format($0) + unit }
        }

        var rows: [StatGroup.Row] = [
            StatGroup.Row(label: "Average", value: figure(snapshot.average))
        ]
        if metric.higherIsBetter {
            rows.append(StatGroup.Row(label: "Best", value: figure(snapshot.high)))
        } else {
            rows.append(StatGroup.Row(label: "Low", value: figure(snapshot.low)))
            rows.append(StatGroup.Row(label: "High", value: figure(snapshot.high)))
        }
        if let onTarget = snapshot.onTargetDays {
            rows.append(StatGroup.Row(
                label: model.range == .year ? "Months on target" : "Days on target",
                value: "\(onTarget) of \(snapshot.readingDays)"
            ))
        }
        return rows
    }
}

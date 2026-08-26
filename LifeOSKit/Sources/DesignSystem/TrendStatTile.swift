import SwiftUI

/// A dashboard card for one metric: the module's icon in a pastel bubble, the
/// day's figure, and the week behind it.
///
/// The same card as `IconBubbleTile` with the week added, rather than a second
/// card language: a screen that shows both should not look like two designs.
/// The week is the point — a step count alone says nothing about whether it is
/// a good day, and a bare progress bar could only ever say that about today.
public struct TrendStatTile: View {
    private let icon: String
    private let hue: ModuleHue
    private let label: String
    private let value: String?
    private let unit: String?
    private let series: TrendSeries
    private let goal: Double?
    private let baseline: RoundedBarChart.Baseline

    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout
    private let calendar = Calendar.current

    /// - Parameters:
    ///   - value: The formatted figure. Nil renders an em dash, never a zero.
    ///   - goal: Days below it draw faded. Nil for a metric with no target.
    public init(
        icon: String,
        hue: ModuleHue,
        label: String,
        value: String?,
        unit: String? = nil,
        series: TrendSeries,
        goal: Double? = nil,
        baseline: RoundedBarChart.Baseline = .zero
    ) {
        self.icon = icon
        self.hue = hue
        self.label = label
        self.value = value
        self.unit = unit
        self.series = series
        self.goal = goal
        self.baseline = baseline
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            numeral
            // A week with no readings at all draws seven empty tracks and seven
            // gap markers, which is a lot of chart to say nothing. The card
            // falls back to the plain figure until there is a week to show —
            // but still holds the chart's space, so a dataless tile stands the
            // same height as its siblings in the grid.
            if series.hasAnyReading {
                chart
            } else {
                Color.clear.frame(height: chartHeight)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LifeOSTokens.cardSurface.resolve(scheme))
                .shadow(color: scheme == .dark ? .clear : LifeOSTokens.cardShadow, radius: 12, y: 4)
        )
    }

    private var header: some View {
        HStack {
            Text(label)
                .font(LifeOSType.label)
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            Spacer(minLength: 4)
            Image(systemName: icon)
                .font(LifeOSType.rowTitle)
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .frame(width: 38, height: 38)
                .background(Circle().fill(scheme == .dark ? hue.pastelDark : hue.pastel))
        }
    }

    private var numeral: some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(value ?? "—")
                .font(LifeOSType.numeral)
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .opacity(value == nil ? 0.4 : 1)
            if let unit, value != nil {
                Text(unit)
                    .font(LifeOSType.label)
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    /// Two of these sit side by side on a phone, so the bars get about twenty
    /// points of column each. The wide pane can afford the roomier spacing the
    /// full-width charts use.
    private var chart: some View {
        RoundedBarChart(
            bars: series.points.map {
                RoundedBarChart.Bar(id: $0.date, label: Self.initial(of: $0.date, calendar), value: $0.value)
            },
            hue: hue,
            goal: goal,
            baseline: baseline,
            spacing: layout.isRegular ? 8 : 5,
            height: chartHeight
        )
    }

    /// `RoundedBarChart` resolves to exactly this height, bars and labels
    /// included, so the dataless placeholder can match it to the point.
    private var chartHeight: CGFloat {
        layout.isRegular ? 88 : 74
    }

    /// One letter, because seven of them share a half-width card.
    static func initial(of date: Date, _ calendar: Calendar) -> String {
        let weekday = calendar.component(.weekday, from: date)
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.indices.contains(weekday - 1) else { return "" }
        return symbols[weekday - 1]
    }
}

#Preview {
    let week = (0..<7).map { offset in
        TrendPoint(
            date: Calendar.current.date(byAdding: .day, value: offset - 6, to: .now) ?? .now,
            value: offset == 3 ? nil : Double(6_000 + offset * 900)
        )
    }
    HStack(spacing: 12) {
        TrendStatTile(icon: "figure.walk", hue: .activity, label: "Steps",
                      value: "9,770", series: TrendSeries(points: week), goal: 10_000)
        TrendStatTile(icon: "scalemass.fill", hue: .body, label: "Weight",
                      value: "78.0", unit: "kg",
                      series: TrendSeries(points: week), baseline: .windowMinimum)
    }
    .padding()
    .background(LifeOSTokens.canvas.resolve(.light))
}

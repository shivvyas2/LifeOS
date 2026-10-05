import SwiftUI

/// The reference design's weekly chart: a full-height soft track per day with
/// a solid rounded bar inside it, scaled across the week.
public struct RoundedBarChart: View {
    public struct Bar: Identifiable, Equatable, Sendable {
        public let id: Date
        public let label: String
        public let value: Double?

        public init(id: Date, label: String, value: Double?) {
            self.id = id
            self.label = label
            self.value = value
        }
    }

    /// What the bottom of a bar means.
    public enum Baseline: Sendable, Equatable {
        /// Bars are read against nought. Right for a count that starts each day
        /// at nought and accumulates: steps, calories, minutes asleep.
        case zero
        /// Bars are read against the week's own low. Right for a measurement
        /// that never approaches nought. Body weight moves about a percent over
        /// a week, so against nought the seven bars are indistinguishable and
        /// the chart says nothing the number has not already said.
        case windowMinimum
    }

    /// What colours the bars. The accent is the app-wide default; a module hue
    /// is for the metric screens that still carry one; ink is for a chart on
    /// the editorial dusk field, where the only colours are ink and the rule.
    public enum Style: Sendable, Equatable {
        case accent
        case hue(ModuleHue)
        case ink
    }

    private let bars: [Bar]
    private let style: Style
    private let goal: Double?
    private let baseline: Baseline
    private let spacing: CGFloat
    private let height: CGFloat
    @Environment(\.colorScheme) private var scheme

    public init(
        bars: [Bar],
        style: Style = .accent,
        goal: Double? = nil,
        baseline: Baseline = .zero,
        spacing: CGFloat = 10,
        height: CGFloat = 150
    ) {
        self.bars = bars
        self.style = style
        self.goal = goal
        self.baseline = baseline
        self.spacing = spacing
        self.height = height
    }

    /// The older spelling. `hue` has no default here on purpose: with one,
    /// `RoundedBarChart(bars:)` would match both initialisers.
    public init(
        bars: [Bar],
        hue: ModuleHue?,
        goal: Double? = nil,
        baseline: Baseline = .zero,
        spacing: CGFloat = 10,
        height: CGFloat = 150
    ) {
        self.init(bars: bars, style: hue.map(Style.hue) ?? .accent, goal: goal,
                  baseline: baseline, spacing: spacing, height: height)
    }

    public static func fraction(
        of value: Double,
        in readings: [Double],
        baseline: Baseline
    ) -> Double {
        switch baseline {
        case .zero:
            let peak = max(readings.max() ?? value, value, 1)
            return min(max(value / peak, 0), 1)
        case .windowMinimum:
            guard let low = readings.min(), let high = readings.max(), high > low else {
                return 0.5
            }
            return min(max((value - low) / (high - low), 0), 1)
        }
    }

    public var body: some View {
        let readings = bars.compactMap(\.value)

        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(bars) { bar in
                VStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .bottom) {
                            // The track: always full height, so a light week
                            // still reads as seven days, not four.
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(trackFill)
                            if let value = bar.value {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(barFill)
                                    .opacity(meetsGoal(value) ? 1 : 0.45)
                                    .frame(height: max(
                                        geo.size.height
                                            * Self.fraction(of: value, in: readings, baseline: baseline),
                                        10
                                    ))
                            } else {
                                // A day with no reading is a gap, not a zero.
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(LifeOSTokens.dotMissed.resolve(scheme))
                                    .frame(height: 6)
                            }
                        }
                    }

                    Text(bar.label)
                        .font(LifeOSType.eyebrow.weight(.medium))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }
            }
        }
        .frame(height: height)
    }

    private func meetsGoal(_ value: Double) -> Bool {
        guard let goal else { return true }
        return value >= goal
    }

    static func barFill(_ style: Style, scheme: ColorScheme) -> Color {
        switch style {
        case .accent: LifeOSTokens.accent
        case .hue(let hue): hue.top
        case .ink: LifeOSTokens.primaryText.resolve(scheme)
        }
    }

    static func trackFill(_ style: Style, scheme: ColorScheme) -> Color {
        switch style {
        case .accent: LifeOSTokens.accentSoft.resolve(scheme)
        case .hue(let hue): scheme == .dark ? hue.pastelDark : hue.pastel
        case .ink: Editorial.rule(scheme)
        }
    }

    private var barFill: Color { Self.barFill(style, scheme: scheme) }
    private var trackFill: Color { Self.trackFill(style, scheme: scheme) }
}

#Preview {
    let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    let bars = days.enumerated().map { index, label in
        RoundedBarChart.Bar(id: Date().addingTimeInterval(Double(index) * 86_400),
                            label: label,
                            value: index == 4 ? nil : Double(200 + index * 130))
    }
    VStack(spacing: 24) {
        RoundedBarChart(bars: bars)
        RoundedBarChart(bars: bars, hue: .activity, goal: 600, spacing: 5, height: 90)
    }
    .padding()
    .background(LifeOSTokens.canvas.resolve(.light))
}

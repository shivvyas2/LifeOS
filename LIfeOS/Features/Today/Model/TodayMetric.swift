import Foundation
import DesignSystem
import Persistence

/// One of the figures Today puts on a tile, and everything needed to draw it
/// at either size: a tile in the grid, or a page of its own.
///
/// The tile and the detail page used to be able to disagree — the grid decided
/// steps were `figure.walk` in the activity hue and a second screen would have
/// decided again — so icon, hue, unit and formatting live here once and both
/// read them. It also gives the navigation destination something to be: a
/// value the stack can carry, rather than four booleans.
enum TodayMetric: String, Identifiable, Hashable, CaseIterable {
    case steps, sleep, weight, recovery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps:    "Steps"
        case .sleep:    "Sleep"
        case .weight:   "Weight"
        case .recovery: "Recovery"
        }
    }

    var icon: String {
        switch self {
        case .steps:    "figure.walk"
        case .sleep:    "moon.fill"
        case .weight:   "scalemass.fill"
        case .recovery: "bolt.heart.fill"
        }
    }

    var hue: ModuleHue {
        switch self {
        case .steps:    .activity
        case .sleep:    .nutrition
        case .weight:   .body
        case .recovery: .recovery
        }
    }

    /// Rendered beside the figure, never inside it, so the numeral stays one
    /// glyph run that can be scaled down on a narrow tile.
    var unit: String? {
        switch self {
        case .steps, .sleep: nil
        case .weight:        "kg"
        case .recovery:      "%"
        }
    }

    /// Weight is read against its own window rather than against nought: it
    /// moves about a percent over a week, so bars measured from zero are
    /// indistinguishable and say nothing the figure has not already said.
    var baseline: RoundedBarChart.Baseline {
        self == .weight ? .windowMinimum : .zero
    }

    /// Whether a higher reading is the better one. Weight is the exception,
    /// and it is the reason the summary panel cannot say "best" for everything.
    var higherIsBetter: Bool { self != .weight }

    /// The reading this metric takes from a stored day, or nil where the day
    /// has none. Kept here rather than in the view model so the tile grid and
    /// the detail page cannot read a day differently.
    func value(in row: DailyMetrics) -> Double? {
        switch self {
        case .steps:    row.steps.map(Double.init)
        case .sleep:    row.sleepMinutes.map(Double.init)
        case .weight:   row.weightKg
        case .recovery: row.whoopRecoveryPct
        }
    }

    /// The goal a day is judged against, or nil for a metric with no target.
    /// Weight and recovery have none: one is not a target to hit and the other
    /// is a score the body returns rather than something to aim at.
    func goal(in targets: GoalTargets) -> Double? {
        switch self {
        case .steps:              Double(targets.steps)
        case .sleep:              Double(targets.sleepMinutes)
        case .weight, .recovery:  nil
        }
    }

    /// The figure as it is written, without its unit.
    func format(_ value: Double) -> String {
        switch self {
        case .steps:    Int(value.rounded()).formatted()
        case .sleep:    Self.duration(Int(value.rounded()))
        case .weight:   String(format: "%.1f", value)
        case .recovery: "\(Int(value.rounded()))"
        }
    }

    static func duration(_ minutes: Int) -> String {
        "\(minutes / 60)h \(minutes % 60)m"
    }
}

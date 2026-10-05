import SwiftUI
import Charts
import DesignSystem

/// The three Money charts. One ink at stepped opacity, no y-axis, no grid:
/// the figure above each chart is the number, the marks are the shape. A
/// pastel categorical palette was run through the dataviz validator and
/// failed every check, which is the long way of saying what the one-ink rule
/// already said.

// MARK: - This week

struct MoneyWeekChart: View {
    let days: [DaySpend]
    var height: CGFloat = 110
    @Environment(\.colorScheme) private var scheme

    private var peak: Double { max(days.map(\.amount).max() ?? 0, 1) }

    var body: some View {
        Chart(days) { day in
            // An empty track for every day, so a day still to come is
            // visibly a slot and not a gap.
            //
            // Both marks are unstacked: two bars at one x stack by default,
            // which drew each day's spend on top of its own full-height
            // track, ran the busiest day off the top of the chart, and laid
            // it over the heading above.
            BarMark(x: .value("Day", day.date, unit: .day), y: .value("Track", peak), stacking: .unstacked)
                .foregroundStyle(MoneyPalette.ink.resolve(scheme).opacity(0.07))
                .cornerRadius(4)

            if !day.isFuture {
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Spent", day.amount), stacking: .unstacked)
                    .foregroundStyle(MoneyPalette.ink.resolve(scheme).opacity(day.isToday ? 1 : 0.32))
                    .cornerRadius(4)
                    .annotation(position: .top, spacing: 4) {
                        if day.isToday, day.amount > 0 {
                            Text(day.amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                                .font(LifeOSType.eyebrow.weight(.semibold))
                                .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                        }
                    }
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...(peak * 1.25))
        .chartXAxis {
            AxisMarks(values: days.map(\.date)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(LifeOSType.eyebrow)
                            .foregroundStyle(MoneyPalette.quietInk(scheme))
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: height)
        .accessibilityLabel("Spending this week by day")
    }
}

// MARK: - Where it went

struct MoneyDonut: View {
    let slices: [CategorySlice]
    var size: CGFloat = 128
    var onSelect: (CategorySlice) -> Void = { _ in }
    @Environment(\.colorScheme) private var scheme
    @State private var selectedAmount: Double?

    var body: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value("Share", slice.amount),
                innerRadius: .ratio(0.62),
                // The paper gap between fills, so two adjacent steps of the
                // same ink read as two slices and not a gradient.
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(MoneyPalette.ink.resolve(scheme).opacity(slice.opacity))
        }
        .chartLegend(.hidden)
        .chartAngleSelection(value: $selectedAmount)
        .onChange(of: selectedAmount) { _, amount in
            guard let amount, let slice = slice(at: amount) else { return }
            selectedAmount = nil
            if !slice.isOther { onSelect(slice) }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Spending by category")
        .accessibilityValue(slices.map { "\($0.name) \(Int($0.share * 100)) percent" }.joined(separator: ", "))
    }

    /// `chartAngleSelection` reports a position along the cumulative angle
    /// value, in the data's own units. Walk the slices until it is passed.
    private func slice(at amount: Double) -> CategorySlice? {
        var running = 0.0
        for slice in slices {
            running += slice.amount
            if amount <= running { return slice }
        }
        return slices.last
    }
}

// MARK: - Six months

struct MonthSpend: Equatable, Identifiable {
    let monthStart: Date
    let amount: Double
    let isCurrent: Bool

    var id: Date { monthStart }
}

struct MoneyMonthsChart: View {
    let months: [MonthSpend]
    /// Across the completed months. Nil until there is one.
    let average: Double?
    var height: CGFloat = 140
    @Environment(\.colorScheme) private var scheme

    private var peak: Double { max(months.map(\.amount).max() ?? 0, average ?? 0, 1) }

    var body: some View {
        Chart {
            ForEach(months) { month in
                BarMark(x: .value("Month", month.monthStart, unit: .month),
                        y: .value("Spent", month.amount))
                    .foregroundStyle(MoneyPalette.ink.resolve(scheme).opacity(month.isCurrent ? 1 : 0.32))
                    .cornerRadius(4)
                    .annotation(position: .top, spacing: 4) {
                        if month.isCurrent, month.amount > 0 {
                            Text(month.amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                                .font(LifeOSType.eyebrow.weight(.semibold))
                                .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                        }
                    }
            }
            if let average, average > 0 {
                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(MoneyPalette.ink.resolve(scheme).opacity(0.4))
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...(peak * 1.25))
        .chartXAxis {
            AxisMarks(values: months.map(\.monthStart)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.month(.abbreviated)))
                            .font(LifeOSType.eyebrow)
                            .foregroundStyle(MoneyPalette.quietInk(scheme))
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: height)
        .accessibilityLabel("Spending over the last six months")
    }
}

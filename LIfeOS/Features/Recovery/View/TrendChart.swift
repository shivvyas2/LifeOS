import SwiftUI
import Charts
import DesignSystem

/// One metric across the fortnight.
///
/// A line rather than bars. Fourteen bars is fourteen blocks of saturated
/// colour reading as a wall; the shape of a fortnight is a direction, and a
/// line is what draws a direction. The bars also spent the card's whole colour
/// budget on quantity that the axis already carried.
///
/// The chrome is deliberately almost absent: no gridlines, no y-axis, two date
/// labels. What a reader wants from this card is the current figure and the
/// shape behind it, and every rule drawn across the plot competes with the
/// shape for attention.
struct TrendChart: View {
    let title: String
    let unit: String?
    let series: TrendSeries
    var color: Color = ModuleHue.recovery.top

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Nothing recorded means no chart, not an empty axis.
        if series.hasAnyReading {
            GlassPanel {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    plot
                    footer
                }
            }
        }
    }

    // MARK: - Header

    /// The figure lives in the header at display size, in text ink rather than
    /// the series colour.
    ///
    /// Two reasons it is not inside the plot. The palette check flags the
    /// warmer module hues as under 3:1 on this surface, and the relief for
    /// that is a visible label rather than a colour a reader has to resolve.
    /// And a number per point is chaos: one figure, the current one, is what
    /// this card is for.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))

            Spacer(minLength: Space.x1)

            if let latest = series.latest {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(formatted(latest))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    if let unit {
                        Text(unit)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    }
                }
            }
        }
    }

    // MARK: - Plot

    private var plot: some View {
        Chart {
            // The baseline first, so the line and its marker draw over it.
            // Solid, not dashed: a dashed rule reads as a projection or a
            // threshold, and this is neither. It is where the fortnight sits.
            if let average = series.average {
                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme).opacity(0.25))
            }

            ForEach(segments, id: \.id) { segment in
                ForEach(segment.points) { point in
                    if let value = point.value {
                        // The wash under the line carries the shape at a
                        // glance without the saturated hue occupying a block.
                        AreaMark(
                            x: .value("Day", point.date, unit: .day),
                            y: .value(title, value),
                            series: .value("Run", segment.id)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [color.opacity(0.22), color.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Day", point.date, unit: .day),
                            y: .value(title, value),
                            series: .value("Run", segment.id)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .foregroundStyle(color)
                    }
                }
            }

            // The current reading, ringed in the surface colour so it stays
            // legible where it lands on top of the line.
            if let last = series.points.last(where: { $0.value != nil }),
               let value = last.value {
                PointMark(
                    x: .value("Day", last.date, unit: .day),
                    y: .value(title, value)
                )
                .symbolSize(80)
                .foregroundStyle(color)

                PointMark(
                    x: .value("Day", last.date, unit: .day),
                    y: .value(title, value)
                )
                .symbolSize(24)
                .foregroundStyle(LifeOSTokens.cardSurface.resolve(scheme))
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis(.hidden)
        // Padded rather than tight to the data: a line that touches the top of
        // its own frame reads as clipped.
        .chartYScale(domain: paddedDomain)
        .frame(height: 96)
        // The area fill runs to the bottom of the y-domain, which sits below
        // the frame; without this it spills out of the card and over whatever
        // is beneath it.
        .clipped()
    }

    // MARK: - Footer

    /// Two dates and the standing of the current reading. This is the whole
    /// axis: fourteen tick labels on a card this size is a wall of grey text
    /// nobody reads, and the only dates that answer anything are the ends.
    private var footer: some View {
        HStack {
            if let first = series.points.first?.date {
                Text(first, format: .dateTime.day().month(.abbreviated))
            }
            Spacer()
            if let delta = series.deltaFromAverage, let average = series.average, average != 0 {
                Text(standing(delta))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
            Spacer()
            if let last = series.points.last?.date {
                Text(last, format: .dateTime.day().month(.abbreviated))
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme).opacity(0.7))
    }

    /// Where today sits against the fortnight, in words.
    ///
    /// Descriptive, never diagnostic: this says what the number is doing, not
    /// what it means for the person. "Above your average" is a fact; "you are
    /// recovering well" is a claim this app does not get to make.
    private func standing(_ delta: Double) -> String {
        if abs(delta) < 0.05 { return "at your average" }
        return delta > 0
            ? "\(formatted(abs(delta))) above your average"
            : "\(formatted(abs(delta))) below your average"
    }

    // MARK: - Shape

    /// A run of consecutive days that all have readings.
    ///
    /// Swift Charts joins a line straight across a day it was given no mark
    /// for, which would draw a reading that never happened. Splitting the
    /// window into runs and giving each its own series keeps the gap a gap.
    private struct Segment {
        let id: Int
        let points: [TrendPoint]
    }

    private var segments: [Segment] {
        var runs: [Segment] = []
        var current: [TrendPoint] = []

        for point in series.points {
            if point.value != nil {
                current.append(point)
            } else if !current.isEmpty {
                runs.append(Segment(id: runs.count, points: current))
                current = []
            }
        }
        if !current.isEmpty { runs.append(Segment(id: runs.count, points: current)) }
        return runs
    }

    /// The data's own range with a tenth of headroom either side, never
    /// anchored at zero: these are physiological readings, and a resting heart
    /// rate plotted from zero is a flat line with no shape in it at all.
    private var paddedDomain: ClosedRange<Double> {
        let values = series.points.compactMap(\.value)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let span = max(high - low, abs(high) * 0.05, 0.5)
        return (low - span * 0.25)...(high + span * 0.25)
    }

    private func formatted(_ value: Double) -> String {
        value >= 100 ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

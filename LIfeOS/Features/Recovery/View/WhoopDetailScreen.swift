import SwiftUI
import Charts
import DesignSystem

/// The fortnight behind today's card.
struct WhoopDetailScreen: View {
    let snapshot: RecoverySnapshot

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // First, because it is the only chart here showing structure
                // rather than quantity. A short night and a fragmented night
                // look identical on the duration chart below and obviously
                // different here, which is the reason the stages are ingested.
                SleepCompositionChart(nights: snapshot.nights)

                TrendChart(title: "Recovery", unit: "%", series: snapshot.recoveryTrend)
                TrendChart(title: "Day strain", unit: nil, series: snapshot.strainTrend)
                TrendChart(title: "Sleep", unit: "min", series: snapshot.sleepTrend)
                TrendChart(title: "HRV", unit: "ms", series: snapshot.hrvTrend)
                TrendChart(title: "Resting heart rate", unit: "bpm", series: snapshot.restingHRTrend)
            }
            .padding(20)
            .padding(.bottom, 60)
        }
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
        .navigationTitle("14 days")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One metric over the window, with the baseline drawn in.
struct TrendChart: View {
    let title: String
    let unit: String?
    let series: TrendSeries

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Nothing recorded means no chart, not an empty axis.
        if series.points.contains(where: { $0.value != nil }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    Spacer()
                    if let average = series.average {
                        Text("avg \(formatted(average))\(unit.map { " \($0)" } ?? "")")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    }
                }

                Chart {
                    // A day with no reading contributes no mark at all, so the
                    // gap stays visible instead of being drawn as a zero.
                    ForEach(series.points) { point in
                        if let value = point.value {
                            BarMark(
                                x: .value("Day", point.date, unit: .day),
                                y: .value(title, value)
                            )
                            .foregroundStyle(LifeOSTokens.accent.opacity(0.85))
                            .cornerRadius(3)
                        }
                    }
                    if let average = series.average {
                        RuleMark(y: .value("Average", average))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme).opacity(0.6))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 4)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .frame(height: 120)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LifeOSTokens.cardSurface.resolve(scheme))
            )
        }
    }

    private func formatted(_ value: Double) -> String {
        value >= 100 ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

/// Sleep stages stacked per night.
struct SleepCompositionChart: View {
    let nights: [SleepComposition]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if !nights.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sleep composition")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))

                Chart {
                    ForEach(nights) { night in
                        ForEach(night.segments) { segment in
                            BarMark(
                                x: .value("Night", night.date, unit: .day),
                                y: .value("Minutes", segment.minutes)
                            )
                            .foregroundStyle(by: .value("Stage", segment.stage.label))
                        }
                    }
                }
                .chartForegroundStyleScale([
                    SleepComposition.Stage.sws.label:   SleepComposition.Stage.sws.color,
                    SleepComposition.Stage.rem.label:   SleepComposition.Stage.rem.color,
                    SleepComposition.Stage.light.label: SleepComposition.Stage.light.color,
                    SleepComposition.Stage.awake.label: SleepComposition.Stage.awake.color,
                ])
                .chartYAxis {
                    // Hours read; minutes do not, at this scale.
                    AxisMarks { value in
                        AxisValueLabel {
                            if let minutes = value.as(Int.self) { Text("\(minutes / 60)h") }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 4)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .chartLegend(position: .bottom, spacing: 8)
                .frame(height: 180)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LifeOSTokens.cardSurface.resolve(scheme))
            )
        }
    }
}

#Preview {
    let day = Calendar.current.startOfDay(for: .now)
    func series(_ values: [Double?]) -> TrendSeries {
        TrendSeries(points: values.enumerated().map { offset, value in
            TrendPoint(date: Calendar.current.date(byAdding: .day, value: offset - 13, to: day)!,
                       value: value)
        })
    }

    return NavigationStack {
        WhoopDetailScreen(snapshot: RecoverySnapshot(
            recoveryTrend: series([61, 72, nil, 48, 55, 80, 77, 64, 59, 71, 83, 66, 74, 72]),
            strainTrend: series([12.1, 14.2, 8.0, 16.4, 11.2, 9.8, 13.3, 15.1, 10.0, 12.8,
                                 17.2, 11.9, 13.0, 14.2]),
            sleepTrend: series([412, 432, 388, 401, 455, 470, 420, 398, 441, 462, 409, 430,
                                448, 432]),
            nights: (0..<14).map { offset in
                SleepComposition(
                    date: Calendar.current.date(byAdding: .day, value: offset - 13, to: day)!,
                    lightMinutes: 200 + offset * 3,
                    remMinutes: 90 + offset,
                    swsMinutes: 95 - offset,
                    awakeMinutes: 10 + offset % 5
                )
            }
        ))
    }
}

import SwiftUI
import Charts
import DesignSystem

/// The fortnight behind today's card.
struct WhoopDetailScreen: View {
    let snapshot: RecoverySnapshot

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // First, because it is the only chart here showing structure
                    // rather than quantity. A short night and a fragmented night
                    // look identical on the duration chart below and obviously
                    // different here, which is the reason the stages are ingested.
                    SleepCompositionChart(nights: snapshot.nights)

                    TrendChart(title: "Recovery", unit: "%", series: snapshot.recoveryTrend,
                               color: LifeOSTokens.primaryText.resolve(scheme))
                    TrendChart(title: "Day strain", unit: nil, series: snapshot.strainTrend,
                               color: LifeOSTokens.primaryText.resolve(scheme))
                    TrendChart(title: "Sleep", unit: "min", series: snapshot.sleepTrend,
                               color: SleepComposition.Stage.rem.color)
                    TrendChart(title: "HRV", unit: "ms", series: snapshot.hrvTrend,
                               color: LifeOSTokens.primaryText.resolve(scheme))
                    TrendChart(title: "Resting heart rate", unit: "bpm",
                               series: snapshot.restingHRTrend, color: LifeOSTokens.primaryText.resolve(scheme))
                }
                .padding(20)
                .padding(.bottom, 60)
                .safeAreaInset(edge: .top) {
                    EditorialMasthead(eyebrow: "WHOOP · last 14 days", title: "Your trends",
                                      detail: "Each chart is one reading over the fortnight; gaps are days without data.")
                        .padding(.horizontal, 20).padding(.top, 8)
                }
            }
        }
        .navigationTitle("14 days")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One column per night so composition is compared by eye, not stacked inside
/// a single chart box.
struct SleepCompositionChart: View {
    let nights: [SleepComposition]

    @Environment(\.colorScheme) private var scheme

    private var shown: [SleepComposition] {
        Array(nights.suffix(14))
    }

    var body: some View {
        if !shown.isEmpty {
            SoftCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Sleep composition")
                        .font(LifeOSType.rowTitle)
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))

                    HStack(spacing: 12) {
                        ForEach([
                            SleepComposition.Stage.sws,
                            .rem,
                            .light,
                            .awake
                        ], id: \.self) { stage in
                            HStack(spacing: 5) {
                                Capsule()
                                    .fill(stage.color)
                                    .frame(width: 10, height: 8)
                                Text(stage.label)
                                    .font(LifeOSType.eyebrow)
                                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                            }
                        }
                    }

                    SleepNightStrip(nights: shown)
                }
            }
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

import SwiftUI
import DesignSystem

struct TodayScreen: View {
    let snapshot: TodaySnapshot
    /// Raised when a dot for a real, non-future day is tapped. The screen stays
    /// a pure function of its inputs: it does not decide what a day opens.
    let onSelectDay: (Date) -> Void

    @Environment(\.colorScheme) private var scheme
    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                MonthCalendarView(
                    date: snapshot.date,
                    cells: snapshot.cells,
                    calendar: calendar,
                    today: snapshot.date,
                    onTap: { cell in
                        // `DotGrid` only calls this for tappable cells, which
                        // always carry a date. The guard is belt and braces.
                        if let date = cell.date { onSelectDay(date) }
                    }
                )

                streakLine

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SolidCard {
                        StatTile(
                            label: "Steps",
                            value: snapshot.steps.map { $0.formatted() },
                            progress: snapshot.stepsProgress
                        )
                    }
                    SolidCard {
                        StatTile(
                            label: "Sleep",
                            value: snapshot.sleepMinutes.map(Self.duration),
                            progress: snapshot.sleepProgress
                        )
                    }
                    SolidCard {
                        StatTile(
                            label: "Weight",
                            value: snapshot.weightKg.map { String(format: "%.1f", $0) },
                            unit: "kg"
                        )
                    }
                    SolidCard {
                        StatTile(
                            label: "Recovery",
                            value: snapshot.recoveryPct.map { "\(Int($0))" },
                            unit: "%"
                        )
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 140)
        }
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
    }

    private var streakLine: some View {
        HStack(spacing: 6) {
            Text("\(snapshot.streak)")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(LifeOSTokens.accent)
            Text(snapshot.streak == 1 ? "day streak" : "day streak")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
        }
    }

    static func duration(_ minutes: Int) -> String {
        "\(minutes / 60)h \(minutes % 60)m"
    }
}

#Preview {
    TodayScreen(
        snapshot: TodaySnapshot(
            cells: (0..<35).map { DotCell(id: $0, date: nil, state: $0 < 10 ? .onTarget : ($0 == 10 ? .today : .future)) },
            streak: 6,
            steps: 8432,
            stepsProgress: 1.05,
            sleepMinutes: 432,
            sleepProgress: 0.9,
            weightKg: 77.4,
            recoveryPct: nil
        ),
        onSelectDay: { _ in }
    )
}

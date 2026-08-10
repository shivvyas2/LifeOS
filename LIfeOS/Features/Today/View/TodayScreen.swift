import SwiftUI
import DesignSystem

struct TodayScreen: View {
    let snapshot: TodaySnapshot

    @Environment(\.colorScheme) private var scheme
    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                MonthCalendarView(
                    date: snapshot.date,
                    cells: snapshot.cells,
                    calendar: calendar,
                    today: snapshot.date
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
    TodayScreen(snapshot: TodaySnapshot(
        cells: (0..<35).map { DotCell(id: $0, date: nil, state: $0 < 10 ? .onTarget : ($0 == 10 ? .today : .future)) },
        streak: 6,
        steps: 8432,
        stepsProgress: 1.05,
        sleepMinutes: 432,
        sleepProgress: 0.9,
        weightKg: 77.4,
        recoveryPct: nil
    ))
}

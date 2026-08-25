import SwiftUI
import DesignSystem

struct TodayScreen: View {
    let snapshot: TodaySnapshot
    /// Raised when a dot for a real, non-future day is tapped. The screen stays
    /// a pure function of its inputs: it does not decide what a day opens.
    let onSelectDay: (Date) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout
    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            // No `maxContentWidth` here: both arrangements are grids, and the
            // cap exists for prose and single columns. On a phone it is
            // `.infinity` regardless, so this only ever concerned the wide pane,
            // where the two columns should have the whole of it.
            layoutBody
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, layout.gutter)
                .padding(.leading, layout.railInset)
                .padding(.top, 24)
                .padding(.bottom, layout.contentBottomInset)
        }
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
    }

    /// One column on a phone, two side by side on a wide pane.
    ///
    /// Not just a column count: the month has to be *narrower* than the pane,
    /// not wider. A dot grid divides whatever width it is given by seven, so a
    /// full-width month on a 1300pt pane draws 170pt dots and shoves every stat
    /// below the fold — the opposite of what more room should buy. Standing the
    /// stats beside it fixes both at once.
    @ViewBuilder
    private var layoutBody: some View {
        if layout.isRegular {
            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading, spacing: 22) {
                    month
                    streakLine
                }
                .frame(maxWidth: 520)

                statGrid(columns: 2)
            }
        } else {
            VStack(alignment: .leading, spacing: 22) {
                month
                streakLine
                statGrid(columns: layout.statColumns)
            }
        }
    }

    private var month: some View {
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
    }

    private func statGrid(columns: Int) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns),
            spacing: 12
        ) {
            SoftCard {
                StatTile(
                    label: "Steps",
                    value: snapshot.steps.map { $0.formatted() },
                    progress: snapshot.stepsProgress
                )
            }
            SoftCard {
                StatTile(
                    label: "Sleep",
                    value: snapshot.sleepMinutes.map(Self.duration),
                    progress: snapshot.sleepProgress
                )
            }
            SoftCard {
                StatTile(
                    label: "Weight",
                    value: snapshot.weightKg.map { String(format: "%.1f", $0) },
                    unit: "kg"
                )
            }
            SoftCard {
                StatTile(
                    label: "Recovery",
                    value: snapshot.recoveryPct.map { "\(Int($0))" },
                    unit: "%"
                )
            }
        }
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

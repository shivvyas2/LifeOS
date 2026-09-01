import SwiftUI
import DesignSystem
import Persistence

struct TodayScreen: View {
    let snapshot: TodaySnapshot
    /// Raised when a dot for a real, non-future day is tapped. The screen stays
    /// a pure function of its inputs: it does not decide what a day opens.
    let onSelectDay: (Date) -> Void
    /// Raised from the agenda card's empty state. The EventKit prompt itself
    /// fires from here, never at launch.
    let onConnectCalendar: () -> Void
    let onAddEvent: () -> Void
    let onTapEvent: (CalendarEventSnapshot) -> Void
    /// Raised by the agenda's "+N more" row, since only the day sheet lists
    /// everything.
    let onOpenToday: () -> Void
    /// Raised from the empty state below. Like the calendar prompt, the
    /// permission sheet fires from a tap and never at launch.
    var onConnectHealth: () -> Void = {}
    /// Whether a source is already attached, so a connected person with a quiet
    /// day is not told to connect something they have connected.
    var isHealthConnected = false

    /// Raised when a stat tile is tapped. The screen names the metric and
    /// stops there: what a metric opens is the shell's decision, the same way
    /// a tapped day is.
    var onSelectMetric: (TodayMetric) -> Void = { _ in }

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
                    agendaCard
                    streakLine
                }
                .frame(maxWidth: 520)

                VStack(alignment: .leading, spacing: 22) {
                    if showsHealthPrompt { healthPrompt }
                    statGrid(columns: 2)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 22) {
                month
                agendaCard
                streakLine
                if showsHealthPrompt { healthPrompt }
                statGrid(columns: layout.statColumns)
            }
        }
    }

    /// Only when there is nothing to show and nothing attached. A connected
    /// strap that simply has not synced yet is a different situation, and
    /// telling that person to connect something would be wrong.
    private var showsHealthPrompt: Bool {
        snapshot.hasNoHealthData && !isHealthConnected
    }

    private var healthPrompt: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("No health data yet", systemImage: "heart.text.square")
                    .font(LifeOSType.rowTitle)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))

                Text("Steps, sleep, weight and recovery come from Apple Health and Whoop. Connect one and this fills in.")
                    .font(LifeOSType.label.weight(.regular))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onConnectHealth) {
                    Text("Connect Apple Health")
                        .font(LifeOSType.label.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(LifeOSTokens.accent))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var agendaCard: some View {
        AgendaCard(
            access: snapshot.calendarAccess,
            agenda: snapshot.agenda,
            upcoming: snapshot.upcoming,
            onConnect: onConnectCalendar,
            onAddEvent: onAddEvent,
            onTapEvent: onTapEvent,
            onOpenToday: onOpenToday
        )
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

    /// Every tile is a way into that metric's own page, so the grid is built
    /// from `TodayMetric` rather than written out four times. What each one
    /// looks like — icon, hue, unit, how the figure is written — belongs to the
    /// metric, which is what keeps the tile and the page it opens agreeing.
    private func statGrid(columns: Int) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns),
            spacing: 12
        ) {
            ForEach(TodayMetric.allCases) { metric in
                Button { onSelectMetric(metric) } label: {
                    tile(metric)
                }
                // Plain, or the card takes the accent tint and the whole grid
                // turns blue on press. The tile is already the affordance.
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(metric))
                .accessibilityHint("Opens \(metric.title.lowercased()) history")
            }
        }
    }

    private func tile(_ metric: TodayMetric) -> some View {
        TrendStatTile(
            icon: metric.icon,
            hue: metric.hue,
            label: metric.title,
            value: latest(metric).map(metric.format),
            unit: metric.unit,
            series: series(metric),
            goal: goal(metric),
            baseline: metric.baseline
        )
    }

    /// Today's figure for a metric. Held on the snapshot as separate fields
    /// rather than a dictionary, so this is the one place they are matched up.
    private func latest(_ metric: TodayMetric) -> Double? {
        switch metric {
        case .steps:    snapshot.steps.map(Double.init)
        case .sleep:    snapshot.sleepMinutes.map(Double.init)
        case .weight:   snapshot.weightKg
        case .recovery: snapshot.recoveryPct
        }
    }

    private func series(_ metric: TodayMetric) -> TrendSeries {
        switch metric {
        case .steps:    snapshot.stepsWeek
        case .sleep:    snapshot.sleepWeek
        case .weight:   snapshot.weightWeek
        case .recovery: snapshot.recoveryWeek
        }
    }

    private func goal(_ metric: TodayMetric) -> Double? {
        switch metric {
        case .steps:              snapshot.stepsTarget
        case .sleep:              snapshot.sleepTargetMinutes
        case .weight, .recovery:  nil
        }
    }

    /// The tile reads as an icon, a word and a numeral, which VoiceOver would
    /// otherwise announce as three separate things inside a button.
    private func accessibilityLabel(_ metric: TodayMetric) -> String {
        guard let value = latest(metric) else { return "\(metric.title), no reading" }
        return "\(metric.title), \(metric.format(value))\(metric.unit.map { " \($0)" } ?? "")"
    }

    private var streakLine: some View {
        HStack(spacing: 6) {
            Text("\(snapshot.streak)")
                .font(LifeOSType.rowTitle.weight(.bold))
                .foregroundStyle(LifeOSTokens.accent)
            Text(snapshot.streak == 1 ? "day streak" : "day streak")
                .font(LifeOSType.secondary.weight(.medium))
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
        }
    }

    static func duration(_ minutes: Int) -> String {
        "\(minutes / 60)h \(minutes % 60)m"
    }
}

#Preview {
    let now = Date.now
    let fakeEvents = [
        CalendarEventSnapshot(
            id: UUID(), source: .eventKit, sourceID: "1",
            calendarTitle: "Work", title: "Standup",
            startDate: now, endDate: now.addingTimeInterval(30 * 60),
            isAllDay: false, isRecurring: false, location: nil, notes: nil
        ),
        CalendarEventSnapshot(
            id: UUID(), source: .eventKit, sourceID: "2",
            calendarTitle: "Work", title: "Design review",
            startDate: now.addingTimeInterval(3600), endDate: now.addingTimeInterval(3600 * 2.5),
            isAllDay: false, isRecurring: false, location: nil, notes: nil
        ),
    ]

    TodayScreen(
        snapshot: TodaySnapshot(
            cells: (0..<35).map { DotCell(id: $0, date: nil, state: $0 < 10 ? .onTarget : ($0 == 10 ? .today : .future)) },
            streak: 6,
            steps: 8432,
            stepsProgress: 1.05,
            sleepMinutes: 432,
            sleepProgress: 0.9,
            weightKg: 77.4,
            recoveryPct: nil,
            calendarAccess: .authorized,
            agenda: fakeEvents
        ),
        onSelectDay: { _ in },
        onConnectCalendar: {},
        onAddEvent: {},
        onTapEvent: { _ in },
        onOpenToday: {}
    )
}

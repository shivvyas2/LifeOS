import SwiftUI
import DesignSystem
import Persistence

struct TodayScreen: View {
    let snapshot: TodaySnapshot
    /// Raised when a dot for a real day is tapped. The screen stays
    /// a pure function of its inputs: it does not decide what a day opens.
    let onSelectDay: (Date) -> Void
    /// Raised from the agenda card's empty state. The EventKit prompt itself
    /// fires from here, never at launch.
    let onConnectCalendar: () -> Void
    let onAddEvent: () -> Void
    let onTapEvent: (CalendarEventSnapshot) -> Void
    /// Raised by the agenda's "+N more" row, since only the day screen lists
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
                .padding(.top, Space.x3)
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
            HStack(alignment: .top, spacing: Space.x4) {
                VStack(alignment: .leading, spacing: Space.x3) {
                    masthead
                    agendaCard
                    month
                    scheduledWorkout
                }
                .frame(maxWidth: 520)
                VStack(alignment: .leading, spacing: Space.x3) {
                    if showsHealthPrompt { healthPrompt }
                    statGrid(columns: 2)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: Space.x3) {
                masthead
                agendaCard
                month
                scheduledWorkout
                if showsHealthPrompt { healthPrompt }
                statGrid(columns: layout.statColumns)
            }
        }
    }

    private var masthead: some View {
        let headline = TodayHeadline.make(date: snapshot.date, streak: snapshot.streak, calendar: calendar)
        return EditorialMasthead(eyebrow: headline.eyebrow, title: headline.title, detail: headline.detail)
    }

    private var showsHealthPrompt: Bool {
        snapshot.hasNoHealthData && !isHealthConnected
    }

    private var healthPrompt: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text("No health data yet").font(LifeOSType.rowTitle)
            Text("Steps, sleep, weight and recovery come from Apple Health and Whoop. Connect one and this fills in.")
                .font(LifeOSType.secondary)
                .foregroundStyle(Editorial.quietInk(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Button("Connect Apple Health", action: onConnectHealth)
                .buttonStyle(.editorial(.primary, size: .compact))
        }
        .editorialCard()
    }

    @ViewBuilder
    private var scheduledWorkout: some View {
        if let title = snapshot.scheduledWorkoutTitle {
            VStack(alignment: .leading, spacing: Space.half) {
                EditorialRow("Scheduled workout", value: title)
                Text("In Workout library").font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
            }
            .editorialCard()
            .accessibilityElement(children: .combine)
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
    /// Ghosted sample figures while nothing is connected: the tiles show
    /// what they will hold, and the card above says how to fill them.
    private func statGrid(columns: Int) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns),
            spacing: 12
        ) {
            ForEach(TodayMetric.allCases) { metric in
                Button { onSelectMetric(metric) } label: {
                    tile(metric)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(metric))
                .accessibilityHint("Opens \(metric.title.lowercased()) history")
            }
        }
        .opacity(showsHealthPrompt ? 0.35 : 1)
        .allowsHitTesting(!showsHealthPrompt)
        .accessibilityHidden(showsHealthPrompt)
    }

    private func tile(_ metric: TodayMetric) -> some View {
        TrendStatTile(
            icon: metric.icon,
            hue: metric.hue,
            label: metric.title,
            value: (showsHealthPrompt ? sample(metric) : latest(metric)).map(metric.format),
            unit: metric.unit,
            series: showsHealthPrompt ? sampleSeries : series(metric),
            goal: goal(metric),
            baseline: metric.baseline,
            style: .ink
        )
    }

    private func sample(_ metric: TodayMetric) -> Double {
        switch metric {
        case .steps: 8_240
        case .sleep: 432
        case .weight: 77.4
        case .recovery: 82
        }
    }

    private var sampleSeries: TrendSeries {
        TrendSeries(points: (0..<7).map { offset in
            TrendPoint(date: calendar.date(byAdding: .day, value: offset - 6, to: snapshot.date) ?? snapshot.date,
                       value: Double(60 + (offset * 7) % 30))
        })
    }

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

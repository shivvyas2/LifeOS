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

    private func statGrid(columns: Int) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns),
            spacing: 12
        ) {
            TrendStatTile(
                icon: "figure.walk",
                hue: .activity,
                label: "Steps",
                value: snapshot.steps.map { $0.formatted() },
                series: snapshot.stepsWeek,
                goal: snapshot.stepsTarget
            )
            TrendStatTile(
                icon: "moon.fill",
                hue: .nutrition,
                label: "Sleep",
                value: snapshot.sleepMinutes.map(Self.duration),
                series: snapshot.sleepWeek,
                goal: snapshot.sleepTargetMinutes
            )
            TrendStatTile(
                icon: "scalemass.fill",
                hue: .body,
                label: "Weight",
                value: snapshot.weightKg.map { String(format: "%.1f", $0) },
                unit: "kg",
                series: snapshot.weightWeek,
                // Weight has no target to hit and never nears nought, so it is
                // read against its own week rather than against zero.
                baseline: .windowMinimum
            )
            TrendStatTile(
                icon: "bolt.heart.fill",
                hue: .recovery,
                label: "Recovery",
                value: snapshot.recoveryPct.map { "\(Int($0))" },
                unit: "%",
                series: snapshot.recoveryWeek
            )
        }
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

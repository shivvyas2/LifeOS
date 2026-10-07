import SwiftUI
import SwiftData
import Combine
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
    /// everything; also by a task's text, which the day screen opens.
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
    /// The GitHub card's reconnect row and the tray's Connect GitHub.
    var onOpenSettings: () -> Void = {}

    /// The arrangement, saved per account on this device.
    @State var store: TodayLayoutStore
    /// Today's day model, the one behind the day screen: tasks, weather,
    /// spend, LIFO and GitHub come from it, loading only what is shown.
    @State var day: DayViewModel
    @State var newTask = ""

    @Environment(\.colorScheme) var scheme
    @Environment(\.layout) var layout
    @Environment(\.modelContext) var context
    @Environment(\.dayProviders) var providers
    @Environment(\.noteSync) var sync
    @Environment(\.github) var github
    @Environment(\.openURL) var openURL
    let calendar = Calendar.current

    init(snapshot: TodaySnapshot,
         onSelectDay: @escaping (Date) -> Void,
         onConnectCalendar: @escaping () -> Void,
         onAddEvent: @escaping () -> Void,
         onTapEvent: @escaping (CalendarEventSnapshot) -> Void,
         onOpenToday: @escaping () -> Void,
         onConnectHealth: @escaping () -> Void = {},
         isHealthConnected: Bool = false,
         onSelectMetric: @escaping (TodayMetric) -> Void = { _ in },
         onOpenSettings: @escaping () -> Void = {},
         layoutStore: TodayLayoutStore? = nil) {
        self.snapshot = snapshot
        self.onSelectDay = onSelectDay
        self.onConnectCalendar = onConnectCalendar
        self.onAddEvent = onAddEvent
        self.onTapEvent = onTapEvent
        self.onOpenToday = onOpenToday
        self.onConnectHealth = onConnectHealth
        self.isHealthConnected = isHealthConnected
        self.onSelectMetric = onSelectMetric
        self.onOpenSettings = onOpenSettings
        _store = State(initialValue: layoutStore ?? TodayLayoutStore())
        _day = State(initialValue: DayViewModel(date: snapshot.date))
    }

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
        .sensoryFeedback(.impact(weight: .light), trigger: store.isArranging) { _, on in on }
        // Switching tabs ends arranging; every change is already saved.
        .onDisappear { store.isArranging = false }
        .task { attachDay() }
        .onChange(of: store.layout) { attachDay() }
        .onChange(of: github?.changeCount) { attachDay() }
        .onChange(of: github?.state) { _, state in
            if case .connected = state { store.offerGitHubOnce() }
        }
        // Saves arrive in bursts (a tick, a health sample, a sync); one reload
        // a quarter second after the last is enough.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
            day.load()
        }
    }

    func attachDay() {
        day.onlySections = TodayLayout.sections(for: store.layout.phoneOrder)
        day.attach(context, providers: providers, sync: sync)
        day.load()
    }

    /// The masthead, then the arrangement: one list on a phone, the two
    /// columns side by side on a wide pane.
    ///
    /// The month has to be *narrower* than a wide pane, not wider: a dot grid
    /// divides whatever width it is given by seven, so a full-width month on a
    /// 1300pt pane draws 170pt dots. The left column's cap keeps it in hand.
    @ViewBuilder
    private var layoutBody: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            if store.isArranging {
                arrangingMasthead
            } else {
                masthead
                if !store.hintSeen { TodayArrangeHint { store.hintSeen = true } }
            }
            if layout.isRegular {
                HStack(alignment: .top, spacing: Space.x4) {
                    column(store.layout.left, side: .left).frame(maxWidth: 520)
                    column(store.layout.right, side: .right)
                }
            } else {
                column(store.layout.phoneOrder, side: nil)
            }
            if store.isArranging {
                TodayTray(hidden: store.layout.hidden, isGitHubConnected: isGitHubConnected,
                          onAdd: { module in store.update { $0.add(module) } },
                          onConnectGitHub: onOpenSettings,
                          onReset: { store.reset() })
            }
        }
        // A tap on empty canvas ends arranging.
        .contentShape(.rect)
        .onTapGesture { if store.isArranging { store.isArranging = false } }
    }

    private var isGitHubConnected: Bool {
        if case .connected = github?.state { return true }
        return false
    }

    private var arrangingMasthead: some View {
        let headline = TodayHeadline.make(date: snapshot.date, streak: snapshot.streak, calendar: calendar)
        return HStack(alignment: .top) {
            EditorialMasthead(eyebrow: "Arranging Today", title: headline.title, detail: nil)
            Spacer(minLength: Space.x2)
            Button("Done") { store.isArranging = false }
                .buttonStyle(.editorial(.primary, size: .compact))
        }
    }

    /// Puts `module` just before `target`, in `target`'s column.
    private func place(_ name: String, before target: TodayModule) -> Bool {
        guard let module = TodayModule(rawValue: name), module != target else { return false }
        store.update { layout in
            layout.hide(module)
            let side = layout.column(of: target) ?? .left
            let index = (side == .left ? layout.left : layout.right).firstIndex(of: target) ?? 0
            layout.move(module, to: side, at: index)
        }
        return true
    }

    /// Dropped below a column's last row: the end of that column (on a phone,
    /// the end of the list).
    private func append(_ name: String, to side: TodayColumn?) -> Bool {
        guard let module = TodayModule(rawValue: name) else { return false }
        store.update { $0.move(module, to: side ?? .right, at: .max) }
        return true
    }

    /// A column's rows, with the health prompt above its first tile row.
    private func column(_ modules: [TodayModule], side: TodayColumn?) -> some View {
        let rows = TodayLayout.rows(modules)
        let firstTileRow = rows.firstIndex { if case .pair = $0 { true } else { false } }
        return VStack(alignment: .leading, spacing: Space.x3) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index == firstTileRow, showsHealthPrompt, !store.isArranging { healthPrompt }
                rowView(row)
                    .modifier(ArrangeableModule(
                        modules: row.modules, isArranging: store.isArranging, index: index,
                        onHide: { module in store.update { $0.hide(module) } },
                        onDrop: { place($0, before: row.modules[0]) }))
                    .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                        if !store.isArranging { store.isArranging = true; store.hintSeen = true }
                    })
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("today.module.\(row.modules[0].rawValue)")
                    .modifier(MoveActions(modules: row.modules, isRegular: layout.isRegular, store: store))
            }
            if store.isArranging {
                // Below the last row: drop here for the end of the column.
                Color.clear.frame(height: 44).frame(maxWidth: .infinity)
                    .contentShape(.rect)
                    .dropDestination(for: String.self) { names, _ in names.first.map { append($0, to: side) } ?? false }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var masthead: some View {
        let headline = TodayHeadline.make(date: snapshot.date, streak: snapshot.streak, calendar: calendar)
        return EditorialMasthead(eyebrow: headline.eyebrow, title: headline.title, detail: headline.detail)
    }

    var showsHealthPrompt: Bool {
        snapshot.hasNoHealthData && !isHealthConnected
    }

    var healthPrompt: some View {
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
    var scheduledWorkout: some View {
        if let title = snapshot.scheduledWorkoutTitle {
            VStack(alignment: .leading, spacing: Space.half) {
                EditorialRow("Scheduled workout", value: title)
                Text("In Workout library").font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
            }
            .editorialCard()
            .accessibilityElement(children: .combine)
        }
    }

    var agendaCard: some View {
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

    var month: some View {
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

    func tile(_ metric: TodayMetric) -> some View {
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
    func accessibilityLabel(_ metric: TodayMetric) -> String {
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

/// VoiceOver's way to arrange, available whether or not arranging: each
/// module moves up, down, across (iPad) or hides. A tile pair names which
/// tile each action moves.
private struct MoveActions: ViewModifier {
    let modules: [TodayModule]
    let isRegular: Bool
    let store: TodayLayoutStore

    func body(content: Content) -> some View {
        modules.reduce(AnyView(content)) { view, module in
            let suffix = modules.count > 1 ? " \(module.title)" : ""
            var actions = AnyView(view
                .accessibilityAction(named: "Move up\(suffix)") { store.update { $0.moveUp(module) } }
                .accessibilityAction(named: "Move down\(suffix)") { store.update { $0.moveDown(module) } }
                .accessibilityAction(named: "Hide\(suffix)") { store.update { $0.hide(module) } })
            if isRegular {
                actions = AnyView(actions.accessibilityAction(named: "Move to other column\(suffix)") {
                    store.update { $0.moveToOtherColumn(module) }
                })
            }
            return actions
        }
    }
}


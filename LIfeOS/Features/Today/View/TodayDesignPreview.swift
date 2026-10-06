#if DEBUG
import SwiftUI
import SwiftData
import AppSurfaces
import DesignSystem
import Persistence

/// Fixture pages for Today, the calendar screen, the day sheet and Notes,
/// mounted by `--design-preview` with `--page=today`, `today-empty`,
/// `today-done`, `month` (the calendar in Monthly), `schedule` (the calendar
/// in Weekly), `calendar-find` (the calendar with `--query=` live; add
/// `--weekly` to open it on the bands),
/// `calendar-ask` (the reply card from a seeded conversation; `--far` makes
/// it about an event outside the loaded months; `--no-model`
/// on either calendar page hides the arrow and shows the needs-model line),
/// `day` (today, every section), `day-past` (three days ago), `day-future`
/// (three days ahead), `day-far` (twenty days ahead, no forecast), `day-empty`
/// (today with nothing), `day-no-location` (location not yet allowed), `notes`
/// or `notes-empty`. `--select=` opens the
/// calendar pages on a given day.
struct TodayDesignPreview: View {
    let page: String
    @State private var fixture = TodayFixture()

    /// `--select=2026-09-29` opens the calendar pages on that day, so a week
    /// that straddles two months or a month in another year can be captured
    /// without a tap.
    private var selected: Date? {
        guard let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--select=") })?.dropFirst(9) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current
        return formatter.date(from: String(raw))
    }

    /// `--query=den` opens the calendar with that text in the field, so the
    /// results block and the grid marks can be captured without typing.
    private var query: String {
        ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--query=") })?.dropFirst(8).description ?? ""
    }

    var body: some View {
        Group {
            switch page {
            case "today-empty":
                NavigationStack {
                    TodayScreen(snapshot: fixture.emptySnapshot, onSelectDay: { _ in }, onConnectCalendar: {},
                                onAddEvent: {}, onTapEvent: { _ in }, onOpenToday: {})
                        .shellToolbar()
                }
            case "month":
                NavigationStack { CalendarScreen(initialSelection: selected) }.modelContainer(fixture.container)
            case "schedule":
                NavigationStack { CalendarScreen(initialMode: .weekly, initialSelection: selected) }.modelContainer(fixture.container)
            case "calendar-find":
                NavigationStack {
                    CalendarScreen(assistant: fixture.assistant,
                                   initialMode: ProcessInfo.processInfo.arguments.contains("--weekly") ? .weekly : .monthly,
                                   initialSelection: selected, initialQuery: query)
                }
                .modelContainer(fixture.container)
            case "calendar-ask":
                NavigationStack {
                    CalendarScreen(assistant: fixture.assistant, initialSelection: selected,
                                   initialQuestion: TodayFixture.question)
                }
                .modelContainer(fixture.container)
            case "day", "day-past", "day-future", "day-far", "day-empty", "day-no-location":
                NavigationStack { DayScreen(date: fixture.dayDate(for: page)) }
                    .modelContainer(page == "day-empty" ? fixture.emptyContainer : fixture.container)
                    .environment(\.dayProviders, DayProviders(
                        weather: StubWeatherProvider(),
                        location: StubLocation(access: page == "day-no-location" ? .notDetermined : .granted)))
            case "today-done":
                NavigationStack {
                    TodayScreen(snapshot: fixture.doneSnapshot, onSelectDay: { _ in }, onConnectCalendar: {},
                                onAddEvent: {}, onTapEvent: { _ in }, onOpenToday: {}, isHealthConnected: true)
                        .shellToolbar()
                }
            case "notes":
                NavigationStack { NoteShelfScreen(model: fixture.notes, onOpen: { _ in }, onNewFolder: { _ in }).shellToolbar() }
                    .modelContainer(fixture.container)
            case "notes-empty":
                NavigationStack { NoteShelfScreen(model: fixture.emptyNotes, onOpen: { _ in }, onNewFolder: { _ in }).shellToolbar() }
                    .modelContainer(fixture.emptyContainer)
            default:
                NavigationStack {
                    TodayScreen(snapshot: fixture.snapshot, onSelectDay: { _ in }, onConnectCalendar: {},
                                onAddEvent: {}, onTapEvent: { _ in }, onOpenToday: {}, isHealthConnected: true)
                        .shellToolbar()
                }
            }
        }
        .environment(\.quickActions, LifeDesignPreview.actions)
        .environment(\.shellProfile, ShellProfile(photo: nil, open: {}))
    }
}

@MainActor private final class TodayFixture {
    let container = try! LifeOSContainer.make(inMemory: true)
    let emptyContainer = try! LifeOSContainer.make(inMemory: true)
    let notes = NotesViewModel()
    let emptyNotes = NotesViewModel()
    let calendar = Calendar.current
    let events: [CalendarEventSnapshot]
    private var today: Date { calendar.startOfDay(for: .now) }

    static var question: String {
        ProcessInfo.processInfo.arguments.contains("--far") ? "When is the ski trip?" : "When is the dentist?"
    }

    /// The calendar pages share one assistant, seeded with a question about
    /// the dentist and its answer under the conversation id the model loads,
    /// so the reply card draws without a model turn. `--no-model` hides the
    /// ask arrow the way a device without Apple Intelligence would.
    private(set) lazy var assistant: AssistantViewModel = {
        let model = AssistantViewModel(context: container.mainContext)
        model.previewAuthorized = true
        model.previewModelAvailable = !ProcessInfo.processInfo.arguments.contains("--no-model")
        let id = UUID()
        UserDefaults.currentAccount.set(id.uuidString, forKey: "assistant.conversationID")
        let chat = ChatStore(context: container.mainContext)
        try! chat.append(conversationID: id, role: .user, text: Self.question)
        // `--far` answers about the ski trip 100 days out, outside the two
        // months the screen loads, so the jump to an unloaded week is drawn.
        let far = ProcessInfo.processInfo.arguments.contains("--far")
        let about = events.first { $0.title == (far ? "Ski trip" : "Dentist") }!
        let answer = far
            ? "Your ski trip is on \(about.startDate.formatted(.dateTime.weekday(.wide).month(.wide).day())), from 09:00."
            : "Your dentist is tomorrow at 10:00, for an hour. Nothing else is booked that morning."
        try! chat.append(conversationID: id, role: .assistant, text: answer,
                         toolSummaries: ["Checked your calendar"], eventIDs: [about.id])
        return model
    }()

    init() {
        let start = Calendar.current.startOfDay(for: .now)
        func at(_ dayOffset: Int, _ hour: Int, _ minutes: Int, _ title: String) -> CalendarEventSnapshot {
            let day = Calendar.current.date(byAdding: .day, value: dayOffset, to: start)!
            let begins = Calendar.current.date(byAdding: .hour, value: hour, to: day)!
            return CalendarEventSnapshot(id: UUID(), source: .eventKit, sourceID: "\(title)-\(dayOffset)", calendarTitle: "Work", title: title,
                                         startDate: begins, endDate: begins.addingTimeInterval(Double(minutes) * 60),
                                         isAllDay: false, isRecurring: false, location: nil, notes: nil)
        }
        events = [
            at(0, 9, 30, "Standup"), at(0, 12, 60, "Lunch with Sam"), at(0, 16, 90, "Design review"),
            at(1, 10, 60, "Dentist"), at(2, 19, 120, "Dinner with Alice"), at(3, 8, 60, "Programming class"),
            at(6, 19, 180, "Professional party"), at(-2, 9, 30, "Standup"), at(-7, 11, 60, "Dentist follow-up"),
            at(14, 9, 60, "Flight to Lisbon"), at(100, 9, 60, "Ski trip"),
        ]
        let window = DateInterval(start: calendar.date(byAdding: .day, value: -40, to: start)!,
                                  end: calendar.date(byAdding: .day, value: 70, to: start)!)
        try! CalendarStore(context: container.mainContext, calendar: calendar).apply(events, window: window)
        notes.attach(container.mainContext)
        _ = notes.createNote(kind: .note, title: "Marathon block, week four")
        _ = notes.createNote(kind: .task, title: "Groceries")
        _ = notes.openTodaysJournal()
        notes.load()
        emptyNotes.attach(emptyContainer.mainContext)
        emptyNotes.load()
        seedDay()
    }

    func dayDate(for page: String) -> Date {
        let offset: Int = switch page {
        case "day-past": -3
        case "day-future": 3
        case "day-far": 20
        default: 0
        }
        return calendar.date(byAdding: .day, value: offset, to: today)!
    }

    /// Readings, spend, habits, due tasks, the journal's to-dos and a nudge,
    /// for today and three days ago, so every day section has rows.
    private func seedDay() {
        let context = container.mainContext
        // The needs-location page must not find a forecast another page cached minutes ago.
        if ProcessInfo.processInfo.arguments.contains("--page=day-no-location") {
            UserDefaults.currentAccount.removeObject(forKey: "day.forecasts")
        }
        for (offset, steps, sleep, weight, recovery) in [(0, 8_432, 432, 77.4, 82.0), (-3, 6_120, 401, 77.6, 64.0)] {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let row = DailyMetrics(date: day)
            row.steps = steps; row.sleepMinutes = sleep; row.weightKg = weight; row.whoopRecoveryPct = recovery
            context.insert(row)
        }
        context.insert(WorkoutRecord(externalID: "run-1", start: today.addingTimeInterval(7 * 3_600), durationMinutes: 35, activityName: "Running"))
        for (offset, amount, merchant) in [(0, -4.60, "Monmouth Coffee"), (0, -48.10, "Waitrose"), (0, -9.99, "Spotify"), (-3, -23.50, "Dishoom")] {
            context.insert(MoneyEntry(date: calendar.date(byAdding: .day, value: offset, to: today)!, amount: amount, merchant: merchant))
        }
        let plan = PlanStore(context: context, calendar: calendar)
        let run = try! plan.add(kind: .habit, title: "5km run")
        let read = try! plan.add(kind: .habit, title: "Read 10 pages")
        let walk = try! plan.add(kind: .habit, title: "Walk the dog")
        // Habits that existed before the past page's day, so a record shows them.
        run.createdAt = calendar.date(byAdding: .day, value: -30, to: today)!
        read.createdAt = calendar.date(byAdding: .day, value: -10, to: today)!
        walk.createdAt = calendar.date(byAdding: .day, value: -1, to: today)!
        for offset in [0, -1, -2, -3, -4, -5] {
            try! plan.toggleTick(for: run, on: calendar.date(byAdding: .day, value: offset, to: today)!)
        }
        let notes = NotesStore(context: context, calendar: calendar)
        let groceries = try! notes.document(titled: "Groceries")!
        try! notes.update(groceries, blocks: [
            NoteBlock(kind: .todo, text: "Buy oat milk", dueDate: today),
            NoteBlock(kind: .todo, text: "Order the filter", dueDate: calendar.date(byAdding: .day, value: 3, to: today)),
        ])
        let journal = try! notes.journalEntry(on: today)
        try! notes.update(journal, blocks: [
            NoteBlock(kind: .todo, text: "Call the dentist", isChecked: true),
            NoteBlock(kind: .todo, text: "Draft the plan"),
        ])
        try! context.save()
        // The empty page shows an empty inbox too; the seed is global.
        guard !ProcessInfo.processInfo.arguments.contains("--page=day-empty") else { return }
        PushService.shared.previewSeed(entries: [
            InboxEntry(ownerID: "preview", text: "Three short nights in a row. An early one tonight would do more than any workout.",
                       trigger: "short_sleep", day: WeatherCache.dayKey(today, calendar: calendar),
                       receivedAt: today.addingTimeInterval(8 * 3_600)),
        ])
    }

    var snapshot: TodaySnapshot {
        var s = TodaySnapshot()
        s.cells = (0..<35).map { DotCell(id: $0, date: nil, state: $0 < 10 ? .onTarget : ($0 == 10 ? .today : .future)) }
        s.streak = 6; s.steps = 8_432; s.sleepMinutes = 432; s.weightKg = 77.4; s.recoveryPct = 82
        s.calendarAccess = .authorized
        s.agenda = events.filter { calendar.isDateInToday($0.startDate) }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        s.upcoming = events.filter { $0.startDate >= tomorrow }.sorted { $0.startDate < $1.startDate }.prefix(3)
            .map { UpcomingEvent(id: $0.id, dayLabel: $0.startDate.formatted(.dateTime.weekday(.wide)), event: $0) }
        s.scheduledWorkoutTitle = "Lower body, 35 min"
        return s
    }

    /// Every event of the day already over: the field must not call one "next".
    var doneSnapshot: TodaySnapshot {
        var s = snapshot
        s.agenda = [
            events.first { $0.title == "Standup" && calendar.isDateInToday($0.startDate) }!,
        ].map { event in
            CalendarEventSnapshot(id: event.id, source: event.source, sourceID: event.sourceID, calendarTitle: event.calendarTitle,
                                  title: event.title, startDate: today.addingTimeInterval(3600), endDate: today.addingTimeInterval(5400),
                                  isAllDay: false, isRecurring: false, location: nil, notes: nil)
        }
        return s
    }


    var emptySnapshot: TodaySnapshot {
        var s = TodaySnapshot()
        s.cells = (0..<35).map { DotCell(id: $0, date: nil, state: $0 == 10 ? .today : .future) }
        s.calendarAccess = .notDetermined
        return s
    }

}
#endif

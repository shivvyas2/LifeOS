#if DEBUG
import SwiftUI
import SwiftData
import DesignSystem
import Persistence

/// Fixture pages for Today, the calendar screen, the day sheet and Notes,
/// mounted by `--design-preview` with `--page=today`, `today-empty`,
/// `today-done`, `month` (the calendar in Monthly), `schedule` (the calendar
/// in Weekly), `calendar-find` (the calendar with `--query=` live), `day`,
/// `day-past`, `notes` or `notes-empty`. `--select=` opens the calendar
/// pages on a given day.
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
                NavigationStack { CalendarScreen(initialSelection: selected, initialQuery: query) }.modelContainer(fixture.container)
            case "day":
                DayDetailSheet(snapshot: fixture.day, onToggleHabit: { _ in })
            case "day-past":
                DayDetailSheet(snapshot: fixture.pastDay, onToggleHabit: { _ in })
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
            at(14, 9, 60, "Flight to Lisbon"),
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

    var pastDay: DayDetailSnapshot {
        DayDetailSnapshot(date: calendar.date(byAdding: .day, value: -3, to: today)!, isToday: false, steps: 6_120,
                          stepsTarget: 10_000, sleepMinutes: 401, sleepTargetMinutes: 480, weightKg: 77.6, recoveryPct: 64,
                          habits: [HabitRow(id: UUID(), title: "5km run", isDone: true),
                                   HabitRow(id: UUID(), title: "Read 10 pages", isDone: false)],
                          events: [])
    }

    var emptySnapshot: TodaySnapshot {
        var s = TodaySnapshot()
        s.cells = (0..<35).map { DotCell(id: $0, date: nil, state: $0 == 10 ? .today : .future) }
        s.calendarAccess = .notDetermined
        return s
    }

    var day: DayDetailSnapshot {
        DayDetailSnapshot(date: today, isToday: true, steps: 8_432, stepsTarget: 10_000, sleepMinutes: 432,
                          sleepTargetMinutes: 480, weightKg: 77.4, recoveryPct: 82,
                          habits: [HabitRow(id: UUID(), title: "5km run", isDone: true),
                                   HabitRow(id: UUID(), title: "Read 10 pages", isDone: false),
                                   HabitRow(id: UUID(), title: "Walk the dog", isDone: false)],
                          events: events.filter { calendar.isDateInToday($0.startDate) })
    }
}
#endif

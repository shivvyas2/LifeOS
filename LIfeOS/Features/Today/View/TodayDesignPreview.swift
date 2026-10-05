#if DEBUG
import SwiftUI
import SwiftData
import DesignSystem
import Persistence

/// Fixture pages for Today, the month screen, the schedule, the day sheet
/// and Notes, mounted by `--design-preview` with `--page=today`,
/// `today-empty`, `month`, `schedule`, `day`, `notes` or `notes-empty`.
struct TodayDesignPreview: View {
    let page: String
    @State private var fixture = TodayFixture()

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
                NavigationStack { MonthScreen() }.modelContainer(fixture.container)
            case "schedule":
                NavigationStack { DayScheduleScreen(model: fixture.month, day: .now) }.modelContainer(fixture.container)
            case "day":
                DayDetailSheet(snapshot: fixture.day, onToggleHabit: { _ in })
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
    let month = MonthViewModel()
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
            return CalendarEventSnapshot(id: UUID(), source: .eventKit, sourceID: title, calendarTitle: "Work", title: title,
                                         startDate: begins, endDate: begins.addingTimeInterval(Double(minutes) * 60),
                                         isAllDay: false, isRecurring: false, location: nil, notes: nil)
        }
        events = [
            at(0, 9, 30, "Standup"), at(0, 12, 60, "Lunch with Sam"), at(0, 16, 90, "Design review"),
            at(1, 10, 60, "Dentist"), at(2, 19, 120, "Dinner with Alice"), at(3, 8, 60, "Programming class"),
            at(6, 19, 180, "Professional party"), at(-2, 9, 30, "Standup"), at(14, 9, 60, "Flight to Lisbon"),
        ]
        let window = DateInterval(start: calendar.date(byAdding: .day, value: -40, to: start)!,
                                  end: calendar.date(byAdding: .day, value: 70, to: start)!)
        try! CalendarStore(context: container.mainContext, calendar: calendar).apply(events, window: window)
        month.attach(container.mainContext)
        month.load()
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

import Foundation
import SwiftData
import DesignSystem
import Persistence

/// One month of the calendar, and whichever day in it is selected.
///
/// Kept apart from `TodayViewModel`, which is about today and holds a month
/// grid only to show how the habit streak has been going. This one is about
/// any month, moves between them, and reads events rather than habits.
@MainActor @Observable
final class MonthViewModel {
    /// Any day inside the month being shown. The first of the month would do
    /// as well, but keeping the real day means stepping March to February and
    /// back returns to the same day rather than to the first.
    private(set) var month: Date = .now
    private(set) var selection: Date = Calendar.current.startOfDay(for: .now)
    /// Events for the whole visible month, grouped by day-start, so a cell
    /// asks a dictionary rather than the store. One fetch per month, not one
    /// per cell: a month is up to 42 cells and every one of them wants a
    /// count.
    private(set) var eventsByDay: [Date: [CalendarEventSnapshot]] = [:]

    /// The day number the person last picked, kept apart from `selection` so
    /// stepping through a short month does not permanently reduce it.
    private var anchorDay: Int = Calendar.current.component(.day, from: .now)
    private var context: ModelContext?
    private let calendar = Calendar.current

    func attach(_ context: ModelContext) {
        self.context = context
        load()
    }

    var selectedEvents: [CalendarEventSnapshot] {
        eventsByDay[calendar.startOfDay(for: selection)] ?? []
    }

    func events(on day: Date) -> [CalendarEventSnapshot] {
        eventsByDay[calendar.startOfDay(for: day)] ?? []
    }

    func select(_ day: Date) {
        selection = calendar.startOfDay(for: day)
        anchorDay = calendar.component(.day, from: selection)
    }

    /// Steps a whole month and carries the selection into it.
    ///
    /// The day number is remembered rather than re-read from the selection,
    /// so stepping is reversible. Reading it back would clamp 31 March to 28
    /// February and then carry the 28th onward, and walking a year forward
    /// from the 31st would quietly arrive at the 28th.
    func step(_ months: Int) {
        guard let moved = calendar.date(byAdding: .month, value: months, to: startOfMonth) else { return }
        month = moved
        selection = MonthGridLayout.stepping(from: moved, by: 0, day: anchorDay, calendar: calendar)
        load()
    }

    /// Back to today, in every sense: the month, the selection and the fetch.
    func goToToday() {
        month = .now
        select(.now)
        load()
    }

    private var startOfMonth: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
    }

    /// One fetch for the visible month, padded by a week either side.
    ///
    /// The padding is what makes the leading and trailing cells of the grid
    /// answerable: the first row of a month usually starts in the previous
    /// one. It also means stepping a month redraws immediately for the days
    /// either side while the new fetch lands.
    func load() {
        guard let context else { return }
        let store = CalendarStore(context: context)

        let startOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: month)
        ) ?? month
        guard let from = calendar.date(byAdding: .day, value: -7, to: startOfMonth),
              let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth),
              let to = calendar.date(byAdding: .day, value: 7, to: endOfMonth)
        else { return }

        let events = (try? store.events(from: from, to: to)) ?? []
        eventsByDay = Dictionary(grouping: events) { calendar.startOfDay(for: $0.startDate) }
    }
}

import Foundation

/// Visual state of a single dot. `blank` is layout padding, not a day.
public enum DotState: Sendable, Equatable {
    case onTarget, missed, today, future, noData, blank
}

public struct DotCell: Sendable, Equatable, Identifiable {
    public let id: Int
    public let date: Date?
    public let state: DotState

    /// Explicit and public: a struct's memberwise init is internal by default,
    /// which would make this unconstructible from the app target.
    public init(id: Int, date: Date?, state: DotState) {
        self.id = id
        self.date = date
        self.state = state
    }
}

public enum MonthGridLayout {
    /// Moves `date` by whole months, keeping the day number where the new
    /// month is long enough for it and clamping to the last day where it is
    /// not.
    ///
    /// `Calendar.date(byAdding: .month,)` already clamps, but a screen that
    /// steps month by month has to hold its own anchor to be correct across
    /// more than one step: clamping 31 March to 28 February and then stepping
    /// on lands in March with the day silently reduced to 28, so walking a
    /// year forward from the 31st arrives at the 28th. Keeping the requested
    /// day and clamping only for display is what makes stepping reversible.
    public static func stepping(
        from date: Date, by months: Int, day: Int, calendar: Calendar
    ) -> Date {
        guard let moved = calendar.date(byAdding: .month, value: months, to: date),
              let startOfMoved = calendar.date(
                from: calendar.dateComponents([.year, .month], from: moved)
              )
        else { return date }

        let length = calendar.range(of: .day, in: .month, for: startOfMoved)?.count ?? 28
        return calendar.date(
            byAdding: .day, value: min(day, length) - 1, to: startOfMoved
        ) ?? startOfMoved
    }

    /// Builds a whole number of 7-day rows for the month containing `date`.
    /// `status` is called only for past days; today and future days are
    /// assigned by position so a partially-logged today never renders as a miss.
    public static func cells(
        monthContaining date: Date,
        calendar: Calendar,
        today: Date,
        status: (Date) -> DotState
    ) -> [DotCell] {
        let startOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: date)
        )!
        let dayCount = calendar.range(of: .day, in: .month, for: startOfMonth)!.count

        // How many blanks before day 1, given the calendar's first weekday.
        let weekday = calendar.component(.weekday, from: startOfMonth)
        let leading = (weekday - calendar.firstWeekday + 7) % 7

        let startOfToday = calendar.startOfDay(for: today)
        var cells: [DotCell] = []

        for _ in 0..<leading {
            cells.append(DotCell(id: cells.count, date: nil, state: .blank))
        }

        for day in 1...dayCount {
            let dayDate = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth)!
            let state: DotState = if calendar.isDate(dayDate, inSameDayAs: startOfToday) {
                .today
            } else if dayDate > startOfToday {
                .future
            } else {
                status(dayDate)
            }
            cells.append(DotCell(id: cells.count, date: dayDate, state: state))
        }

        // Pad to a whole number of rows so the grid is rectangular.
        while cells.count % 7 != 0 {
            cells.append(DotCell(id: cells.count, date: nil, state: .blank))
        }

        return cells
    }
}

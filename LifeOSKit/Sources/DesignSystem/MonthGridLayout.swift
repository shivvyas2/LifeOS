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

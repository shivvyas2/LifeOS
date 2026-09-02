import Foundation

/// The shapes the Money charts are drawn from: a week of daily spend, a run
/// of monthly spend, and a share list folded to fit a donut.
///
/// Pure functions in the kit rather than in the view model, because every one
/// of these is an off-by-one waiting to happen (week boundaries, an empty
/// month in the middle of a run, the "Other" slice) and the app target has no
/// tests. Callers filter to the rows they mean first; these only know an
/// amount and a date.
public enum SpendSeries {

    public struct Line: Equatable, Sendable {
        public let amount: Double
        public let date: Date

        public init(amount: Double, date: Date) {
            self.amount = amount
            self.date = date
        }
    }

    public struct DayTotal: Equatable, Sendable, Identifiable {
        public let date: Date
        /// Positive: money that left that day.
        public let amount: Double
        /// After the day the series was asked for. Drawn as an empty track,
        /// never as a zero, because nothing has happened there yet.
        public let isFuture: Bool

        public var id: Date { date }
    }

    public struct MonthTotal: Equatable, Sendable, Identifiable {
        public let monthStart: Date
        public let amount: Double

        public var id: Date { monthStart }
    }

    public struct Share: Equatable, Sendable {
        public let name: String
        public let amount: Double

        public init(name: String, amount: Double) {
            self.name = name
            self.amount = amount
        }
    }

    /// Seven days from the calendar's first weekday, each holding the outflows
    /// dated that day. Income and anything outside the week are ignored.
    public static func week(of date: Date, lines: [Line], calendar: Calendar) -> [DayTotal] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        let today = calendar.startOfDay(for: date)

        var byDay: [Date: Double] = [:]
        for line in lines where line.amount < 0 {
            let day = calendar.startOfDay(for: line.date)
            guard day >= interval.start, day < interval.end else { continue }
            byDay[day, default: 0] += -line.amount
        }

        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else {
                return nil
            }
            return DayTotal(date: day, amount: byDay[day] ?? 0, isFuture: day > today)
        }
    }

    /// `count` months ending with the month containing `date`, oldest first.
    /// A month with nothing spent is present at zero: a missing bucket would
    /// shift every later bar one slot left.
    public static func months(
        endingIn date: Date, count: Int, lines: [Line], calendar: Calendar
    ) -> [MonthTotal] {
        guard count > 0, let current = calendar.dateInterval(of: .month, for: date) else { return [] }

        let starts: [Date] = (0..<count).reversed().compactMap {
            calendar.date(byAdding: .month, value: -$0, to: current.start)
        }
        guard let windowStart = starts.first else { return [] }

        var byMonth: [Date: Double] = [:]
        for line in lines where line.amount < 0 {
            guard line.date >= windowStart, line.date < current.end,
                  let month = calendar.dateInterval(of: .month, for: line.date)?.start
            else { continue }
            byMonth[month, default: 0] += -line.amount
        }

        return starts.map { MonthTotal(monthStart: $0, amount: byMonth[$0] ?? 0) }
    }

    /// The `keep` largest shares, then everything else summed as "Other".
    /// A list that would fold a single share is returned whole: an "Other"
    /// holding one category is that category with the wrong name.
    public static func fold(_ shares: [Share], keep: Int) -> [Share] {
        let sorted = shares.sorted { ($0.amount, $1.name) > ($1.amount, $0.name) }
        guard sorted.count > keep + 1 else { return sorted }
        let head = Array(sorted.prefix(keep))
        let rest = sorted.dropFirst(keep).reduce(0) { $0 + $1.amount }
        return head + [Share(name: "Other", amount: rest)]
    }
}

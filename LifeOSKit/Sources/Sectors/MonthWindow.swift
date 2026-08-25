import Foundation

/// The exact instants one calendar month spans, computed once so every store
/// read and every date filter for that month agrees on where it starts and
/// ends.
///
/// `PlanStore.entries(kind:)` carries no date filtering of its own, so this
/// is also the one place that filtering happens: `filter(_:on:)` below.
public struct MonthWindow: Sendable, Equatable {
    /// Midnight on the first day of the month. Inclusive.
    public let start: Date
    /// Midnight on the first day of the *following* month. Exclusive: an
    /// instant equal to `end` belongs to next month, not this one.
    public let end: Date
    /// Midnight on the month's last day. For APIs like `MetricsStore.metrics`
    /// and `MoneyStore.entries` whose `to:` bound is inclusive-by-day rather
    /// than the half-open `[start, end)` this type otherwise uses.
    public let lastDay: Date
    public let daysInMonth: Int

    public init(for month: Date, calendar: Calendar) {
        let interval = calendar.dateInterval(of: .month, for: month)
            ?? DateInterval(start: calendar.startOfDay(for: month), duration: 0)
        start = interval.start
        end = interval.end
        lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
        daysInMonth = calendar.range(of: .day, in: .month, for: interval.start)?.count ?? 30
    }

    /// True for any instant from `start` up to, but not including, `end`.
    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }

    /// Keeps only the items whose date, as read by `date`, falls inside this
    /// window. `MonthlyCloseViewModel` uses this to turn `updatedAt` on plan
    /// entries and `createdAt` on journal entries into month-scoped input,
    /// since neither store filters by date itself.
    public func filter<T>(_ items: [T], on date: (T) -> Date) -> [T] {
        items.filter { contains(date($0)) }
    }
}

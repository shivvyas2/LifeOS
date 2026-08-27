import Foundation

/// How much of one month has been lived, as of a given instant.
///
/// Today counts as elapsed. A day already half spent is not a day the person
/// can be offered in full, and treating it as remaining would inflate every
/// ceiling by one day's worth of perfect behaviour that is already partly
/// impossible.
///
/// `MonthWindow` owns the boundary arithmetic; this only divides it.
public struct MonthProgress: Sendable, Equatable {
    public let window: MonthWindow
    public let elapsedDays: Int
    public let remainingDays: Int

    public init(window: MonthWindow, now: Date, calendar: Calendar = .current) {
        self.window = window
        let today = calendar.startOfDay(for: now)

        if today < window.start {
            elapsedDays = 0
        } else if today > window.lastDay {
            elapsedDays = window.daysInMonth
        } else {
            let offset = calendar.dateComponents([.day], from: window.start, to: today).day ?? 0
            elapsedDays = offset + 1
        }
        remainingDays = window.daysInMonth - elapsedDays
    }

    /// True only while there is still a day left to change the outcome. On
    /// the last day of the month the band has collapsed and the score is
    /// whatever it is.
    public var isInFlight: Bool { remainingDays > 0 }

    /// Midnight on each day not yet lived, oldest first. Empty once the
    /// month is over.
    public func remainingDates(calendar: Calendar = .current) -> [Date] {
        guard remainingDays > 0 else { return [] }
        return (elapsedDays..<window.daysInMonth).compactMap {
            calendar.date(byAdding: .day, value: $0, to: window.start)
        }
    }
}

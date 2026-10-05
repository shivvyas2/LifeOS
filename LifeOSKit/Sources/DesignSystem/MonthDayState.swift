import SwiftUI

/// Where a calendar day stands against today. The month grid hatches the
/// past, fills today, and leaves the future on paper.
public enum MonthDayState: Equatable, Sendable {
    case past, today, future

    public static func of(_ date: Date, today: Date = .now, calendar: Calendar = .current) -> MonthDayState {
        if calendar.isDate(date, inSameDayAs: today) { return .today }
        return date < calendar.startOfDay(for: today) ? .past : .future
    }
}

/// The seven days of the week a date falls in, as start-of-day dates, in
/// the calendar's own order.
public enum WeekSpan {
    public static func days(containing date: Date, calendar: Calendar = .current) -> [Date] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }
}

/// Three thin diagonals across a cell, the reference's mark for a day that
/// has gone. Stroke it in the accent.
public struct HatchedCell: Shape {
    let lines: Int

    public init(lines: Int = 3) { self.lines = lines }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.18)
        let count = max(lines, 1)
        let step = inset.width / CGFloat(count + 1)
        for index in 1...count {
            // Each stroke rises to the right at 45°, and is clipped so it
            // never leaves the inset box on either axis.
            let startX = inset.minX + step * CGFloat(index) - step * 0.5
            let run = min(inset.height, inset.maxX - startX)
            path.move(to: CGPoint(x: startX, y: inset.maxY))
            path.addLine(to: CGPoint(x: startX + run, y: inset.maxY - run))
        }
        return path
    }
}

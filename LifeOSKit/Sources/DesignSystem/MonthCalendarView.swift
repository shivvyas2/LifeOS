import SwiftUI

/// Column headings for the dot grid: one narrow weekday letter per column,
/// ordered by the calendar's `firstWeekday`, with today's column accented.
public struct WeekdayHeader: View {
    private let calendar: Calendar
    private let today: Date?
    private let spacing: CGFloat
    @Environment(\.colorScheme) private var scheme

    /// `today` nil paints no column in the accent: a month that is not this
    /// one has no "today" to mark.
    public init(calendar: Calendar = .current, today: Date? = .now, spacing: CGFloat = 8) {
        self.calendar = calendar
        self.today = today
        self.spacing = spacing
    }

    /// Narrow symbols rotated so index 0 is the calendar's first weekday.
    /// `veryShortWeekdaySymbols` is Sunday-first regardless of locale ordering.
    private var symbols: [String] {
        let raw = calendar.veryShortWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return (0..<7).map { raw[($0 + offset) % 7] }
    }

    private var todayColumn: Int? {
        guard let today else { return nil }
        return (calendar.component(.weekday, from: today) - calendar.firstWeekday + 7) % 7
    }

    public var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                Text(symbol)
                    .font(LifeOSType.caption.weight(.semibold))
                    .foregroundStyle(
                        index == todayColumn
                            ? LifeOSTokens.accent
                            : LifeOSTokens.secondaryText.resolve(scheme)
                    )
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// The oversized date headline: day numeral, month and year stacked beneath it,
/// weekday trailing. The numeral is the largest thing on the screen by a wide
/// margin: the date is the anchor the whole hub reads from.
public struct DateHeadline: View {
    private let date: Date
    private let calendar: Calendar
    @Environment(\.colorScheme) private var scheme

    public init(date: Date, calendar: Calendar = .current) {
        self.date = date
        self.calendar = calendar
    }

    public var body: some View {
        let primary = LifeOSTokens.primaryText.resolve(scheme)
        let secondary = LifeOSTokens.secondaryText.resolve(scheme)

        VStack(alignment: .leading, spacing: 0) {
            Text(date.formatted(.dateTime.day().locale(.current)))
                .font(LifeOSType.masthead)
                .tracking(LifeOSType.mastheadTracking)
                .foregroundStyle(primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(date.formatted(.dateTime.month(.wide)).uppercased())
                        .font(LifeOSType.mastheadCaption)
                        .foregroundStyle(primary)
                    Text(date.formatted(.dateTime.year()))
                        .font(LifeOSType.mastheadCaption.weight(.regular))
                        .foregroundStyle(secondary)
                }

                Spacer(minLength: 12)

                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(LifeOSType.mastheadWeekday)
                    .foregroundStyle(secondary)
            }
        }
    }
}

/// The hub's month view: date headline, weekday headings, and the month's dots.
/// Cells are passed in already computed. Deriving them inside a `body` would
/// re-run the calendar maths on every render.
public struct MonthCalendarView: View {
    private let date: Date
    private let cells: [DotCell]
    private let calendar: Calendar
    private let today: Date
    private let onTap: ((DotCell) -> Void)?
    private let spacing: CGFloat = 6

    public init(
        date: Date,
        cells: [DotCell],
        calendar: Calendar = .current,
        today: Date = .now,
        onTap: ((DotCell) -> Void)? = nil
    ) {
        self.date = date
        self.cells = cells
        self.calendar = calendar
        self.today = today
        self.onTap = onTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DateHeadline(date: date, calendar: calendar)

            WeekdayHeader(calendar: calendar, today: today, spacing: spacing)
                .padding(.top, 22)
                .padding(.bottom, 10)

            DotGrid(cells: cells, dotSize: nil, spacing: spacing, onTap: onTap)
        }
    }
}

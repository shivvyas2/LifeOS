import SwiftUI

public struct WeekStrip: View {
    @Binding private var selection: Date
    private let calendar: Calendar
    private let today: Date

    public init(selection: Binding<Date>, calendar: Calendar = .current, today: Date = .now) {
        self._selection = selection
        self.calendar = calendar
        self.today = today
    }

    private var days: [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: selection)?.start ?? selection
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    public var body: some View {
        // Hoisted out of the loop: this is invariant across all seven days, and
        // `startOfDay` is not free enough to repeat once per column.
        let startOfToday = calendar.startOfDay(for: today)

        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let isSelected = calendar.isDate(day, inSameDayAs: selection)
                let isFuture = calendar.startOfDay(for: day) > startOfToday

                VStack(spacing: 6) {
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 11, weight: .semibold))
                        .opacity(0.5)
                    Text(day.formatted(.dateTime.day()))
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(isSelected ? LifeOSTokens.accent : .clear))
                        .foregroundStyle(isSelected ? .white : .primary)
                }
                .opacity(isFuture ? 0.35 : 1)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
                .onTapGesture { if !isFuture { selection = day } }
            }
        }
    }
}

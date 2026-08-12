import SwiftUI

/// The day selector across the top of a domain screen: weekday above the day
/// number, the selected day emphasised, days either side falling away.
///
/// Colours are inherited rather than hard-coded, so the caller sets
/// `.foregroundStyle(LifeOSTokens.onGradient)` on a gradient or a text token on
/// the neutral canvas, and this only modulates opacity and weight.
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
        // Invariant across all seven columns, and `startOfDay` is not free enough
        // to repeat once per column.
        let startOfToday = calendar.startOfDay(for: today)

        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let isSelected = calendar.isDate(day, inSameDayAs: selection)
                let isFuture = calendar.startOfDay(for: day) > startOfToday

                VStack(spacing: 3) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 12, weight: .medium))
                    Text(day.formatted(.dateTime.day()))
                        .font(.system(size: isSelected ? 19 : 16,
                                      weight: isSelected ? .bold : .medium))
                }
                .opacity(isSelected ? 1 : (isFuture ? 0.3 : 0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background {
                    if isSelected {
                        Capsule().fill(LifeOSTokens.onGradient.opacity(0.16))
                    }
                }
                .contentShape(.rect)
                .onTapGesture { if !isFuture { selection = day } }
            }
        }
    }
}

#Preview {
    @Previewable @State var selection = Date()
    ZStack {
        LinearGradient(colors: [ModuleHue.activity.top, ModuleHue.activity.bottom],
                       startPoint: .top, endPoint: .bottom)
        WeekStrip(selection: $selection)
            .foregroundStyle(LifeOSTokens.onGradient)
            .padding()
    }
    .ignoresSafeArea()
}

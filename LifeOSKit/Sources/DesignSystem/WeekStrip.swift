import SwiftUI

/// The day selector across the top of a domain screen: weekday above a
/// circled day number, with an optional per-day progress ring — the reference
/// design's calendar strip.
public struct WeekStrip: View {
    @Binding private var selection: Date
    private let progress: [Date: Double]
    private let calendar: Calendar
    private let today: Date
    @Environment(\.colorScheme) private var scheme

    /// `progress` is keyed by `calendar.startOfDay(for:)`. Days without an
    /// entry show a bare ring track — no data is a gap, not an empty score.
    public init(selection: Binding<Date>, progress: [Date: Double] = [:],
                calendar: Calendar = .current, today: Date = .now) {
        self._selection = selection
        self.progress = progress
        self.calendar = calendar
        self.today = today
    }

    private var days: [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: selection)?.start ?? selection
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    public var body: some View {
        let startOfToday = calendar.startOfDay(for: today)

        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let dayStart = calendar.startOfDay(for: day)
                let isSelected = calendar.isDate(day, inSameDayAs: selection)
                let isFuture = dayStart > startOfToday
                let ring = progress[dayStart].map { min(max($0, 0), 1) }

                VStack(spacing: 6) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(LifeOSType.caption.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))

                    ZStack {
                        Circle()
                            .stroke(LifeOSTokens.dotMissed.resolve(scheme), lineWidth: 2.5)
                        if let ring, !isFuture {
                            Circle()
                                .trim(from: 0, to: ring)
                                .stroke(LifeOSTokens.accent,
                                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        Text(day.formatted(.dateTime.day()))
                            .font(LifeOSType.label.weight(isSelected ? .bold : .medium))
                            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    }
                    .frame(width: 36, height: 36)
                    .background {
                        if isSelected {
                            Circle().fill(LifeOSTokens.accentSoft.resolve(scheme))
                        }
                    }
                }
                .opacity(isFuture ? 0.35 : 1)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
                .onTapGesture { if !isFuture { selection = day } }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }
}

#Preview {
    @Previewable @State var selection = Date()
    let calendar = Calendar.current
    let week = calendar.dateInterval(of: .weekOfYear, for: .now)!.start
    WeekStrip(
        selection: $selection,
        progress: [calendar.startOfDay(for: week): 0.8,
                   calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: week)!): 0.45]
    )
    .padding()
    .background(LifeOSTokens.canvas.resolve(.light))
}

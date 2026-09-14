import SwiftUI
import DesignSystem
import Persistence

/// Event rows for the calendar workspace. Today retains its existing presentation.
struct CalendarEventRow: View {
    let event: CalendarEventSnapshot
    var onTap: ((CalendarEventSnapshot) -> Void)?

    @Environment(\.colorScheme) private var scheme
    private let calendar = Calendar.current

    var body: some View {
        if let onTap {
            Button { onTap(event) } label: { label }
                .buttonStyle(.plain)
                .accessibilityLabel("\(event.title), \(spanLabel)")
        } else {
            label
                .accessibilityElement(children: .combine)
        }
    }

    private var spanLabel: String {
        let calendar = Calendar.current
        if event.isAllDay {
            let lastDay = event.endDate.addingTimeInterval(-1)
            if !calendar.isDate(event.startDate, inSameDayAs: lastDay) {
                return event.startDate.formatted(.dateTime.month().day()) + " – " + lastDay.formatted(.dateTime.month().day()) + " · All day"
            }
            return "All day"
        }
        if !calendar.isDate(event.startDate, inSameDayAs: event.endDate) {
            return event.startDate.formatted(.dateTime.month().day().hour().minute()) + " – " + event.endDate.formatted(.dateTime.month().day().hour().minute())
        }
        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        let end = event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) to \(end)"
    }

    private var label: some View {
        let part = DayPart.of(event, calendar: calendar)
        return HStack(spacing: 12) {
            Image(systemName: part.icon)
                .font(LifeOSType.rowTitle)
                .foregroundStyle(LifeOSTokens.accent)
                .frame(width: 38, height: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(LifeOSTokens.accent.opacity(0.08)))

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(LifeOSType.rowTitle)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .lineLimit(2)
                Text(spanLabel)
                    .font(LifeOSType.label.weight(.regular))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin")
                        .font(.caption).foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme)).lineLimit(1)
                }
            }

            Spacer()

            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(LifeOSType.caption.weight(.semibold))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme).opacity(0.6))
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

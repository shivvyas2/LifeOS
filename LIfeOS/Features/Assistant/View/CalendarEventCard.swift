import SwiftUI
import DesignSystem
import Persistence

/// An event the assistant surfaced, drawn rather than described.
///
/// The reply already says what it says in words. This is the same event as an
/// object you can read at a glance: the time large enough to find, the title
/// beside it, the calendar's own colour down the edge. It carries no icons and
/// no decoration, because a list of events is already a list and does not need
/// to be announced as one.
struct CalendarEventCard: View {
    let event: CalendarEventSnapshot
    @Environment(\.colorScheme) private var scheme

    private var primary: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var secondary: Color { LifeOSTokens.secondaryText.resolve(scheme) }

    /// A colour per calendar, so work and personal are told apart at a glance.
    ///
    /// Derived from the calendar's name rather than read from EventKit, whose
    /// colour does not reach the stored snapshot. Summed character codes
    /// rather than `hashValue`, because Swift seeds its hash per process and
    /// the stripe would change colour on every launch.
    private var stripe: Color {
        let palette: [Color] = [
            Color(red: 0.35, green: 0.62, blue: 0.42),
            Color(red: 0.29, green: 0.53, blue: 0.83),
            Color(red: 0.52, green: 0.41, blue: 0.83),
            Color(red: 0.84, green: 0.46, blue: 0.25),
            Color(red: 0.82, green: 0.38, blue: 0.50),
            Color(red: 0.83, green: 0.66, blue: 0.24),
        ]
        let sum = event.calendarTitle.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[sum % palette.count]
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(stripe)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(LifeOSType.rowTitle)
                    .foregroundStyle(primary)
                    .lineLimit(2)

                Text(timeSpan)
                    .font(LifeOSType.label.weight(.regular))
                    .foregroundStyle(secondary)
            }

            Spacer(minLength: 0)

            if !event.isAllDay {
                Text(duration)
                    .font(LifeOSType.caption.weight(.medium))
                    .foregroundStyle(secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(primary.opacity(scheme == .dark ? 0.12 : 0.05)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(primary.opacity(scheme == .dark ? 0.14 : 0.07), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(timeSpan)")
    }

    /// The day is only named when the event is not today, because repeating
    /// "today" down a list of today's events is noise.
    private var timeSpan: String {
        let calendar = Calendar.current
        let day = calendar.isDateInToday(event.startDate)
            ? ""
            : event.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) + ", "

        if event.isAllDay { return day.isEmpty ? "All day" : String(day.dropLast(2)) + ", all day" }

        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        let end = event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(day)\(start) to \(end)"
    }

    private var duration: String {
        let minutes = Int(event.endDate.timeIntervalSince(event.startDate) / 60)
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }
}

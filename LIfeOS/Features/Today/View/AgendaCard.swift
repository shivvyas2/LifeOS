import SwiftUI
import UIKit
import DesignSystem
import Persistence

/// Shared by `AgendaCard` and `DayDetailSheet`'s schedule section, so both
/// render one event the same way.
extension CalendarEventSnapshot {
    var timeLabel: String {
        isAllDay ? "all day" : startDate.formatted(.dateTime.hour().minute())
    }

    /// "45m", "1h", "1h 30m", or "" for an all-day event. Divides by 60 the
    /// same way `TodayScreen.duration` does, but drops a leading "0h" that
    /// would otherwise clutter every event under an hour. Empty rather than
    /// "all day" because the time slot already says that; a row must omit
    /// this label entirely, not render it a second time.
    var durationLabel: String {
        guard !isAllDay else { return "" }
        let minutes = max(0, Int(endDate.timeIntervalSince(startDate) / 60))
        let hours = minutes / 60
        let mins = minutes % 60
        if hours == 0 { return "\(mins)m" }
        if mins == 0 { return "\(hours)h" }
        return "\(hours)h \(mins)m"
    }

    /// "8:00 to 8:45" or "All day": the row subtitle, reference-style.
    var spanLabel: String {
        guard !isAllDay else { return "All day" }
        let start = startDate.formatted(date: .omitted, time: .shortened)
        let end = endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) to \(end)"
    }
}

/// The stretch of day an event belongs to. Groups the agenda the way the
/// reference design groups its journey: a quiet label per part of the day,
/// each with its own bubble colour, so a glance says when things cluster.
private enum DayPart: Int, CaseIterable, Identifiable {
    case allDay, morning, afternoon, evening

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .allDay:    "All day"
        case .morning:   "Morning"
        case .afternoon: "Afternoon"
        case .evening:   "Evening"
        }
    }

    var icon: String {
        switch self {
        case .allDay:    "calendar"
        case .morning:   "sunrise.fill"
        case .afternoon: "sun.max.fill"
        case .evening:   "moon.fill"
        }
    }

    var hue: ModuleHue {
        switch self {
        case .allDay:    .habits
        case .morning:   .activity
        case .afternoon: .recovery
        case .evening:   .nutrition
        }
    }

    static func of(_ event: CalendarEventSnapshot, calendar: Calendar) -> DayPart {
        guard !event.isAllDay else { return .allDay }
        let hour = calendar.component(.hour, from: event.startDate)
        if hour < 12 { return .morning }
        if hour < 17 { return .afternoon }
        return .evening
    }
}

/// Today's schedule, plus what's coming after it, in the journey style: a
/// titled card with a date chip, icon-bubble rows, and day-part groupings.
/// The agenda card always renders (it carries the permission states);
/// Upcoming only when there is something to show and access is granted.
///
/// A pure function of the snapshot, like every other Today subview: the
/// EventKit prompt itself lives behind `onConnect`, never fired from here.
struct AgendaCard: View {
    let access: CalendarAccessState
    let agenda: [CalendarEventSnapshot]
    let upcoming: [UpcomingEvent]
    let onConnect: () -> Void
    let onAddEvent: () -> Void
    let onTapEvent: (CalendarEventSnapshot) -> Void
    let onOpenToday: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    private let calendar = Calendar.current

    private static let maxAgendaRows = 4
    private static let maxUpcomingRows = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SoftCard {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    body(for: access)
                }
            }

            if access == .authorized, !upcoming.isEmpty {
                SoftCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Upcoming")
                            .font(LifeOSType.body.weight(.bold))
                            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                        upcomingRows
                    }
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(LifeOSType.body.weight(.bold))
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                if access == .authorized, !agenda.isEmpty {
                    Text(agenda.count == 1 ? "1 event on your day" : "\(agenda.count) events on your day")
                        .font(LifeOSType.label.weight(.regular))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }
            }

            Spacer()

            if access == .authorized {
                Button(action: onOpenToday) {
                    HStack(spacing: 4) {
                        Text(Date.now.formatted(.dateTime.month(.abbreviated).day()))
                            .font(LifeOSType.label.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(LifeOSType.eyebrow)
                    }
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(LifeOSTokens.accentSoft.resolve(scheme)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open today's day view")
            }
        }
    }

    // MARK: Agenda body, by access state

    @ViewBuilder
    private func body(for access: CalendarAccessState) -> some View {
        switch access {
        case .notDetermined:
            VStack(alignment: .leading, spacing: 12) {
                Text("See your day's schedule here.")
                    .font(LifeOSType.secondary)
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                CapsuleButton(title: "Connect calendar", action: onConnect)
            }
            .padding(.vertical, 4)

        case .denied:
            VStack(alignment: .leading, spacing: 12) {
                Text("Calendar access is off.")
                    .font(LifeOSType.secondary)
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                CapsuleButton(title: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            }
            .padding(.vertical, 4)

        case .authorized:
            VStack(alignment: .leading, spacing: 12) {
                if agenda.isEmpty {
                    Text("Nothing scheduled today.")
                        .font(LifeOSType.secondary)
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                        .padding(.vertical, 2)
                } else {
                    agendaGroups
                }

                Button("+ Add event", action: onAddEvent)
                    .buttonStyle(.plain)
                    .font(LifeOSType.secondary.weight(.medium))
                    .foregroundStyle(LifeOSTokens.accent)
            }
        }
    }

    /// The first `maxAgendaRows` events, grouped by part of day in order.
    /// Capped before grouping so the card's height budget stays the same
    /// whatever shape the day has.
    private var agendaGroups: some View {
        let visible = Array(agenda.prefix(Self.maxAgendaRows))
        let grouped = DayPart.allCases.compactMap { part -> (DayPart, [CalendarEventSnapshot])? in
            let events = visible.filter { DayPart.of($0, calendar: calendar) == part }
            return events.isEmpty ? nil : (part, events)
        }

        return VStack(alignment: .leading, spacing: 10) {
            ForEach(grouped, id: \.0.id) { part, events in
                VStack(alignment: .leading, spacing: 6) {
                    eyebrow(part.title)
                    ForEach(events) { event in
                        EventJourneyRow(event: event, onTap: onTapEvent)
                    }
                }
            }

            if agenda.count > Self.maxAgendaRows {
                Button(action: onOpenToday) {
                    Text("+\(agenda.count - Self.maxAgendaRows) more")
                        .font(LifeOSType.label)
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Upcoming

    /// Rows grouped under their day label, consecutive runs preserved in
    /// order, so a stacked week reads as short day sections rather than a
    /// table of columns.
    private var upcomingRows: some View {
        let visible = Array(upcoming.prefix(Self.maxUpcomingRows))
        var groups: [(label: String, rows: [UpcomingEvent])] = []
        for row in visible {
            if groups.last?.label == row.dayLabel {
                groups[groups.count - 1].rows.append(row)
            } else {
                groups.append((row.dayLabel, [row]))
            }
        }

        return VStack(alignment: .leading, spacing: 10) {
            ForEach(groups, id: \.label) { group in
                VStack(alignment: .leading, spacing: 6) {
                    eyebrow(group.label)
                    ForEach(group.rows) { row in
                        EventJourneyRow(event: row.event, onTap: onTapEvent)
                    }
                }
            }

            if upcoming.count > Self.maxUpcomingRows {
                Text("+\(upcoming.count - Self.maxUpcomingRows) more")
                    .font(LifeOSType.label)
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
        }
    }

    // MARK: Row building blocks

    /// Small caps label above a run of rows: the same eyebrow vocabulary the
    /// Money bands use, so every card's sections read alike.
    private func eyebrow(_ title: String) -> some View {
        Text(title.uppercased())
            .font(LifeOSType.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
    }
}

/// One event in the journey vocabulary: a pastel icon bubble sized like
/// `IconBubbleTile`'s, the title over its time span, and a quiet chevron
/// when the row opens somewhere. Shared with `DayDetailSheet`'s schedule so
/// an event looks the same wherever it appears.
struct EventJourneyRow: View {
    let event: CalendarEventSnapshot
    var onTap: ((CalendarEventSnapshot) -> Void)?

    @Environment(\.colorScheme) private var scheme
    private let calendar = Calendar.current

    var body: some View {
        if let onTap {
            Button { onTap(event) } label: { label }
                .buttonStyle(.plain)
                .accessibilityLabel("\(event.title), \(event.spanLabel)")
        } else {
            label
                .accessibilityElement(children: .combine)
        }
    }

    private var label: some View {
        let part = DayPart.of(event, calendar: calendar)
        return HStack(spacing: 12) {
            Image(systemName: part.icon)
                .font(LifeOSType.rowTitle)
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .frame(width: 38, height: 38)
                .background(Circle().fill(scheme == .dark ? part.hue.pastelDark : part.hue.pastel))

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(LifeOSType.rowTitle)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .lineLimit(1)
                Text(event.spanLabel)
                    .font(LifeOSType.label.weight(.regular))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
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

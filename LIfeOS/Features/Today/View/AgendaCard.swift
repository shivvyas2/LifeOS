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
///
/// Internal rather than private to this file, because the assistant's agenda
/// card draws its rows with the same icon and hue. One vocabulary for what a
/// morning looks like, wherever the app draws a morning.
enum DayPart: Int, CaseIterable, Identifiable {
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
        VStack(alignment: .leading, spacing: Space.x2) {
            switch access {
            case .authorized: field
            case .notDetermined: teaching
            case .denied: denied
            }
            if access == .authorized, !upcoming.isEmpty { upcomingCard }
        }
    }

    /// The screen's one field: what is next, then the rest of the day.
    private var field: some View {
        let next = agenda.first
        let rest = Array(agenda.dropFirst().prefix(Self.maxAgendaRows))
        return EditorialField(.dusk) {
            HStack(alignment: .firstTextBaseline) {
                Text("Next up").editorialEyebrow()
                Spacer(minLength: Space.x1)
                Button(action: onOpenToday) {
                    HStack(spacing: Space.half) {
                        Text(Date.now.formatted(.dateTime.month(.abbreviated).day()))
                        Image(systemName: "chevron.down")
                    }
                }
                .buttonStyle(.editorial(.quiet, size: .compact))
                .accessibilityLabel("Open today's day view")
            }
            // The headline is the next event, and tapping it opens that event.
            Button { if let next { onTapEvent(next) } } label: {
                VStack(alignment: .leading, spacing: Space.half) {
                    Text(next?.title ?? "Nothing scheduled")
                        .font(Editorial.headline(28)).tracking(-0.6)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(next?.spanLabel ?? "Add a plan when you're ready.")
                        .font(LifeOSType.secondary)
                        .opacity(0.75)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(next == nil)
            .accessibilityLabel(next.map { "\($0.title), \($0.spanLabel)" } ?? "Nothing scheduled")
            ForEach(rest) { event in
                Button { onTapEvent(event) } label: {
                    EditorialRow(event.timeLabel) {
                        HStack(spacing: Space.half) {
                            Text(event.title).lineLimit(1)
                            Image(systemName: "arrow.right").font(LifeOSType.caption.weight(.semibold))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(event.title), \(event.spanLabel)")
            }
            if agenda.count > Self.maxAgendaRows + 1 {
                Button("+\(agenda.count - Self.maxAgendaRows - 1) more", action: onOpenToday)
                    .buttonStyle(.editorial(.quiet, size: .compact))
            }
            Button("Add", action: onAddEvent)
                .buttonStyle(.editorial(.secondary, size: .compact))
        }
    }

    /// Not connected: a ghost of the field and the one action that fills it.
    private var teaching: some View {
        EditorialEmptyState(
            sentence: "Your day's events, with the next one first.",
            action: "Connect calendar",
            onAction: onConnect
        ) {
            VStack(alignment: .leading, spacing: 0) {
                EditorialRow("09:00", value: "Standup")
                EditorialRow("12:30", value: "Lunch with Sam")
                EditorialRow("16:00", value: "Design review")
            }
        }
    }

    private var denied: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text("Calendar access is off.")
                .font(LifeOSType.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.editorial(.secondary, size: .compact))
        }
        .editorialCard()
    }

    private var upcomingCard: some View {
        let visible = Array(upcoming.prefix(Self.maxUpcomingRows))
        var groups: [(label: String, rows: [UpcomingEvent])] = []
        for row in visible {
            if groups.last?.label == row.dayLabel {
                groups[groups.count - 1].rows.append(row)
            } else {
                groups.append((row.dayLabel, [row]))
            }
        }
        return VStack(alignment: .leading, spacing: Space.x2) {
            EditorialSectionHeader(title: "Upcoming")
            ForEach(groups, id: \.label) { group in
                Text(group.label).editorialEyebrow()
                ForEach(group.rows) { row in
                    Button { onTapEvent(row.event) } label: {
                        EditorialRow(row.event.timeLabel) {
                            HStack(spacing: Space.half) {
                                Text(row.event.title).lineLimit(1)
                                Image(systemName: "arrow.right").font(LifeOSType.caption.weight(.semibold))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(row.event.title), \(row.event.spanLabel)")
                }
            }
            if upcoming.count > Self.maxUpcomingRows {
                Text("+\(upcoming.count - Self.maxUpcomingRows) more")
                    .font(LifeOSType.label)
                    .foregroundStyle(Editorial.quietInk(scheme))
            }
        }
        .editorialCard()
    }
}

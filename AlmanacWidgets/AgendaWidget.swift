import SwiftUI
import WidgetKit
import AppSurfaces

struct AgendaEntry: TimelineEntry {
    let date: Date
    let snapshot: AgendaSnapshot?
    var available: Bool { snapshot?.isAvailable(at: date) == true }
}

struct AgendaTimeline: TimelineProvider {
    func placeholder(in context: Context) -> AgendaEntry {
        AgendaEntry(date: .now, snapshot: .sample())
    }
    func getSnapshot(in context: Context, completion: @escaping (AgendaEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : AgendaEntry(date: .now, snapshot: .read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<AgendaEntry>) -> Void) {
        let now = Date.now
        let snapshot = AgendaSnapshot.read()
        var entries = [AgendaEntry(date: now, snapshot: snapshot)]
        if let snapshot {
            // One entry per event end in the next day, so the next-events list
            // rolls forward without waiting for a refresh.
            let ends = snapshot.events.map(\.endDate)
                .filter { $0 > now && $0 < now.addingTimeInterval(86400) && $0 < snapshot.expiresAt }
            for end in Array(Set(ends)).sorted().prefix(24) {
                entries.append(AgendaEntry(date: end, snapshot: snapshot))
            }
            // Explicit expiry entry hides stale data even when refresh is delayed.
            if snapshot.expiresAt > now { entries.append(AgendaEntry(date: snapshot.expiresAt, snapshot: nil)) }
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(1800))))
    }
}

struct AgendaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AgendaSnapshot.widgetKind, provider: AgendaTimeline()) { entry in
            AgendaWidgetView(entry: entry)
                .widgetURL(SurfaceRoute.today.url)
                .containerBackground(for: .widget) { WidgetCanvas() }
        }
        .configurationDisplayName("Your week")
        .description("Your next events and a week at a glance.")
        .supportedFamilies([.accessoryInline, .accessoryRectangular, .systemMedium, .systemLarge])
    }
}

/// Chip tint keyed by calendar name, from the shared widget palette so the
/// Health cards and the agenda chips read as one set.
enum ChipColors {
    static func color(for event: AgendaSnapshot.Event) -> Color {
        WidgetPalette.tints[ChipPalette.index(for: event.calendarTitle) % WidgetPalette.tints.count]
    }
}

struct AgendaWidgetView: View {
    let entry: AgendaEntry
    var previewFamily: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var environmentFamily
    private var family: WidgetFamily { previewFamily ?? environmentFamily }
    private var onField: Bool { family == .systemMedium || family == .systemLarge }

    @ViewBuilder var body: some View {
        // Accessory families are system-tinted, so only the field gets white.
        if onField { base.foregroundStyle(.white) } else { base }
    }
    @ViewBuilder private var base: some View {
        if entry.available, let snapshot = entry.snapshot { content(snapshot) }
        else { empty }
    }

    @ViewBuilder private func content(_ agenda: AgendaSnapshot) -> some View {
        let next = agenda.upcoming(from: entry.date)
        switch family {
        case .accessoryInline:
            if let first = next.first {
                Label("\(timeText(first)) \(first.title)", systemImage: "calendar").privacySensitive()
            } else {
                Label("Nothing scheduled", systemImage: "calendar")
            }
        case .accessoryRectangular:
            if next.isEmpty {
                Label("Nothing scheduled", systemImage: "calendar").font(.headline)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(next) { event in row(event, compact: true) }
                }
            }
        case .systemLarge:
            VStack(alignment: .leading, spacing: 10) {
                strip(agenda)
                let today = agenda.events(on: entry.date)
                if today.isEmpty {
                    Text("Nothing scheduled today").font(.caption).foregroundStyle(WidgetPalette.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(today.prefix(5)) { event in row(event, compact: false) }
                    }
                }
                Spacer(minLength: 0)
            }
        default:
            strip(agenda)
        }
    }

    /// Seven equal columns: weekday and day number over up to four chips.
    /// Today's column sits on a pale highlight with ink text, as the day
    /// headers in the reference do.
    private func strip(_ agenda: AgendaSnapshot) -> some View {
        let calendar = Calendar.current
        let cap = 4
        return HStack(alignment: .top, spacing: 3) {
            ForEach(agenda.weekDays(calendar: calendar), id: \.self) { day in
                let isToday = calendar.isDate(day, inSameDayAs: entry.date)
                let events = agenda.events(on: day, calendar: calendar)
                VStack(spacing: 3) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isToday ? WidgetPalette.ink : WidgetPalette.secondary)
                    Text(day.formatted(.dateTime.day()))
                        .font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(isToday ? WidgetPalette.ink : .white)
                        .padding(.bottom, 2)
                    ForEach(events.prefix(cap)) { event in chip(event) }
                    if events.count > cap {
                        Text("+\(events.count - cap)").font(.system(size: 8, weight: .semibold)).foregroundStyle(WidgetPalette.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 4)
                .background {
                    if isToday { RoundedRectangle(cornerRadius: 8).fill(WidgetPalette.highlight) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide).day())), \(events.count) events")
            }
        }
    }

    private func chip(_ event: AgendaSnapshot.Event) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(event.isAllDay ? "All day" : rangeText(event))
                .font(.system(size: 7, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(event.title).font(.system(size: 8, weight: .medium)).privacySensitive()
        }
        .lineLimit(1).minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 3).padding(.vertical, 2)
        .foregroundStyle(WidgetPalette.ink)
        .background(ChipColors.color(for: event).opacity(WidgetPalette.chipOpacity), in: RoundedRectangle(cornerRadius: 4))
    }

    private func row(_ event: AgendaSnapshot.Event, compact: Bool) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(compact ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
                .frame(width: 3, height: compact ? 14 : 24)
            if compact {
                Text(timeText(event)).font(.system(.caption2, design: .rounded, weight: .semibold)).monospacedDigit()
                Text(event.title).font(.system(.caption, weight: .semibold)).lineLimit(1).privacySensitive()
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title).font(.system(.subheadline, weight: .semibold)).lineLimit(1).privacySensitive()
                    Label(event.isAllDay ? "All day" : rangeText(event), systemImage: "clock")
                        .font(.caption2).monospacedDigit().foregroundStyle(WidgetPalette.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private static let clock = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute()
    /// Start time, or "All day"; an event on a later day than the entry is
    /// prefixed with its weekday so a list that rolls into tomorrow says so.
    private func timeText(_ event: AgendaSnapshot.Event) -> String {
        let time = event.isAllDay ? "All day" : event.startDate.formatted(Self.clock)
        guard !Calendar.current.isDate(event.startDate, inSameDayAs: entry.date), event.startDate > entry.date else { return time }
        return "\(event.startDate.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }
    private func rangeText(_ event: AgendaSnapshot.Event) -> String {
        "\(event.startDate.formatted(Self.clock)) - \(event.endDate.formatted(Self.clock))"
    }

    @ViewBuilder private var empty: some View {
        switch family {
        case .accessoryInline: Label("Open Almanac to sync", systemImage: "calendar")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                Label("Almanac", systemImage: "calendar").font(.headline)
                Text("Open the app to sync your week.").font(.caption)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "calendar").widgetAccentable()
                Text("Your week, at a glance.").font(.headline)
                Text("Open Almanac to sign in or connect a calendar.")
                    .font(.caption).foregroundStyle(WidgetPalette.secondary)
            }
        }
    }
}

extension AgendaSnapshot {
    /// Placeholder and gallery data. Times are relative to `now` so the
    /// strip always shows a populated week.
    static func sample(now: Date = .now, calendar: Calendar = .current) -> AgendaSnapshot {
        let week = window(around: now, calendar: calendar).start
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(byAdding: .minute, value: (day * 24 + hour) * 60 + minute, to: week)!
        }
        func event(_ day: Int, _ start: (Int, Int), _ end: (Int, Int), _ title: String, _ cal: String) -> Event {
            Event(id: UUID(), title: title, calendarTitle: cal, startDate: at(day, start.0, start.1), endDate: at(day, end.0, end.1), isAllDay: false)
        }
        let events = [
            event(0, (7, 0), (8, 0), "Gym", "Health"), event(0, (8, 0), (9, 0), "Weekly Team Sync", "Work"),
            event(0, (12, 30), (13, 30), "Lunch Meeting", "Work"), event(0, (18, 30), (19, 30), "Networking Event", "Personal"),
            event(1, (8, 0), (10, 0), "Client Presentation", "Work"), event(1, (10, 30), (12, 0), "Creative Team", "Work"),
            event(1, (18, 0), (19, 0), "Gym", "Health"), event(2, (8, 30), (9, 30), "Weekly Report", "Work"),
            event(2, (10, 0), (12, 0), "Product Marketing", "Work"), event(2, (14, 0), (17, 0), "Campaign Prep", "Work"),
            event(2, (19, 0), (20, 0), "Dinner with Jun", "Personal"), event(3, (8, 0), (9, 0), "Team Stand-up", "Work"),
            event(3, (9, 0), (11, 30), "Client Review", "Work"), event(3, (17, 0), (18, 0), "Creator Collab", "Personal"),
            event(3, (19, 30), (20, 30), "Korean Class", "Learning"), event(4, (8, 30), (10, 0), "Campaign Launch", "Work"),
            event(4, (10, 30), (12, 0), "Executive Meeting", "Work"), event(4, (15, 30), (16, 30), "Submit Marketing", "Work"),
            event(5, (14, 0), (15, 0), "Pilates Class", "Health"), event(5, (16, 30), (17, 30), "Coffee Date", "Personal"),
            event(5, (19, 0), (20, 0), "Dinner Reservation", "Personal"), event(6, (10, 0), (11, 0), "Brunch with Bell", "Personal"),
            event(6, (18, 0), (19, 0), "Family Dinner", "Family"),
        ]
        return AgendaSnapshot(ownerID: "preview", generatedAt: now, events: events, calendar: calendar)
    }
}

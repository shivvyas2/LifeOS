import SwiftUI
import DesignSystem
import Persistence

/// The events an assistant turn surfaced, drawn as a day you can move around
/// in rather than a stack of cards you can only read.
///
/// The old card was one event, repeated: a reply about four meetings produced
/// four boxes and no sense of the day holding them. This is the day itself.
/// The strip across the top is the week the reply landed in, so the answer to
/// "what about Thursday?" is a tap rather than another question, and the rows
/// below are that day's whole agenda from the store, not only the events the
/// turn happened to name. Days the reply did touch carry an accent dot, which
/// is what keeps the answer visible inside the larger week.
///
/// Reads come straight through `events`; writes leave by `onTapEvent` and
/// `onAddEvent`. The card owns no store and no calendar, so it previews and
/// composes like every other view in the app. On paper: a hairline card, the
/// chosen day as an ink-filled square, rows ruled by hairlines.
struct AssistantAgendaCard: View {
    /// The events this reply was about. Only their days are used, for the
    /// dots on the strip; the rows come from `events` so a day always reads
    /// as itself rather than as the part of it the assistant mentioned.
    let touched: [CalendarEventSnapshot]
    let events: (Date) -> [CalendarEventSnapshot]
    let onTapEvent: (CalendarEventSnapshot) -> Void
    let onAddEvent: (Date) -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var selection: Date

    private let calendar = Calendar.current

    /// Opens on the day the reply was about, not on today. A question about
    /// next Tuesday that answers itself with this morning is not an answer.
    init(
        touched: [CalendarEventSnapshot],
        events: @escaping (Date) -> [CalendarEventSnapshot],
        onTapEvent: @escaping (CalendarEventSnapshot) -> Void,
        onAddEvent: @escaping (Date) -> Void
    ) {
        self.touched = touched
        self.events = events
        self.onTapEvent = onTapEvent
        self.onAddEvent = onAddEvent
        let first = touched.map(\.startDate).min() ?? .now
        _selection = State(initialValue: Calendar.current.startOfDay(for: first))
    }

    private var primary: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var secondary: Color { LifeOSTokens.secondaryText.resolve(scheme) }

    private var week: [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: selection)?.start ?? selection
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// The days the reply named, as day-starts, so the strip can mark them
    /// with one set lookup per column rather than a scan per column.
    private var touchedDays: Set<Date> {
        Set(touched.map { calendar.startOfDay(for: $0.startDate) })
    }

    private var day: [CalendarEventSnapshot] {
        events(selection).sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            return lhs.startDate < rhs.startDate
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            strip.padding(.top, 12)
            rows.padding(.top, 4)
            addButton
        }
        .editorialCard()
    }

    // MARK: - Header

    /// Weekday large on the left, the date stacked small on the right. The
    /// filled accent dot beside the weekday says this is today; a hollow one
    /// says it is another day.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 7) {
                Text(selection.formatted(.dateTime.weekday(.wide)))
                    .font(LifeOSType.sectionTitle)
                    .foregroundStyle(primary)
                Circle()
                    .strokeBorder(LifeOSTokens.accent, lineWidth: 2)
                    .background(Circle().fill(calendar.isDateInToday(selection) ? LifeOSTokens.accent : .clear))
                    .frame(width: 8, height: 8)
            }
            Spacer(minLength: 8)
            Text(selection.formatted(.dateTime.month(.abbreviated).day().year())).editorialEyebrow()
        }
    }

    // MARK: - Week strip

    private var strip: some View {
        HStack(spacing: 0) {
            ForEach(week, id: \.self) { date in
                let isSelected = calendar.isDate(date, inSameDayAs: selection)
                VStack(spacing: 2) {
                    Text(date.formatted(.dateTime.day()))
                        .font(LifeOSType.label.weight(isSelected ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? LifeOSTokens.canvas.resolve(scheme) : primary)
                    Text(date.formatted(.dateTime.weekday(.narrow)))
                        .font(LifeOSType.caption)
                        .foregroundStyle(isSelected ? LifeOSTokens.canvas.resolve(scheme).opacity(0.8) : secondary)
                    // Always laid out, coloured only when the day carries an
                    // event from this reply, so columns never shift.
                    Circle()
                        .fill(touchedDays.contains(calendar.startOfDay(for: date))
                              ? (isSelected ? LifeOSTokens.canvas.resolve(scheme) : LifeOSTokens.accent) : .clear)
                        .frame(width: 3, height: 3)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background { if isSelected { Rectangle().fill(primary) } }
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.18)) { selection = calendar.startOfDay(for: date) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month().day()))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .overlay(Rectangle().strokeBorder(Editorial.rule(scheme)))
    }

    // MARK: - Rows

    @ViewBuilder
    private var rows: some View {
        let events = day
        if events.isEmpty {
            HStack {
                Text("Nothing scheduled.").font(LifeOSType.secondary).foregroundStyle(secondary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 18)
        } else {
            VStack(spacing: 0) {
                ForEach(events) { event in
                    row(event)
                    Hairline()
                }
            }
        }
    }

    /// A row is a time, a title and an arrow, with nothing between them but
    /// space. Past events recede rather than disappear.
    private func row(_ event: CalendarEventSnapshot) -> some View {
        let isPast = event.endDate < .now
        return Button { onTapEvent(event) } label: {
            HStack(spacing: Space.x2) {
                Text(event.isAllDay ? "All day" : event.startDate.formatted(date: .omitted, time: .shortened))
                    .font(LifeOSType.secondary).foregroundStyle(secondary).monospacedDigit()
                    .frame(width: 72, alignment: .leading)
                Text(event.title).font(LifeOSType.secondary.weight(.medium)).foregroundStyle(primary).lineLimit(1)
                Spacer(minLength: Space.x1)
                Image(systemName: "arrow.right").font(LifeOSType.caption.weight(.semibold)).foregroundStyle(primary)
            }
            .padding(.vertical, 12)
            .opacity(isPast ? 0.42 : 1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(event.title), \(event.spanLabel)")
    }

    /// Creates on the day being looked at, not on today.
    private var addButton: some View {
        Button("Add") { onAddEvent(selection) }
            .buttonStyle(.editorial(.secondary, size: .compact))
            .padding(.top, Space.x2)
            .accessibilityLabel("Add an event on \(selection.formatted(.dateTime.month().day()))")
    }
}

#Preview {
    let now = Calendar.current.startOfDay(for: .now)
    func event(_ title: String, _ hour: Int, allDay: Bool = false) -> CalendarEventSnapshot {
        let start = Calendar.current.date(byAdding: .hour, value: hour, to: now) ?? now
        return CalendarEventSnapshot(
            id: UUID(), source: .eventKit, sourceID: title, calendarTitle: "Personal",
            title: title, startDate: start,
            endDate: Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start,
            isAllDay: allDay, isRecurring: false, location: nil, notes: nil
        )
    }
    let day = [
        event("Daria's 20th Birthday", 0, allDay: true),
        event("Wake up", 9),
        event("Design Crit", 10),
        event("Haircut with Vincent", 13),
        event("Wind down", 21),
    ]
    return AssistantAgendaCard(
        touched: [day[2]],
        events: { _ in day },
        onTapEvent: { _ in },
        onAddEvent: { _ in }
    )
    .padding()
}

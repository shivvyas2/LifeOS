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
/// composes like every other view in the app.
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
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(primary.opacity(scheme == .dark ? 0.14 : 0.07), lineWidth: 1)
                )
        )
    }

    // MARK: - Header

    /// Weekday large on the left with the accent dot beside it, date stacked
    /// small on the right. The dot is filled on today and hollow on any other
    /// day, so the card says whether you are looking at now without spending
    /// a word on it.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 7) {
                Text(selection.formatted(.dateTime.weekday(.abbreviated)))
                    .font(LifeOSType.sectionTitle.weight(.bold))
                    .foregroundStyle(primary)
                Circle()
                    .strokeBorder(LifeOSTokens.accent, lineWidth: 2)
                    .background(
                        Circle().fill(
                            calendar.isDateInToday(selection) ? LifeOSTokens.accent : .clear
                        )
                    )
                    .frame(width: 8, height: 8)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: -2) {
                Text(selection.formatted(.dateTime.month(.wide).day()))
                    .font(LifeOSType.label.weight(.semibold))
                    .foregroundStyle(primary)
                Text(selection.formatted(.dateTime.year()))
                    .font(LifeOSType.label.weight(.regular))
                    .foregroundStyle(secondary)
            }
        }
    }

    // MARK: - Week strip

    private var strip: some View {
        HStack(spacing: 2) {
            ForEach(week, id: \.self) { date in
                let isSelected = calendar.isDate(date, inSameDayAs: selection)

                VStack(spacing: 1) {
                    Text(date.formatted(.dateTime.day()))
                        .font(LifeOSType.label.weight(.semibold))
                        .foregroundStyle(isSelected ? primary : secondary)
                    Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                        .font(LifeOSType.eyebrow.weight(.semibold))
                        .foregroundStyle(isSelected ? LifeOSTokens.accent : secondary.opacity(0.8))
                    // Always laid out, coloured only when the day carries an
                    // event from this reply. Hiding it entirely would shift
                    // every other column by three points as the selection moves.
                    Circle()
                        .fill(touchedDays.contains(calendar.startOfDay(for: date))
                              ? LifeOSTokens.accent : .clear)
                        .frame(width: 3, height: 3)
                        .padding(.top, 1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(primary.opacity(scheme == .dark ? 0.10 : 0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(primary.opacity(scheme == .dark ? 0.18 : 0.10),
                                                  lineWidth: 1)
                            )
                    }
                }
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.18)) {
                        selection = calendar.startOfDay(for: date)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month().day()))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private var rows: some View {
        let events = day
        if events.isEmpty {
            HStack {
                Text("Nothing scheduled.")
                    .font(LifeOSType.secondary)
                    .foregroundStyle(secondary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 18)
        } else {
            VStack(spacing: 0) {
                ForEach(events) { event in
                    dottedRule
                    row(event)
                }
                dottedRule
            }
        }
    }

    /// A row is a glyph, a title and a time, with nothing between them but
    /// space. The events already form a list; boxing each one restates that.
    private func row(_ event: CalendarEventSnapshot) -> some View {
        // Past events recede rather than disappear: the day is still the day,
        // but what is left of it is what you are being asked about.
        let isPast = event.endDate < .now

        return Button {
            onTapEvent(event)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: DayPart.of(event, calendar: calendar).icon)
                    .font(LifeOSType.label)
                    .foregroundStyle(primary)
                    .frame(width: 18)

                Text(event.title)
                    .font(LifeOSType.rowTitle)
                    .foregroundStyle(primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                // All-day events say so on the strip's dot and by having no
                // hour; printing "all day" in the time column would make the
                // one row without a time the loudest thing in the list.
                if !event.isAllDay {
                    Text(event.startDate.formatted(date: .omitted, time: .shortened))
                        .font(LifeOSType.label.weight(.regular))
                        .foregroundStyle(secondary)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 11)
            .opacity(isPast ? 0.42 : 1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(event.title), \(event.spanLabel)")
    }

    /// The reference's hairline between rows. Dotted rather than solid so it
    /// separates without ruling the list into a table.
    private var dottedRule: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: 1)
            .overlay(
                Line()
                    .stroke(
                        primary.opacity(scheme == .dark ? 0.16 : 0.10),
                        style: StrokeStyle(lineWidth: 1, dash: [1, 3])
                    )
            )
    }

    /// The reference's floating plus, centred under the day. It creates on
    /// the day being looked at, not on today, which is the only reading that
    /// makes sense directly below that day's events.
    private var addButton: some View {
        HStack {
            Spacer()
            Button {
                onAddEvent(selection)
            } label: {
                Image(systemName: "plus")
                    .font(LifeOSType.label.weight(.semibold))
                    .foregroundStyle(primary)
                    .frame(width: 40, height: 28)
                    .background(Capsule().fill(primary.opacity(scheme == .dark ? 0.12 : 0.06)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add an event on \(selection.formatted(.dateTime.month().day()))")
            Spacer()
        }
        .padding(.top, 12)
    }
}

/// A horizontal rule as a shape, so it can take a dash pattern. `Divider`
/// cannot be stroked.
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
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

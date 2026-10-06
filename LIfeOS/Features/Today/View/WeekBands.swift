import SwiftUI
import DesignSystem
import Persistence

/// The week around the selected day, as stacked bands: the day's number
/// large, its events beside it. The selected day's band is open, with its
/// rows and an Add button; the others show their number and a count until
/// their number is tapped.
///
/// A body view, not a screen: `CalendarScreen` owns the masthead, the mode
/// switch and the scroll, so the bands can sit under them in place of the
/// month grids rather than on a pushed screen of their own.
struct WeekBands: View {
    let model: MonthViewModel
    var onTapEvent: (CalendarEventSnapshot) -> Void = { _ in }
    var onAddEvent: (Date) -> Void = { _ in }

    @Environment(\.colorScheme) private var scheme
    private let calendar = Calendar.current

    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var quiet: Color { Editorial.quietInk(scheme) }
    private var week: [Date] { WeekSpan.days(containing: model.selection, calendar: calendar) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(week, id: \.self) { date in
                band(date)
                Hairline()
            }
        }
    }

    private func events(on date: Date) -> [CalendarEventSnapshot] {
        model.events(on: date).sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            return lhs.startDate < rhs.startDate
        }
    }

    private func numberInk(_ date: Date) -> Color {
        switch MonthDayState.of(date, calendar: calendar) {
        case .today: LifeOSTokens.accent
        case .past: quiet
        case .future: ink
        }
    }

    private func band(_ date: Date) -> some View {
        let rows = events(on: date)
        let isOpen = calendar.isDate(date, inSameDayAs: model.selection)
        return HStack(alignment: .top, spacing: Space.x2) {
            Button {
                withAnimation(.snappy(duration: 0.22)) { model.select(date) }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(date.formatted(.dateTime.day()))
                        .font(Editorial.figure(64)).tracking(Editorial.figureTracking(64))
                        .monospacedDigit()
                        .foregroundStyle(numberInk(date))
                    Text(date.formatted(.dateTime.weekday(.wide))).editorialEyebrow()
                }
                .frame(width: 96, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(date.formatted(.dateTime.weekday(.wide).month().day())), \(rows.count) events")
            .accessibilityHint(isOpen ? "Showing its events" : "Shows its events")
            .accessibilityAddTraits(isOpen ? [.isSelected] : [])

            VStack(alignment: .leading, spacing: Space.x1) {
                if isOpen {
                    if rows.isEmpty {
                        Text("Nothing scheduled").font(LifeOSType.secondary).foregroundStyle(quiet)
                            .padding(.top, Space.x2)
                    }
                    ForEach(rows) { event in
                        Button { onTapEvent(event) } label: {
                            EditorialRow(event.timeLabel) {
                                HStack(spacing: Space.half) {
                                    Text(event.title).lineLimit(2)
                                    Image(systemName: "arrow.right").font(LifeOSType.caption.weight(.semibold))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(event.title), \(event.spanLabel)")
                    }
                    Button("Add") { onAddEvent(date) }
                        .buttonStyle(.editorial(.secondary, size: .compact))
                        .padding(.top, Space.x1)
                } else if !rows.isEmpty {
                    EditorialTag(rows.count == 1 ? "1 event" : "\(rows.count) events")
                        .padding(.top, Space.x2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Space.x2)
    }
}

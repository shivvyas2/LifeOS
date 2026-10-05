import SwiftUI
import DesignSystem
import Persistence

/// The week around a day, as stacked bands: the day's number large, its
/// events beside it. The chosen day opens with its rows and an Add button;
/// the others show their number and a count until tapped.
struct DayScheduleScreen: View {
    let model: MonthViewModel
    let day: Date
    var onTapEvent: (CalendarEventSnapshot) -> Void = { _ in }
    var onAddEvent: (Date) -> Void = { _ in }

    @State private var expanded: Date
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout
    private let calendar = Calendar.current

    init(model: MonthViewModel, day: Date,
         onTapEvent: @escaping (CalendarEventSnapshot) -> Void = { _ in },
         onAddEvent: @escaping (Date) -> Void = { _ in }) {
        self.model = model
        self.day = day
        self.onTapEvent = onTapEvent
        self.onAddEvent = onAddEvent
        _expanded = State(initialValue: Calendar.current.startOfDay(for: day))
    }

    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var quiet: Color { Editorial.quietInk(scheme) }
    private var week: [Date] { WeekSpan.days(containing: day, calendar: calendar) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EditorialMasthead(eyebrow: "Weekly · \(day.formatted(.dateTime.month(.wide)))",
                                  title: weekTitle)
                    .padding(.bottom, Space.x2)
                ForEach(week, id: \.self) { date in
                    band(date)
                    Hairline()
                }
            }
            .frame(maxWidth: layout.maxContentWidth)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, layout.gutter)
            .padding(.leading, layout.railInset)
            .padding(.top, Space.x2)
            .padding(.bottom, layout.contentBottomInset)
        }
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var weekTitle: String {
        guard let first = week.first, let last = week.last else { return "" }
        let style = Date.FormatStyle().month(.abbreviated).day()
        return "\(first.formatted(style)) to \(last.formatted(style))"
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
        let isOpen = calendar.isDate(date, inSameDayAs: expanded)
        return HStack(alignment: .top, spacing: Space.x2) {
            Button {
                withAnimation(.snappy(duration: 0.22)) { expanded = calendar.startOfDay(for: date) }
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

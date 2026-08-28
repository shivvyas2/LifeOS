import SwiftUI
import SwiftData
import DesignSystem
import Persistence

/// A whole month of the calendar, and the selected day's schedule beneath it.
///
/// Today's month grid shows how the habit streak has been going, one dot per
/// day, and cannot leave the current month. This is the other question: what
/// is on, across a month you can move through. The grid carries day numbers
/// and up to three event dots per day; the agenda under it is the selected
/// day, in the same row vocabulary the assistant's card and the Today tab use.
struct MonthScreen: View {
    @State private var model = MonthViewModel()
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme

    /// Create and edit leave through the caller, which owns `CalendarSync`.
    /// This screen never writes: it has no more business talking to EventKit
    /// than `AgendaCard` does.
    var onTapEvent: (CalendarEventSnapshot) -> Void = { _ in }
    var onAddEvent: (Date) -> Void = { _ in }

    private let calendar = Calendar.current

    private var primary: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var secondary: Color { LifeOSTokens.secondaryText.resolve(scheme) }

    private var cells: [DotCell] {
        // The states are ignored: this grid draws event dots, not habit
        // status. `MonthGridLayout` is used for the part that is genuinely
        // fiddly, which is how many blanks come before the first and after
        // the last, given the locale's first weekday.
        MonthGridLayout.cells(
            monthContaining: model.month, calendar: calendar, today: .now, status: { _ in .noData }
        )
    }

    var body: some View {
        GradientCanvas(hue: .recovery) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    grid
                    agenda
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Today") { model.goToToday() }
                    .disabled(calendar.isDate(model.month, equalTo: .now, toGranularity: .month))
            }
        }
        .task { model.attach(context) }
        // A write made from the sheet this screen opens lands in the store,
        // not in this view model, so the month is re-read when the save
        // notification arrives rather than left showing the old dots.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            model.load()
        }
    }

    // MARK: - Month header

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: -2) {
                Text(model.month.formatted(.dateTime.month(.wide)).uppercased())
                    .font(LifeOSType.sectionTitle.weight(.bold))
                    .foregroundStyle(primary)
                Text(model.month.formatted(.dateTime.year()))
                    .font(LifeOSType.secondary)
                    .foregroundStyle(secondary)
            }

            Spacer(minLength: 0)

            stepButton("chevron.left", months: -1, label: "Previous month")
            stepButton("chevron.right", months: 1, label: "Next month")
        }
    }

    private func stepButton(_ icon: String, months: Int, label: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { model.step(months) }
        } label: {
            Image(systemName: icon)
                .font(LifeOSType.label.weight(.semibold))
                .foregroundStyle(primary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(primary.opacity(scheme == .dark ? 0.12 : 0.06)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Grid

    private var grid: some View {
        VStack(spacing: 8) {
            WeekdayHeader(calendar: calendar, today: model.month, spacing: 6)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
                spacing: 6
            ) {
                ForEach(cells) { cell in
                    if let date = cell.date {
                        dayCell(date)
                    } else {
                        // Keeps the row rectangular. `Color.clear` alone has
                        // no intrinsic height and would collapse the row.
                        Color.clear.frame(height: 46)
                    }
                }
            }
        }
        // A swipe is how people move through months everywhere else, and the
        // chevrons stay for anyone who would rather aim than swipe.
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        model.step(value.translation.width < 0 ? 1 : -1)
                    }
                }
        )
    }

    private func dayCell(_ date: Date) -> some View {
        let events = model.events(on: date)
        let isSelected = calendar.isDate(date, inSameDayAs: model.selection)
        let isToday = calendar.isDateInToday(date)

        return Button {
            model.select(date)
        } label: {
            VStack(spacing: 3) {
                Text(date.formatted(.dateTime.day()))
                    .font(LifeOSType.label.weight(isToday ? .bold : .medium))
                    .foregroundStyle(isToday ? LifeOSTokens.accent : primary)

                // Three at most. A day with nine events is a day with a lot
                // on, which three dots and a heavier row in the agenda say
                // better than nine dots two points wide.
                HStack(spacing: 2) {
                    ForEach(0..<min(events.count, 3), id: \.self) { _ in
                        Circle()
                            .fill(isSelected ? primary : secondary.opacity(0.8))
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(primary.opacity(scheme == .dark ? 0.14 : 0.07))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(date.formatted(.dateTime.weekday(.wide).month().day())), \(events.count) events"
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - The selected day

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.selection.formatted(.dateTime.weekday(.wide).month().day()).uppercased())
                    .font(LifeOSType.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(secondary)
                Spacer()
                Button {
                    onAddEvent(model.selection)
                } label: {
                    Image(systemName: "plus")
                        .font(LifeOSType.label.weight(.semibold))
                        .foregroundStyle(primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add an event on this day")
            }

            let events = model.selectedEvents
            if events.isEmpty {
                Text("Nothing scheduled.")
                    .font(LifeOSType.secondary)
                    .foregroundStyle(secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(events.sorted { lhs, rhs in
                    if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                    return lhs.startDate < rhs.startDate
                }) { event in
                    EventJourneyRow(event: event, onTap: onTapEvent)
                }
            }
        }
    }
}

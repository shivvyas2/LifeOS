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
    @Environment(\.layout) private var layout
    @State private var showDatePicker = false

    /// Create and edit leave through the caller, which owns `CalendarSync`.
    /// This screen never writes: it has no more business talking to EventKit
    /// than `AgendaCard` does.
    var onTapEvent: (CalendarEventSnapshot) -> Void = { _ in }
    var onAddEvent: (Date) -> Void = { _ in }

    var isCalendarConnected = true
    var onConnectCalendar: () -> Void = {}

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
        ScrollView {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 28) {
                    calendarPanel.frame(width: 400)
                    agenda.frame(minWidth: 320, maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 28) {
                    calendarPanel
                    agenda
                }
            }
            .padding(.horizontal, layout.gutter)
            .padding(.leading, layout.railInset)
            .padding(.top, 16)
            .padding(.bottom, layout.contentBottomInset)
        }
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
        .tint(LifeOSTokens.accent)
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                DatePicker("Go to date", selection: Binding(get: { model.selection }, set: {
                    model.goTo($0)
                    showDatePicker = false
                }), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Go to date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showDatePicker = false }
                } }
            }
            .presentationDetents([.medium, .large])
            .tint(LifeOSTokens.accent)
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Today") { model.goToToday() }
                    .disabled(calendar.isDateInToday(model.selection))
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

    private var calendarPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            grid
        }
        .padding(16)
        .background(LifeOSTokens.cardSurface.resolve(scheme), in: RoundedRectangle(cornerRadius: 20))
    }

    private var header: some View {
        HStack(spacing: 16) {
            Button { showDatePicker = true } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.month.formatted(.dateTime.month(.wide)))
                        .font(LifeOSType.sectionTitle.weight(.bold))
                        .foregroundStyle(primary)
                    Text(model.month.formatted(.dateTime.year()))
                        .font(LifeOSType.secondary)
                        .foregroundStyle(secondary)
                }

            }
            .buttonStyle(.plain)
            .accessibilityHint("Choose any date")
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
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(primary.opacity(0.045)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Grid

    private var grid: some View {
        VStack(spacing: 8) {
            WeekdayHeader(calendar: calendar, today: model.month, spacing: 2)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7),
                spacing: 2
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
                    .foregroundStyle(isSelected ? Color.white : (isToday ? LifeOSTokens.accent : primary))

                // Three at most. A day with nine events is a day with a lot
                // on, which three dots and a heavier row in the agenda say
                // better than nine dots two points wide.
                HStack(spacing: 2) {
                    ForEach(0..<min(events.count, 3), id: \.self) { _ in
                        Circle()
                            .fill(isSelected ? Color.white : LifeOSTokens.accent)
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
                        .fill(LifeOSTokens.accent)
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(calendar.isDateInToday(model.selection) ? "Today" : model.selection.formatted(.dateTime.weekday(.wide)))
                        .font(.title2.bold()).foregroundStyle(primary)
                    Text(model.selection.formatted(.dateTime.month(.wide).day()))
                        .font(.subheadline).foregroundStyle(secondary)
                }
                Spacer()
                Button {
                    if isCalendarConnected { onAddEvent(model.selection) } else { onConnectCalendar() }
                } label: {
                    Image(systemName: "plus")
                        .font(LifeOSType.label.weight(.semibold))
                        .foregroundStyle(LifeOSTokens.accent)
                        .frame(width: 44, height: 44)
                        .background(primary, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add an event on this day")
            }

            if !isCalendarConnected {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Bring your plans together").font(.headline)
                    Text("Connect your calendar to see and manage your events here.")
                        .font(.subheadline).foregroundStyle(secondary)
                    Button("Connect calendar", action: onConnectCalendar).frame(minHeight: 44)
                }
                .padding(16)
                .background(LifeOSTokens.cardSurface.resolve(scheme), in: RoundedRectangle(cornerRadius: 16))
            }
            let events = model.selectedEvents
            if events.isEmpty && isCalendarConnected {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "sun.horizon").font(.title).foregroundStyle(LifeOSTokens.accent)
                    Text("A little room in your day").font(.headline)
                    Text("Nothing scheduled. Add a plan when you’re ready.")
                        .font(.subheadline).foregroundStyle(secondary)
                    Button("Add an event") { onAddEvent(model.selection) }
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(LifeOSTokens.cardSurface.resolve(scheme), in: RoundedRectangle(cornerRadius: 16))
            } else if !events.isEmpty {
                Text("\(events.count) \(events.count == 1 ? "event" : "events")")
                    .font(.subheadline).foregroundStyle(secondary)
                ForEach(events.sorted { lhs, rhs in
                    if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                    return lhs.startDate < rhs.startDate
                }) { event in
                    CalendarEventRow(event: event, onTap: onTapEvent)
                }
            }
        }
    }
}

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
/// Two months on hairlines: this one and the next. Past days are hatched,
/// today is the accent, a dot marks a day with events, and a tap pushes the
/// week's schedule at that day.
struct MonthScreen: View {
    @State private var model = MonthViewModel()
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout
    @Environment(\.dismiss) private var dismiss
    @State private var showDatePicker = false
    @State private var openDay: ScheduleDay?

    var onTapEvent: (CalendarEventSnapshot) -> Void = { _ in }
    var onAddEvent: (Date) -> Void = { _ in }
    var isCalendarConnected = true
    var onConnectCalendar: () -> Void = {}

    private let calendar = Calendar.current
    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var paper: Color { LifeOSTokens.canvas.resolve(scheme) }

    /// A pushed day. `Date` is not `Identifiable`, and the push needs one.
    struct ScheduleDay: Identifiable, Hashable {
        let date: Date
        var id: Date { date }
    }

    private var months: [Date] {
        [model.month, calendar.date(byAdding: .month, value: 1, to: model.month) ?? model.month]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x4) {
                header
                if !isCalendarConnected { connectCard }
                ForEach(months, id: \.self) { month in
                    monthBlock(month)
                }
                Button("Go back") { dismiss() }
                    .buttonStyle(.editorial(.secondary, fullWidth: true))
            }
            .frame(maxWidth: layout.maxContentWidth)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, layout.gutter)
            .padding(.leading, layout.railInset)
            .padding(.top, Space.x2)
            .padding(.bottom, layout.contentBottomInset)
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
        .background(paper.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Today") { model.goToToday() }
                    .disabled(calendar.isDate(model.month, equalTo: .now, toGranularity: .month))
            }
        }
        .navigationDestination(item: $openDay) { day in
            DayScheduleScreen(model: model, day: day.date, onTapEvent: onTapEvent, onAddEvent: onAddEvent)
        }
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
        }
        .task { model.attach(context) }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            model.load()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Button { showDatePicker = true } label: {
                EditorialMasthead(eyebrow: "Monthly · \(model.month.formatted(.dateTime.year()))", title: "Calendar")
            }
            .buttonStyle(.plain)
            .accessibilityHint("Choose any date")
            Spacer(minLength: Space.x1)
            stepButton("chevron.left", months: -1, label: "Previous month")
            stepButton("chevron.right", months: 1, label: "Next month")
        }
    }

    private func stepButton(_ icon: String, months: Int, label: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { model.step(months) }
        } label: {
            Image(systemName: icon)
        }
        .buttonStyle(.editorial(.secondary, size: .compact))
        .accessibilityLabel(label)
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text("Connect your calendar to see and manage your events here.")
                .font(LifeOSType.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Connect calendar", action: onConnectCalendar)
                .buttonStyle(.editorial(.primary, size: .compact))
        }
        .editorialCard()
    }

    private func monthBlock(_ month: Date) -> some View {
        let isCurrent = calendar.isDate(month, equalTo: .now, toGranularity: .month)
        return VStack(alignment: .leading, spacing: Space.x2) {
            Text(month.formatted(.dateTime.month(.wide)))
                .font(Editorial.headline(34)).tracking(-1)
                .foregroundStyle(isCurrent ? LifeOSTokens.accent : ink)
                .accessibilityAddTraits(.isHeader)
            WeekdayHeader(calendar: calendar, today: month, spacing: 0)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(MonthGridLayout.cells(monthContaining: month, calendar: calendar, today: .now, status: { _ in .noData })) { cell in
                    if let date = cell.date {
                        dayCell(date)
                    } else {
                        Color.clear.frame(height: 48)
                    }
                }
            }
            .overlay(Rectangle().strokeBorder(Editorial.rule(scheme)))
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let state = MonthDayState.of(date, calendar: calendar)
        let count = model.events(on: date).count
        return Button {
            openDay = ScheduleDay(date: date)
        } label: {
            ZStack {
                if state == .today { Rectangle().fill(LifeOSTokens.accent) }
                if state == .past {
                    HatchedCell().stroke(LifeOSTokens.accent, lineWidth: 1).opacity(0.55)
                }
                VStack(spacing: 3) {
                    Text(date.formatted(.dateTime.day()))
                        .font(LifeOSType.label.weight(state == .today ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(state == .today ? paper : ink)
                    Circle()
                        .fill(state == .today ? paper : ink)
                        .frame(width: 3, height: 3)
                        .opacity(count > 0 ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .overlay(Rectangle().strokeBorder(Editorial.rule(scheme), lineWidth: 0.5))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(date.formatted(.dateTime.weekday(.wide).month().day())), \(count) events")
        .accessibilityAddTraits(state == .today ? [.isSelected] : [])
    }
}

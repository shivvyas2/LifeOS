import SwiftUI
import SwiftData
import DesignSystem
import Insights
import Persistence

/// The calendar behind the header's calendar button: one screen, two faces.
///
/// Monthly is this month and the next on hairline grids, past days hatched,
/// today in the accent, a dot on days with events. Weekly is the seven days
/// around the selected day as stacked bands. The switch moves between them
/// in place, and a tapped day in Monthly opens its week; nothing is pushed,
/// so the way back is always the one Back button.
struct CalendarScreen: View {
    @State private var model = MonthViewModel()
    @State private var mode: CalendarMode
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout
    @Environment(\.dismiss) private var dismiss
    @State private var showDatePicker = false
    /// What the person is finding. Trimmed for matching; the block and the
    /// marks show only while the trimmed text is not empty.
    @State private var query: String
    /// The question asked from here and, once answered, its reply. While
    /// set, the reply card stands where the results block would.
    @State private var asked: CalendarAsk?

    /// The one assistant the app owns; nil in previews that never ask.
    private let assistant: AssistantViewModel?
    /// For the `calendar-ask` preview: adopt the conversation's last reply
    /// as the answer to this question on appear, so no model runs.
    private let initialQuestion: String?

    /// A day to open on instead of today. For previews and deep links; the
    /// header button passes nothing.
    private let initialSelection: Date?
    var onTapEvent: (CalendarEventSnapshot) -> Void
    var onAddEvent: (Date) -> Void
    var isCalendarConnected: Bool
    var onConnectCalendar: () -> Void

    init(
        assistant: AssistantViewModel? = nil,
        initialMode: CalendarMode = .monthly,
        initialSelection: Date? = nil,
        initialQuery: String = "",
        initialQuestion: String? = nil,
        onTapEvent: @escaping (CalendarEventSnapshot) -> Void = { _ in },
        onAddEvent: @escaping (Date) -> Void = { _ in },
        isCalendarConnected: Bool = true,
        onConnectCalendar: @escaping () -> Void = {}
    ) {
        _mode = State(initialValue: initialMode)
        _query = State(initialValue: initialQuery)
        self.assistant = assistant
        self.initialSelection = initialSelection
        self.initialQuestion = initialQuestion
        self.onTapEvent = onTapEvent
        self.onAddEvent = onAddEvent
        self.isCalendarConnected = isCalendarConnected
        self.onConnectCalendar = onConnectCalendar
    }

    private static let topID = "calendar-top"
    private let calendar = Calendar.current
    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var paper: Color { LifeOSTokens.canvas.resolve(scheme) }

    private var months: [Date] {
        [model.month, calendar.date(byAdding: .month, value: 1, to: model.month) ?? model.month]
    }

    private var headline: CalendarHeadline {
        CalendarHeadline.make(mode: mode, month: model.month, selection: model.selection, calendar: calendar)
    }

    /// Nothing to go back to: the shown month is this month, or the shown
    /// week holds today.
    private var isOnToday: Bool {
        switch mode {
        case .monthly:
            calendar.isDate(model.month, equalTo: .now, toGranularity: .month)
        case .weekly:
            WeekSpan.days(containing: model.selection, calendar: calendar).contains { calendar.isDateInToday($0) }
        }
    }

    private var quiet: Color { Editorial.quietInk(scheme) }

    private var isFinding: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Everything the model holds: the two shown months and their padding.
    /// Nothing is fetched on a keystroke.
    private var results: [CalendarEventSnapshot] {
        guard isFinding else { return [] }
        return ScheduleSearch.matches(query, in: model.eventsByDay.values.flatMap { $0 })
    }

    /// Shows the week of an event: a result tap, and later a reply's events.
    /// The query stays so several results can be visited.
    private func reveal(_ event: CalendarEventSnapshot) {
        withAnimation(.snappy(duration: 0.22)) {
            if model.holds(event.startDate) {
                model.select(event.startDate)
            } else {
                // A reply about a flight in January, asked in October: the
                // week is not loaded, so move the calendar there.
                model.goTo(event.startDate)
            }
            mode = .weekly
        }
    }

    /// An assistant was passed, the device model is there, and the calendar
    /// is connected. Find works without any of these.
    private var canAsk: Bool {
        guard let assistant else { return false }
        return assistant.modelAvailable && assistant.isAuthorized
    }

    /// The calendar is connected but the model is not on this device: say
    /// so under the field once there is text, instead of a dead arrow.
    private var needsModel: Bool {
        guard let assistant, isFinding else { return false }
        return assistant.isAuthorized && !assistant.modelAvailable
    }

    /// Hands the words to the assistant as a turn in the one conversation
    /// the sheet shows, then adopts its reply.
    private func ask() async {
        guard let assistant, canAsk, !assistant.isThinking else { return }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        query = ""
        asked = CalendarAsk(question: text, replyID: nil)
        assistant.draft = text
        await assistant.send()
        adoptReply(for: text)
    }

    /// The reply is the conversation's last assistant turn. The calendar
    /// follows it: the earliest event it was about opens in Weekly.
    private func adoptReply(for question: String) {
        guard let assistant,
              let reply = assistant.messages.last(where: { $0.role == .assistant })
        else { return }
        asked = CalendarAsk(question: question, replyID: reply.id)
        if let first = assistant.eventsByMessage[reply.id]?.first {
            reveal(first)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                let found = results
                let matchingDays = Set(found.map { calendar.startOfDay(for: $0.startDate) })
                VStack(alignment: .leading, spacing: Space.x3) {
                    header
                    UnderlinePicker(
                        selection: $mode.animation(.snappy(duration: 0.22)),
                        options: [(.monthly, "Monthly"), (.weekly, "Weekly")]
                    )
                    findField
                    if let asked, let assistant {
                        AssistantReplyCard(ask: asked, assistant: assistant, onSelect: reveal,
                                           onClear: {
                                               // A write still awaiting a yes gets a no, or the
                                               // turn would wait forever behind a hidden card.
                                               for write in assistant.pending { assistant.cancel(write.id) }
                                               self.asked = nil
                                           })
                    } else if isFinding {
                        ScheduleResultsBlock(results: found, months: months, onSelect: reveal)
                    }
                    if !isCalendarConnected { connectCard }
                    switch mode {
                    case .monthly:
                        VStack(alignment: .leading, spacing: Space.x4) {
                            ForEach(months, id: \.self) { month in
                                monthBlock(month, matching: matchingDays)
                            }
                        }
                    case .weekly:
                        WeekBands(model: model, highlighted: Set(found.map(\.id)),
                                  onTapEvent: onTapEvent, onAddEvent: onAddEvent)
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
                            step(value.translation.width < 0 ? 1 : -1)
                        }
                )
            }
            .background(paper.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
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
            .task {
                model.attach(context)
                if let initialSelection { model.goTo(initialSelection) }
                await assistant?.appear()
                if let initialQuestion { adoptReply(for: initialQuestion) }
            }
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                model.load()
            }
            .onChange(of: isCalendarConnected) { _, connected in
                // Connected from this screen's card: the assistant learns of
                // it the way it does on appear, so the ask arrow can show.
                if connected { Task { await assistant?.appear() } }
            }
            .onChange(of: mode) { _, _ in
                // The grids can be scrolled a long way down when a day in the
                // second month is tapped; the week that opens must arrive with
                // the line that names it, not mid-list.
                withAnimation(.snappy(duration: 0.22)) { proxy.scrollTo(Self.topID, anchor: .top) }
            }
        }
    }

    /// One step in whichever unit the mode shows: a month on the grids, a
    /// week on the bands.
    private func step(_ direction: Int) {
        withAnimation(.easeOut(duration: 0.18)) {
            switch mode {
            case .monthly: model.step(direction)
            case .weekly: model.stepWeek(direction)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
            Button { showDatePicker = true } label: {
                EditorialMasthead(eyebrow: headline.eyebrow, title: headline.title, detail: headline.detail)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Choose any date")
            Spacer(minLength: Space.x1)
            Button("Today") {
                withAnimation(.easeOut(duration: 0.18)) { model.goToToday() }
            }
            .buttonStyle(.editorial(.secondary, size: .compact))
            .disabled(isOnToday)
            .accessibilityHint(mode == .monthly ? "Shows this month" : "Shows this week")
            stepButton("chevron.left", direction: -1, label: mode == .monthly ? "Previous month" : "Previous week")
            stepButton("chevron.right", direction: 1, label: mode == .monthly ? "Next month" : "Next week")
        }
    }

    private func stepButton(_ icon: String, direction: Int, label: String) -> some View {
        Button { step(direction) } label: {
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

    private var findField: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            HairlineField(text: $query, placeholder: ScheduleFindText.placeholder,
                          onSubmit: { Task { await ask() } }) {
                if isFinding, canAsk { askArrow }
            }
            if needsModel {
                Text(ScheduleFindText.needsModel)
                    .font(LifeOSType.caption).foregroundStyle(quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// An ink circle with `arrow.up` in paper: the composer's send, at the
    /// field's size.
    private var askArrow: some View {
        Button { Task { await ask() } } label: {
            Image(systemName: "arrow.up")
                .font(LifeOSType.label.weight(.semibold))
                .foregroundStyle(paper)
                .frame(width: 32, height: 32)
                .background(Circle().fill(ink))
        }
        .buttonStyle(.plain)
        .disabled(assistant?.isThinking ?? true)
        .accessibilityLabel("Ask")
    }

    private func monthBlock(_ month: Date, matching: Set<Date>) -> some View {
        let isCurrent = calendar.isDate(month, equalTo: .now, toGranularity: .month)
        return VStack(alignment: .leading, spacing: Space.x2) {
            Text(month.formatted(.dateTime.month(.wide)))
                .font(Editorial.headline(34)).tracking(-1)
                .foregroundStyle(isCurrent ? LifeOSTokens.accent : ink)
                .accessibilityAddTraits(.isHeader)
            WeekdayHeader(calendar: calendar, today: isCurrent ? .now : nil, spacing: 0)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(MonthGridLayout.cells(monthContaining: month, calendar: calendar, today: .now, status: { _ in .noData })) { cell in
                    if let date = cell.date {
                        dayCell(date, isMatch: matching.contains(calendar.startOfDay(for: date)))
                    } else {
                        Color.clear.frame(height: 48)
                    }
                }
            }
            .overlay(Rectangle().strokeBorder(Editorial.rule(scheme)))
        }
    }

    /// A tap selects the day and turns the screen to its week. Nothing is
    /// pushed: the week appears under the same masthead, with this day's
    /// band open.
    private func dayCell(_ date: Date, isMatch: Bool) -> some View {
        let state = MonthDayState.of(date, calendar: calendar)
        let count = model.events(on: date).count
        let mark: Color = state == .today ? paper : (isMatch ? LifeOSTokens.accent : ink)
        return Button {
            model.select(date)
            withAnimation(.snappy(duration: 0.22)) { mode = .weekly }
        } label: {
            ZStack {
                if state == .today { Rectangle().fill(LifeOSTokens.accent) }
                if state == .past {
                    HatchedCell().stroke(LifeOSTokens.accent, lineWidth: 1).opacity(0.55)
                }
                VStack(spacing: 3) {
                    Text(date.formatted(.dateTime.day()))
                        .font(LifeOSType.label.weight(state == .today || isMatch ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(mark)
                    Circle()
                        .fill(mark)
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
        .accessibilityHint("Shows its week")
        .accessibilityAddTraits(state == .today ? [.isSelected] : [])
    }
}

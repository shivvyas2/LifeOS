import SwiftUI
import SwiftData
import Combine
import DesignSystem
import Persistence
import Integrations

/// One day in full, pushed: where it sits, the weather and what to wear,
/// what is on, the checklist, the readings, the spend, what LIFO said.
/// Today is the centre; a past day is a record, a day ahead a plan.
struct DayScreen: View {
    @State private var model: DayViewModel
    /// The date the shell asked for. A route that lands while the screen is
    /// up changes it in place, and the model follows.
    private let date: Date
    @Environment(\.modelContext) private var context
    @Environment(\.dayProviders) private var providers
    @Environment(\.noteSync) private var sync
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.shellProfile) private var shellProfile
    @State private var showDatePicker = false
    @State private var newTask = ""
    @State private var openPage: UUID?
    var onTapEvent: (CalendarEventSnapshot) -> Void
    var onAddEvent: (Date) -> Void
    /// A habit row's text: the shell owns the plan model the habits screen
    /// needs, so it decides what opens.
    var onOpenHabits: () -> Void

    init(date: Date,
         onTapEvent: @escaping (CalendarEventSnapshot) -> Void = { _ in },
         onAddEvent: @escaping (Date) -> Void = { _ in },
         onOpenHabits: @escaping () -> Void = {}) {
        _model = State(initialValue: DayViewModel(date: date))
        self.date = date
        self.onTapEvent = onTapEvent
        self.onAddEvent = onAddEvent
        self.onOpenHabits = onOpenHabits
    }

    private let calendar = Calendar.current
    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var paper: Color { LifeOSTokens.canvas.resolve(scheme) }
    private var quiet: Color { Editorial.quietInk(scheme) }
    private var headline: DayHeadline { DayHeadline.make(date: model.date, calendar: calendar) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                header
                if let briefing = model.briefing {
                    ForEach(briefing.sections, id: \.self) { section in
                        sectionView(section, briefing: briefing)
                    }
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
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await model.refreshProject() }
        .background(paper.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openPage) { id in
            NoteEditorHost(documentID: id, onOpenLinked: { openPage = $0 })
        }
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                DatePicker("Go to date", selection: Binding(get: { model.date }, set: {
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
            model.attach(context, providers: providers, sync: sync)
            model.load()
        }
        .onChange(of: date) { _, newDate in model.goTo(newDate) }
        // Saves arrive in bursts (a tick, a health sample, a sync); one reload
        // a quarter second after the last is enough.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
            model.load()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
            Button { showDatePicker = true } label: {
                EditorialMasthead(eyebrow: headline.eyebrow, title: headline.title, detail: model.briefing?.dayLook)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Choose any date")
            Spacer(minLength: Space.x1)
            Button("Today") {
                withAnimation(.easeOut(duration: 0.18)) { model.goToToday() }
            }
            .buttonStyle(.editorial(.secondary, size: .compact))
            .disabled(model.isOnToday)
            .accessibilityHint("Shows today")
            stepButton("chevron.left", direction: -1, label: "Previous day")
            stepButton("chevron.right", direction: 1, label: "Next day")
        }
    }

    private func stepButton(_ icon: String, direction: Int, label: String) -> some View {
        Button { step(direction) } label: { Image(systemName: icon) }
            .buttonStyle(.editorial(.secondary, size: .compact))
            .accessibilityLabel(label)
    }

    private func step(_ direction: Int) {
        withAnimation(.easeOut(duration: 0.18)) { model.step(direction) }
    }

    // MARK: Sections

    /// Numbered from the first numbered section: the weather card carries
    /// no index, so `The day` is `01` whether or not a forecast is shown.
    /// A day without a project card skips its number, so the rest stay
    /// consecutive.
    private func number(of section: DaySection, in briefing: DayBriefing) -> Int? {
        briefing.sections.filter { $0 != .weather && ($0 != .project || briefing.project != nil) }
            .firstIndex(of: section).map { $0 + 1 }
    }

    @ViewBuilder
    private func sectionView(_ section: DaySection, briefing: DayBriefing) -> some View {
        switch section {
        case .weather:
            WeatherCard(state: briefing.weather, isToday: model.isOnToday) {
                Task { await model.allowLocation() }
            }
        case .agenda:
            VStack(alignment: .leading, spacing: Space.x2) {
                EditorialSectionHeader(index: number(of: section, in: briefing), title: "The day")
                if briefing.agenda.isEmpty {
                    Text("Nothing scheduled").font(LifeOSType.secondary).foregroundStyle(quiet)
                }
                ForEach(briefing.agenda) { event in
                    AgendaRow(event: event) { onTapEvent(event) }
                }
                Button("Add") { onAddEvent(model.date) }
                    .buttonStyle(.editorial(.secondary, size: .compact))
            }
        case .checklist:
            VStack(alignment: .leading, spacing: Space.x2) {
                EditorialSectionHeader(index: number(of: section, in: briefing), title: "Checklist") {
                    if !briefing.checklist.isEmpty {
                        Text("\(briefing.checklistDone) of \(briefing.checklist.count)")
                            .font(LifeOSType.label).monospacedDigit().foregroundStyle(quiet)
                    }
                }
                if briefing.checklist.isEmpty {
                    Text(briefing.placement.isEditable ? "Nothing planned. Add a task below." : "Nothing was listed.")
                        .font(LifeOSType.secondary).foregroundStyle(quiet)
                }
                ChecklistRows(rows: briefing.checklist, onTick: { model.tick($0) }, onOpen: open)
                if briefing.placement.isEditable {
                    HairlineField(text: $newTask, placeholder: "Add a task", glyph: "plus", submitLabel: .done,
                                  onSubmit: {
                                      // The text stays if the write failed, so nothing typed is lost.
                                      if model.add(newTask) { newTask = "" }
                                  })
                }
            }
        case .readings:
            if let readings = briefing.readings {
                VStack(alignment: .leading, spacing: Space.x2) {
                    EditorialSectionHeader(index: number(of: section, in: briefing), title: "Readings")
                    ReadingsRows(readings: readings, workouts: briefing.workouts)
                }
            }
        case .money:
            if let spend = briefing.spend {
                VStack(alignment: .leading, spacing: Space.x2) {
                    EditorialSectionHeader(index: number(of: section, in: briefing), title: "Money")
                    SpendRows(spend: spend)
                }
            }
        case .project:
            if let project = briefing.project {
                VStack(alignment: .leading, spacing: Space.x2) {
                    EditorialSectionHeader(index: number(of: section, in: briefing), title: "Project") {
                        if case .card(let card, _) = project {
                            Button(card.repo) { openURL(card.repoURL) }
                                .buttonStyle(.plain).font(LifeOSType.label).foregroundStyle(quiet)
                        }
                    }
                    ProjectRows(state: project, onOpen: { openURL($0) }, onReconnect: { shellProfile?.open() })
                }
            }
        case .nudges:
            VStack(alignment: .leading, spacing: Space.x2) {
                EditorialSectionHeader(index: number(of: section, in: briefing), title: "From LIFO")
                NudgeRows(nudges: briefing.nudges)
            }
        }
    }

    private func open(_ row: ChecklistRow) {
        switch row.source {
        case .journal:
            openPage = model.journalPageID()
        case .page(let documentID, _):
            openPage = documentID
        case .habit:
            onOpenHabits()
        }
    }
}

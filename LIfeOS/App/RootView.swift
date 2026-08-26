import SwiftUI
import SwiftData
import DesignSystem
import Persistence
import Insights
import Integrations
import OSLog

private let rootLog = Logger(subsystem: "com.shivvyas.lifeos", category: "root")

/// `NoteSync` lives in `Integrations`, which knows nothing about the notes
/// tab's view models. This is the one line that joins them.
extension NoteSync: NoteSyncing {}

/// Composition root for the tab hierarchy: owns every feature's view model,
/// hands each one the model context, and reloads them when the store changes.
/// Views below this point never touch SwiftData.
///
/// Four tabs, not six. Health absorbs activity, weight, recovery and wellness so
/// the bar stays free for the other life domains, and Settings sits behind a
/// gear on Today rather than spending a slot.
///
/// Two shells over one set of screens. A phone gets the bar floating over the
/// content along the bottom, with the actions in the corner; a wide pane gets a
/// left rail that takes its space out of the width and absorbs those same
/// actions into its foot. The screens themselves are identical in both.
struct RootView: View {
    @Bindable var whoop: WhoopConnectionViewModel
    @Bindable var health: HealthConnectionViewModel
    var onSignOut: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    /// The one place the platform's size class is read. `LayoutMetrics` is
    /// expressed over our own `LayoutWidth` so the design system keeps building
    /// for macOS and `swift test` keeps running without a simulator.
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var metrics: LayoutMetrics {
        .metrics(for: sizeClass == .regular ? .regular : .compact)
    }

    @State private var today = TodayViewModel()
    @State private var weight = BodyViewModel()
    @State private var activity = ActivityViewModel()
    @State private var recovery = RecoveryViewModel()
    @State private var wellness = WellnessViewModel()
    @State private var money = MoneyViewModel()
    @State private var plaid = PlaidConnectionViewModel()
    @State private var plan = PlanViewModel()
    @State private var notes = NotesViewModel()
    @State private var life = LifeBoardViewModel()
    @State private var settings = SettingsViewModel()
    @State private var quickLog = QuickLogViewModel()
    @State private var coach = CoachViewModel()
    // Unlike the other view models, `AssistantViewModel` takes its
    // `ModelContext` in `init`, so it cannot be default-constructed before
    // the environment context is available; it is created once in
    // `attachAll()` instead of at property declaration.
    @State private var assistantModel: AssistantViewModel?
    // Calendar sync is owned here so one pass serves Today's agenda, the
    // day sheet, and the assistant alike; every trigger funnels through
    // `syncCalendar()`. Built in `attachAll()` because it needs the context.
    @State private var eventKitSource: EventKitSource?
    @State private var calendarSync: CalendarSync?
    /// Built in `attachAll()` because it needs the context and a live access
    /// token. Nil for a guest, which is not an error: notes are local first and
    /// a signed-out person simply never pushes.
    @State private var noteSync: NoteSync?

    @State private var healthSection = HealthSection.health
    @State private var healthDate = Date()
    @State private var showQuickLog = false
    @State private var showSettings = false
    @State private var showAddPlan = false
    @State private var showAddMoney = false
    @State private var showBudgets = false
    @State private var showJournal = false
    @State private var showCoach = false
    @State private var showAssistant = false
    @State private var showWhoop = false
    @State private var eventSheet: EventSheetPresentation?

    /// Wide panes only. The rail floats over the content rather than taking
    /// layout room from it, so on an iPad in landscape it sits on top of the
    /// thing being read or written. It withdraws while the pane is being worked
    /// with and comes back when that stops.
    ///
    /// Compact width never hides it: the bar lies along the bottom there, where
    /// it overlaps nothing that is being read.
    @State private var isRailVisible = true
    @State private var railReturnTask: Task<Void, Never>?

    /// The tab bar's selection, stated rather than inferred from ordering.
    /// Deliberately not persisted: the requirement is that a cold launch lands
    /// on Today, and non-persisted `@State` delivers exactly that. Selection
    /// still survives backgrounding, because the scene stays alive.
    private enum AppTab: Hashable { case today, health, money, notes, life }

    @State private var tab: AppTab = .today

    var body: some View {
        Group {
            if sizeClass == .regular {
                wideShell
            } else {
                compactShell
            }
        }
        // `today.detail` is the only source of truth for what the sheet shows;
        // there is deliberately no parallel `selectedDay` state to keep in step.
        .sheet(item: Binding(
            get: { today.detail },
            set: { if $0 == nil { today.clearSelection() } }
        )) { detail in
            DayDetailSheet(snapshot: detail) { today.toggleHabit(id: $0) }
        }
        .sheet(isPresented: $showQuickLog) {
            QuickLogSheet(model: quickLog)
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsScreen(model: settings, whoop: whoop, health: health, plaid: plaid, onSignOut: onSignOut)
        }
        .fullScreenCover(isPresented: $showCoach) {
            LifoCoachScreen(model: coach, onDismiss: { showCoach = false })
        }
        .sheet(isPresented: $showAssistant) {
            if let assistantModel {
                AssistantSheet(model: assistantModel)
            }
        }
        .sheet(isPresented: $showAddPlan) {
            AddPlanEntrySheet(
                prompt: plan.section.addPrompt,
                allowsTarget: plan.section == .goals,
                allowsDueDate: plan.section == .content
            ) { title, detail, target, dueDate in
                plan.add(title: title, detail: detail, target: target, dueDate: dueDate)
            }
        }
        .sheet(isPresented: $showJournal) {
            JournalEntrySheet { text in wellness.addJournal(text) }
        }
        .sheet(isPresented: $showAddMoney) {
            AddMoneySheet { merchant, amount, isIncome, category in
                money.add(merchant: merchant, amount: amount, isIncome: isIncome, category: category)
            }
        }
        .sheet(isPresented: $showBudgets, onDismiss: { money.load(connection: plaid) }) {
            BucketEditorSheet(model: money)
        }
        .sheet(item: $eventSheet) { mode in
            EventSheet(
                mode: mode,
                onSave: { draft in
                    guard let calendarSync else { return }
                    switch mode {
                    case .create:
                        Task { try? await calendarSync.create(draft) }
                    case .edit(let event):
                        Task { try? await calendarSync.update(id: event.id, with: draft) }
                    }
                },
                onDelete: {
                    guard let calendarSync, case .edit(let event) = mode else { return }
                    Task { try? await calendarSync.delete(id: event.id) }
                }
            )
        }
        .environment(\.layout, metrics)
        .environment(\.noteSync, noteSync)
        // Typing is the other way of working with the pane, and the one where
        // the rail is most in the way: on a landscape iPad the keyboard takes
        // half the height and the note being written is what is left.
        .task {
            for await _ in NotificationCenter.default.notifications(
                named: UIResponder.keyboardWillShowNotification
            ) {
                guard metrics.isRegular else { continue }
                withdrawRail()
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(
                named: UIResponder.keyboardWillHideNotification
            ) {
                showRail()
            }
        }
        // A tab change is navigation, not content work, so the rail is wanted.
        .onChange(of: tab) { _, _ in showRail() }
        .task {
            attachAll()
            reloadAll()
            syncCalendar()
        }
        // Event-driven, not polled: a save is the only thing that can change
        // what these screens show while the app is running.
        .task {
            for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
                reloadAll()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                reloadAll()
                syncCalendar()
            }
        }

    }

    /// Phone: the bar floats over the content, and the actions keep the corner.
    private var compactShell: some View {
        ZStack(alignment: .bottomTrailing) {
            content

            PillNavBar(selection: $tab, items: navItems)
                .frame(maxWidth: .infinity)          // centers the pill
                .padding(.bottom, 12)

            VStack(spacing: 14) {
                assistantButton
                coachButton
                quickLogButton
            }
            .padding(.trailing, metrics.gutter)
            .padding(.bottom, metrics.fabBottomInset)

            whoopModal
        }
    }

    /// Wide pane: the bar stands on end against the left edge, and the actions
    /// keep the bottom corner they hold on a phone.
    ///
    /// Both are overlays, so a screen's canvas runs the full width underneath
    /// them and there is no bare strip down the side. Overlays claim no layout
    /// room, though, so the rail's clearance is `railInset`, which the screens
    /// apply themselves. Nothing is reserved for the actions: they float over
    /// the content here exactly as they do on a phone.
    private var wideShell: some View {
        ZStack {
            content
                // Scrolling or dragging anywhere in the pane counts as working
                // with the content, so the rail steps aside. Simultaneous, not
                // exclusive: it observes the touch rather than claiming it, so
                // scroll views, text selection and Pencil strokes all still see
                // it. Minimum distance keeps a plain tap from tripping it.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { _ in withdrawRail() }
                        .onEnded { _ in scheduleRailReturn() }
                )
                .overlay(alignment: .leading) {
                    PillNavBar(selection: $tab, items: navItems, axis: .vertical)
                        .padding(.leading, metrics.gutter)
                        .opacity(isRailVisible ? 1 : 0)
                        // Slid out rather than only faded, so the eye reads it
                        // as parked off the edge and knows where it went.
                        .offset(x: isRailVisible ? 0 : -(metrics.gutter + 76))
                        .allowsHitTesting(isRailVisible)
                        .animation(.easeInOut(duration: 0.22), value: isRailVisible)
                }
                // The strip the rail parks behind. Bringing it back has to be
                // possible without first scrolling something, or a person who
                // hid it on a full-screen page has no way back to the tabs.
                .overlay(alignment: .leading) {
                    if !isRailVisible {
                        Color.clear
                            .frame(width: 28)
                            .frame(maxHeight: .infinity)
                            .contentShape(.rect)
                            .onTapGesture { showRail() }
                            .accessibilityLabel("Show navigation")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { showRail() }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    VStack(spacing: 14) {
                        assistantButton
                        coachButton
                        quickLogButton
                    }
                    .padding(.trailing, metrics.gutter)
                    .padding(.bottom, metrics.fabBottomInset)
                }

            whoopModal
        }
    }

    private var navItems: [PillNavItem<AppTab>] {
        [
            PillNavItem(value: AppTab.today, systemImage: "circle.grid.3x3.fill", label: "Today"),
            PillNavItem(value: AppTab.health, systemImage: "heart.fill", label: "Health"),
            PillNavItem(value: AppTab.money, systemImage: "dollarsign", label: "Money"),
            PillNavItem(value: AppTab.notes, systemImage: "text.book.closed.fill", label: "Notes"),
            PillNavItem(value: AppTab.life, systemImage: "square.grid.3x3.fill", label: "Life"),
        ]
    }

    @ViewBuilder
    private var whoopModal: some View {
        if showWhoop {
            WhoopConnectModal(model: whoop) { showWhoop = false }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var content: some View {
        Group {
            switch tab {
            case .today:
                NavigationStack {
                    TodayScreen(
                        snapshot: today.snapshot,
                        onSelectDay: { today.select($0) },
                        onConnectCalendar: { requestCalendarAccess() },
                        onAddEvent: { eventSheet = .create },
                        onTapEvent: { eventSheet = .edit($0) },
                        onOpenToday: { today.select(.now) }
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { showSettings = true } label: {
                                Image(systemName: "gearshape.fill")
                            }
                            .tint(LifeOSTokens.primaryText.resolve(scheme))
                            .accessibilityLabel("Settings")
                        }
                    }
                }
            case .health:
                NavigationStack {
                    HealthHubScreen(
                        activity: activity.snapshot,
                        weight: weight.snapshot,
                        recovery: recovery.snapshot,
                        wellness: wellness.snapshot,
                        onAddJournal: { showJournal = true },
                        onConnectWhoop: { showWhoop = true },
                        section: $healthSection,
                        selectedDate: Binding(
                            get: { healthDate },
                            set: { healthDate = $0; selectHealthDate($0) }
                        )
                    )
                }
            case .money:
                MoneyScreen(
                    snapshot: money.snapshot,
                    onAdd: { showAddMoney = true },
                    onConnect: { plaid.connect() },
                    onSync: { Task { await plaid.sync(); money.load(connection: plaid) } },
                    onEditBudgets: { showBudgets = true }
                )
            case .notes:
                NotesHubScreen(
                    model: notes,
                    plan: plan,
                    onAddHabit: {
                        // The add sheet reads `plan.section` to know what it is
                        // adding, and habits are the only section left that
                        // still lives here.
                        plan.section = .habits
                        showAddPlan = true
                    }
                )
            case .life:
                // `LifeSector.ownsTab` in the Sectors package is the one
                // decision about which three sectors get this row at all;
                // `LifeBoardScreen` only ever calls this closure for those
                // three. `default` below is reachable only if this switch
                // has drifted out of sync with that decision, which should
                // fail loudly rather than swallow the tap.
                LifeBoardScreen(model: life) { sector in
                    switch sector {
                    case .body: tab = .health
                    case .money: tab = .money
                    case .mission: tab = .notes
                    default:
                        assertionFailure("RootView has no tab mapped for \(sector)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var coachButton: some View {
        Button {
            showCoach = true
        } label: {
            Image(systemName: "message.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .frame(width: 52, height: 52)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Circle().strokeBorder(
                                Color.white.opacity(scheme == .dark ? 0.2 : 0.55),
                                lineWidth: 1
                            )
                        }
                        .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.16),
                                radius: 10, y: 4)
                )
        }
        .accessibilityLabel("LIFO")
    }

    private var assistantButton: some View {
        Button {
            showAssistant = true
        } label: {
            Image(systemName: "calendar")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .frame(width: 52, height: 52)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Circle().strokeBorder(
                                Color.white.opacity(scheme == .dark ? 0.2 : 0.55),
                                lineWidth: 1
                            )
                        }
                        .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.16),
                                radius: 10, y: 4)
                )
        }
        .accessibilityLabel("Calendar assistant")
    }

    private var quickLogButton: some View {
        Button {
            showQuickLog = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(LifeOSTokens.fabGlyph.resolve(scheme))
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(LifeOSTokens.fabFill.resolve(scheme))
                        .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.2),
                                radius: 10, y: 4)
                )
        }
        .accessibilityLabel("Quick log")
    }

    private func selectHealthDate(_ date: Date) {
        activity.select(date)
        weight.select(date)
        recovery.select(date)
        wellness.select(date)
    }

    /// Parks the rail off the leading edge. Cancels any pending return so a
    /// long scroll does not have it reappear mid-gesture.
    private func withdrawRail() {
        railReturnTask?.cancel()
        railReturnTask = nil
        guard isRailVisible else { return }
        isRailVisible = false
    }

    /// Brings it back a beat after the interaction ends. The delay is what
    /// stops it flickering between the flicks of a fast scroll.
    private func scheduleRailReturn() {
        railReturnTask?.cancel()
        railReturnTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            isRailVisible = true
        }
    }

    private func showRail() {
        railReturnTask?.cancel()
        railReturnTask = nil
        isRailVisible = true
    }

    private func attachAll() {
        today.attach(context)
        weight.attach(context)
        activity.attach(context)
        recovery.attach(context)
        wellness.attach(context)
        money.attach(context)
        plaid.attach(context)
        plan.attach(context)
        life.attach(context)

        // Notes sync straight to Supabase, unlike the rest of the app, which
        // is still local only. The token is read from the keychain per pass
        // rather than captured: `AppShell` refreshes the session on launch and
        // on every return to the foreground, so a captured token would be the
        // stale one within the hour.
        if noteSync == nil,
           let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey {
            let sessions = KeychainAuthSessionStore()
            noteSync = NoteSync(
                context: context,
                rest: SupabaseREST(baseURL: url, anonKey: key),
                accessToken: { sessions.load()?.accessToken }
            )
        }
        notes.attach(context, sync: noteSync)

        // One-time, and idempotent through the origin id on each page rather
        // than through a flag, so a second device does not produce a second
        // copy of everything the first one migrated.
        do {
            try PlanNoteMigration.seedIfEmpty(context: context)
            try PlanNoteMigration.run(context: context)
        } catch {
            rootLog.error("note migration failed: \(String(describing: error), privacy: .public)")
        }
        settings.attach(context)
        quickLog.attach(context)
        coach.attach(context)

        // Direct capture, not weak: `money` and `life` are RootView's own
        // `@State` view models, so they outlive `coach` for as long as
        // `coach` itself does, and neither holds a reference back to the
        // coach that would make this a cycle.
        coach.bundleExtras = { [money, life] in
            let snapshot = money.snapshot
            return (
                money: snapshot.isConnected
                    ? ContextBundle.Money(
                        income: snapshot.income,
                        expenses: snapshot.expenses,
                        savingsRate: snapshot.savingsRate,
                        netWorth: snapshot.netWorth,
                        recent: snapshot.recent.prefix(30).map {
                            ContextBundle.Money.Transaction(
                                merchant: $0.merchant, category: $0.category,
                                amount: $0.amount, date: $0.date)
                        })
                    : nil,
                sectors: life.cards.map { card in
                    // Newest-last history: the delta is simply the latest
                    // month's score minus the one before it.
                    let delta: Int? = {
                        guard card.history.count >= 2,
                              let last = card.history[card.history.count - 1].value,
                              let previous = card.history[card.history.count - 2].value
                        else { return nil }
                        return Int(last - previous)
                    }()
                    return ContextBundle.Sector(name: card.sector.title, score: card.score, delta: delta)
                },
                firstName: nil
            )
        }

        if assistantModel == nil {
            assistantModel = AssistantViewModel(context: context)
        }
        if calendarSync == nil {
            let source = EventKitSource()
            eventKitSource = source
            calendarSync = CalendarSync(
                sources: [source],
                store: CalendarStore(context: context)
            )
        }
    }

    private func reloadAll() {
        today.load()
        weight.load()
        activity.load()
        recovery.load()
        wellness.load()
        money.load(connection: plaid)
        Task {
            await plaid.syncIfDue()
            money.load(connection: plaid)
        }
        plan.load()
        notes.load()
        life.load()
        settings.load()
    }

    /// Ambient: fires on scene activation and after any calendar write. The
    /// pass saves through the store, `ModelContext.didSave` fires, and
    /// `reloadAll()` refreshes every snapshot; nothing polls.
    private func syncCalendar() {
        guard CalendarAccessState.current == .authorized, let calendarSync else { return }
        Task { await calendarSync.sync() }
    }

    /// The one place the EventKit prompt is allowed to originate.
    private func requestCalendarAccess() {
        guard let eventKitSource else { return }
        Task {
            _ = try? await eventKitSource.requestAccess()
            syncCalendar()
        }
    }
}

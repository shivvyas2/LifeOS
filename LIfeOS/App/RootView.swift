import SwiftUI
import AppSurfaces
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
/// content along the bottom; a wide pane gets a left rail that takes its space
/// out of the width. The screens themselves are identical in both, and the
/// actions sit across the top of every one of them rather than in either
/// shell's corner.
struct RootView: View {
    let integrations: IntegrationContainer
    var onSignOut: () -> Void = {}
    
    // Convenience accessors (keeps existing code working)
    private var whoop: WhoopConnectionViewModel { integrations.whoop }
    private var fitbit: FitbitConnectionViewModel { integrations.fitbit }
    private var plaid: PlaidConnectionViewModel { integrations.plaid }
    private var health: HealthConnectionViewModel { integrations.health }

    @Environment(\.accountSession) private var accountSession
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
    @State private var recorder = ActivityRecorder()
    @State private var library = WorkoutLibraryViewModel()
    @State private var showActivity = false
    private var activityScreen: some View {
        BeginActivityScreen(model: recorder, onQuickLog: { quickLogAfterActivity = true }, library: library)
    }
    private func afterActivity() {
        if quickLogAfterActivity { quickLogAfterActivity = false; showQuickLog = true }
    }
    @State private var showNotifications = false
    @State private var coachAfterDismiss = false
    @State private var quickLogAfterActivity = false
    @State private var recovery = RecoveryViewModel()
    @State private var wellness = WellnessViewModel()
    @State private var money = MoneyViewModel()
    @State private var moneyDetail = MoneyDetailViewModel()
    @State private var openMoney: MoneyDetailFilter?
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
    /// Re-read when the cover closes, so a photo changed in there shows on the
    /// button straight away rather than after a relaunch.
    @State private var profilePhoto: Data? = ProfilePhotoStore.load()
    @State private var showAddPlan = false
    @State private var showAddMoney = false
    /// The metric whose page is open, pushed on Today's own stack. A value
    /// rather than four booleans, so the destination is a function of it.
    @State private var openMetric: TodayMetric?
    @State private var metricDetail = MetricDetailViewModel()
    @State private var showBudgets = false
    @State private var showJournal = false
    @State private var showCoach = false
    @State private var showAssistant = false
    @State private var showWhoop = false
    @State private var showMonth = false
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
        // A sheet on an iPad is a centered card, and the live session and
        // the video it pushes would be stuck inside it. Regular width gets
        // the cover Settings and the Coach already use.
        .sheet(isPresented: Binding(get: { showActivity && sizeClass != .regular }, set: { showActivity = $0 }),
               onDismiss: afterActivity) { activityScreen }
        .fullScreenCover(isPresented: Binding(get: { showActivity && sizeClass == .regular }, set: { showActivity = $0 }),
                         onDismiss: afterActivity) { activityScreen }
        .sheet(isPresented: $showNotifications, onDismiss: presentDeferredCoach) {
            NavigationStack {
                NotificationInboxScreen().toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { showNotifications = false } }
                }
            }
        }
        .sheet(isPresented: $showQuickLog) {
            QuickLogSheet(model: quickLog)
        }
        .onDisappear {
            health.stopWatching()
            coach.disappear()
            coach.stopSpeaking()
        }
        .task(id: "\(health.state)|\(whoop.state)|\(fitbit.state)") {
            await publishWellnessIfShared()
        }
        .onChange(of: showSettings) { _, isOpen in
            if !isOpen { profilePhoto = ProfilePhotoStore.load() }
        }
        .fullScreenCover(isPresented: $showSettings, onDismiss: presentDeferredCoach) {
            ProfileScreen(
                settings: settings, whoop: whoop, fitbit: fitbit, health: health, plaid: plaid,
                stats: profileStats, highlights: profileHighlights,
                allTime: profileAllTime, socialActivity: socialActivity, onSignOut: onSignOut
            )
        }
        .fullScreenCover(isPresented: $showCoach) {
            LifoCoachScreen(model: coach, onDismiss: { showCoach = false })
        }
        // A full screen, not a sheet: the assistant is a place to work in,
        // with a calendar behind its Schedule link, and a bottom sheet left
        // it feeling like a quick errand over the tab underneath.
        .fullScreenCover(isPresented: $showAssistant) {
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
        // Injected rather than passed: Notes and Life own their own
        // navigation stacks several levels down, and a toolbar has to be
        // attached inside the stack it belongs to.
        .environment(\.quickActions, quickActions)
        .environment(\.shellProfile, ShellProfile(photo: profilePhoto, open: { showSettings = true }))
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
        .onChange(of: tab) { _, selected in
            showRail()
            // Life loads when its tab comes up, not on every save elsewhere
            // (see `reloadAll`).
            if selected == .life { life.load() }
        }
        .task {
            attachAll()
            reloadAll()
            syncCalendar()
            await PushService.shared.refreshInbox()
            await PushService.shared.syncRegistration()
            openSurfaceRoute()
            openNudge(PushService.shared.pending)
            // Foreground only: the watch is what keeps a step count on screen
            // climbing, and it is stopped again below when the app goes away.
            health.startWatching()
        }
        // The nudge from a tapped notification, opened as the first turn of a
        // conversation rather than shown and dismissed.
        .onChange(of: SurfaceCoordinator.shared.pendingRoute) { _, _ in openSurfaceRoute() }
        .onChange(of: PushService.shared.pending) { _, nudge in
            openNudge(nudge)
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
                // Re-pushed on every foreground, not only after sign in. The
                // row carries the timezone the send hour is read in, so
                // somebody who has flown somewhere would otherwise keep being
                // nudged at eight in the morning where they used to live.
                Task { await PushService.shared.syncRegistration(); await PushService.shared.refreshInbox() }
                // A notification tapped from a cold launch lands in the inbox
                // before this view exists, so onChange never fires for it.
                openNudge(PushService.shared.pending)
                health.startWatching()
            } else {
                health.stopWatching()
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
                // Stay put when the keyboard opens, and let it cover them.
                //
                // Without this the whole stack is lifted by the keyboard's
                // safe area, so the bar and the buttons ride up and sit on top
                // of the note being written. On a phone that is the worst
                // possible place for them: the keyboard already takes half the
                // screen, and the strip left over is the part someone is
                // actually looking at. Neither control is reachable while
                // typing anyway, so hiding behind the keyboard costs nothing
                // and hands the space back.
                .ignoresSafeArea(.keyboard, edges: .bottom)

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

            whoopModal
        }
    }

    private var navItems: [PillNavItem<AppTab>] {
        [
            PillNavItem(value: AppTab.today, systemImage: "sun.max.fill", label: "Today"),
            PillNavItem(value: AppTab.health, systemImage: "heart.fill", label: "Health"),
            PillNavItem(value: AppTab.money, systemImage: "dollarsign", label: "Money"),
            PillNavItem(value: AppTab.notes, systemImage: "text.book.closed.fill", label: "Notes"),
            PillNavItem(value: AppTab.life, systemImage: "square.grid.2x2.fill", label: "Life"),
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
                        onAddEvent: { eventSheet = .create(on: nil) },
                        onTapEvent: { eventSheet = .edit($0) },
                        onOpenToday: { today.select(.now) },
                        onConnectHealth: { Task { await health.connect() } },
                        isHealthConnected: health.isConnected,
                        onSelectMetric: { openMetric = $0 }
                    )
                    // Applied before the bar items below, so the actions sit
                    // inboard of the avatar rather than being pushed past it:
                    // toolbar items appear in the order their modifiers run.
                    .shellToolbar()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { showMonth = true } label: {
                                Image(systemName: "calendar")
                            }
                            .accessibilityLabel("Calendar")
                        }
                    }
                    .navigationDestination(isPresented: $showMonth) {
                        CalendarScreen(
                            assistant: assistantModel,
                            onTapEvent: { eventSheet = .edit($0) },
                            onAddEvent: { eventSheet = .create(on: $0) },
                            isCalendarConnected: today.snapshot.calendarAccess == .authorized,
                            onConnectCalendar: { requestCalendarAccess() }
                        )
                    }
                    // Pushed on Today's stack rather than presented as a sheet:
                    // it is a place inside the day's numbers, not an errand
                    // that interrupts them, and a push keeps the way back.
                    .navigationDestination(item: $openMetric) { metric in
                        MetricDetailScreen(metric: metric, model: metricDetail, onManageConnections: { showSettings = true })
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
                        isWhoopConnected: whoop.isConnected,
                        onSelectMetric: { openMetric = $0 },
                        library: library,
                        recorder: recorder,
                        section: $healthSection,
                        selectedDate: Binding(
                            get: { healthDate },
                            set: { healthDate = $0; selectHealthDate($0) }
                        )
                    )
                    .shellToolbar()
                    .navigationDestination(item: $openMetric) { metric in
                        MetricDetailScreen(metric: metric, model: metricDetail, onManageConnections: { showSettings = true })
                    }
                }
            case .money:
                // Wrapped here rather than in `MoneyScreen`: the stack carries
                // the bar the actions live in and the detail page a category
                // or merchant opens onto.
                NavigationStack {
                    MoneyScreen(
                        snapshot: money.snapshot,
                        onAdd: { showAddMoney = true },
                        onConnect: { plaid.connect() },
                        onSync: { Task { await plaid.sync(); money.load(connection: plaid) } },
                        onEditBudgets: { showBudgets = true },
                        onOpen: { openMoney = $0 }
                    )
                    .shellToolbar()
                    .navigationDestination(item: $openMoney) { filter in
                        MoneyDetailScreen(filter: filter, model: moneyDetail)
                    }
                }
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

    /// The three actions, defined once and injected into the environment so
    /// every tab draws the same set across the top of its own bar.
    ///
    /// They used to be laid flat on home and collapsed into a bottom-corner
    /// fan everywhere else, which put the control people reach for most in a
    /// different place depending on which tab they were on, and hid it behind
    /// a trigger on four of the five. One place, always open.
    ///
    /// The plus starts or resumes an activity; Quick Log remains inside that screen.
    private var quickActions: [QuickAction] {
        [
            // Not a bare `calendar`: the month button in Today's top bar is
            // already that glyph, and on home the two now sit in the same bar.
            QuickAction(id: "assistant", systemImage: "calendar.badge.clock", label: "Calendar assistant") {
                showAssistant = true
            },
            QuickAction(id: "coach", systemImage: "message.fill", label: "LIFO", shortLabel: "LIFO") {
                showCoach = true
            },
            QuickAction(id: "beginActivity", systemImage: recorder.hasSession ? "timer" : "plus", label: recorder.hasSession ? "Current activity" : "Begin activity", isProminent: true, shortLabel: recorder.hasSession ? "Live" : "Start") {
                showActivity = true
            },
        ]
    }

    /// Opens LIFO on a nudge and clears the inbox.
    ///
    /// The sentence is seeded, the numbers behind it are not: a phone that has
    /// been offline for days would otherwise open on figures two days stale.
    /// Whatever the conversation goes on to say is worked out here, now,
    /// against the store as it currently stands.
    private func openNudge(_ nudge: NudgePayload?) {
        guard let nudge else { return }
        PushService.shared.pending = nil
        coach.seed(nudge.text)
        if showSettings || showNotifications {
            coachAfterDismiss = true; showSettings = false; showNotifications = false
        } else { showCoach = true }
    }
    private func presentDeferredCoach() {
        if coachAfterDismiss { coachAfterDismiss = false; showCoach = true }
    }
    private func openSurfaceRoute() {
        guard let route = SurfaceCoordinator.shared.pendingRoute else { return }
        SurfaceCoordinator.shared.pendingRoute = nil
        switch route {
        case .today: tab = .today
        case .health: tab = .health; selectHealthDate(.now)
        case .activity: showActivity = true
        case .notifications: showNotifications = true
        // Placeholder until the day screen lands in this branch's Task 8.
        case .day: tab = .today
        }
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

    /// What the profile shows under the name.
    ///
    /// Three, because a row of four on a narrow phone squeezes each column
    /// past the point the figures are readable, and because these are the
    /// three the app can state without qualification.
    @MainActor private func publishWellnessIfShared() async {
        guard let api = SocialSession.api, let session = SocialSession.current else { return }
        do {
            let groups = try await api.groups(token: session.accessToken)
            guard !Task.isCancelled, SocialSession.current?.userID == session.userID,
                  groups.contains(where: { $0.members.contains(where: { $0.sharesWellness == true }) }),
                  let activity = socialActivity else { return }
            try await api.publish(activity, token: session.accessToken)
        } catch {
            // Foreground/social refresh retries. Never interrupt the home screen
            // or expose private score values in logs for a background sync failure.
        }
    }

    private var socialActivity: SocialActivitySnapshot? {
        guard let days = try? context.fetchCount(FetchDescriptor<DailyMetrics>()),
              let workouts = try? context.fetchCount(FetchDescriptor<WorkoutRecord>()) else { return nil }
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Calendar.current.startOfDay(for: .now))!
        guard let rows = try? context.fetch(FetchDescriptor<DailyMetrics>(predicate: #Predicate { $0.date >= cutoff })) else { return nil }
        let goals = (try? context.fetch(FetchDescriptor<UserGoals>()))?.first
        let wellness = SocialWellness.scores(readings: rows.map(WellnessReading.init),
            exerciseGoal: goals?.exerciseMinutesGoal ?? 30, sleepGoal: goals?.sleepMinutesGoal ?? 420)
        return SocialActivitySnapshot(streak: today.snapshot.streak, daysTracked: days, workouts: workouts, wellness: wellness)
    }

    private var profileStats: [ProfileStat] {
        // Cumulative, not daily: the trio under the name is who this person
        // has been, the way the reference's followers number is. Counts come
        // straight from the store so they are real however the day is going.
        let daysTracked = (try? context.fetchCount(FetchDescriptor<DailyMetrics>())) ?? 0
        let workouts = (try? context.fetchCount(FetchDescriptor<WorkoutRecord>())) ?? 0
        return [
            ProfileStat("Day streak", "\(today.snapshot.streak)"),
            ProfileStat("Days tracked", "\(daysTracked)"),
            ProfileStat("Workouts", "\(workouts)"),
        ]
    }

    /// Today's living numbers for the profile's glass panel. Only what is
    /// actually known: a missing reading is left out rather than dashed, so
    /// the panel always reads as facts. Money is deliberately absent; the
    /// sample-data default would put invented dollars on a person's face.
    private var profileHighlights: [ProfileStat] {
        var highlights: [ProfileStat] = []
        if let steps = today.snapshot.steps {
            highlights.append(ProfileStat("Steps", steps.formatted()))
        }
        if let sleep = today.snapshot.sleepMinutes {
            highlights.append(ProfileStat("Sleep", TodayScreen.duration(sleep)))
        }
        if let recovery = today.snapshot.recoveryPct {
            highlights.append(ProfileStat("Recovery", "\(Int(recovery))%"))
        }
        if let weight = today.snapshot.weightKg {
            highlights.append(ProfileStat("Weight", String(format: "%.1f kg", weight)))
        }
        if !today.snapshot.agenda.isEmpty {
            highlights.append(ProfileStat("Events today", "\(today.snapshot.agenda.count)"))
        }
        return highlights
    }

    /// What all the tracking adds up to. Sums come from one fetch of the
    /// daily rows, which is a few hundred small objects at most; the counts
    /// are `fetchCount`, which never materialises anything. Zero-valued
    /// figures are left out so the panel only ever states facts.
    private var profileAllTime: [ProfileStat] {
        var figures: [ProfileStat] = []

        let rows = (try? context.fetch(FetchDescriptor<DailyMetrics>())) ?? []
        let steps = rows.compactMap(\.steps).reduce(0, +)
        if steps > 0 {
            figures.append(ProfileStat(
                "Steps taken",
                steps.formatted(.number.notation(.compactName).precision(.significantDigits(3)))
            ))
        }
        let sleepHours = rows.compactMap(\.sleepMinutes).reduce(0, +) / 60
        if sleepHours > 0 {
            figures.append(ProfileStat("Sleep logged", "\(sleepHours)h"))
        }

        let habitTicks = (try? context.fetchCount(FetchDescriptor<HabitTick>())) ?? 0
        if habitTicks > 0 {
            figures.append(ProfileStat("Habits done", "\(habitTicks)"))
        }
        let events = (try? context.fetchCount(FetchDescriptor<CalendarEvent>())) ?? 0
        if events > 0 {
            figures.append(ProfileStat("Events", "\(events)"))
        }
        let scored = life.cards.count { $0.score != nil }
        if scored > 0 {
            figures.append(ProfileStat("Sectors scored", "\(scored)"))
        }
        return figures
    }

    private func attachAll() {
        today.attach(context)
        metricDetail.attach(context)
        weight.attach(context)
        activity.attach(context)
        recorder.attach(context)
        library.attach(context)
        recorder.whoopConnected = { [whoop] in whoop.isConnected }
        accountSession?.beforeAccountChange = { [recorder] in recorder.deactivate() }
        recorder.onSaved = {
            reloadAll()
            Task { await health.syncIfConnected(); reloadAll() }
        }
        recovery.attach(context)
        wellness.attach(context)
        money.attach(context)
        moneyDetail.attach(context)
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
            try NoteIndexMigration.run(context: context)
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

    /// Only while its page is up. Off screen it is six months of rows nobody
    /// is looking at, run on every save in the app.
    private func reloadMoneyDetail() {
        guard let openMoney else { return }
        moneyDetail.load(openMoney)
    }

    private func reloadAll() {
        SurfaceCoordinator.shared.publish()
        today.load()
        // Only while its page is up. Off screen it is a year of bucketing
        // nobody is looking at, run on every save in the app.
        if let openMetric { metricDetail.load(openMetric) }
        weight.load()
        activity.load()
        recovery.load()
        wellness.load()
        // A finished workout is a split in the rotation, so today's plan is
        // recomputed with everything else rather than at the next launch.
        library.load()
        money.load(connection: plaid)
        reloadMoneyDetail()
        Task {
            await plaid.syncIfDue()
            money.load(connection: plaid)
            reloadMoneyDetail()
        }
        plan.load()
        notes.load()
        // Only while its tab is up. The month in progress is read from every
        // input the app holds, and that is too much to redo on every save
        // for a board nobody is looking at.
        if tab == .life { life.load() }
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

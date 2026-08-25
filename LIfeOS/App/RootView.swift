import SwiftUI
import SwiftData
import DesignSystem

/// Composition root for the tab hierarchy: owns every feature's view model,
/// hands each one the model context, and reloads them when the store changes.
/// Views below this point never touch SwiftData.
///
/// Four tabs, not six. Body absorbs activity, weight, recovery and wellness so
/// the bar stays free for the other life domains, and Settings sits behind a
/// gear on Today rather than spending a slot.
struct RootView: View {
    @Bindable var whoop: WhoopConnectionViewModel

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
    @State private var plan = PlanViewModel()
    @State private var settings = SettingsViewModel()
    @State private var quickLog = QuickLogViewModel()

    @State private var bodySection = BodySection.activity
    @State private var bodyDate = Date()
    @State private var showQuickLog = false
    @State private var showSettings = false
    @State private var showAddPlan = false
    @State private var showAddMoney = false
    @State private var showJournal = false

    /// The tab bar's selection, stated rather than inferred from ordering.
    /// Deliberately not persisted: the requirement is that a cold launch lands
    /// on Today, and non-persisted `@State` delivers exactly that. Selection
    /// still survives backgrounding, because the scene stays alive.
    private enum AppTab: Hashable { case today, body, money, plan }

    @State private var tab: AppTab = .today

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $tab) {
                Tab("Today", systemImage: "circle.grid.3x3.fill", value: AppTab.today) {
                    NavigationStack {
                        TodayScreen(snapshot: today.snapshot, onSelectDay: { today.select($0) })
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button {
                                        showSettings = true
                                    } label: {
                                        Image(systemName: "gearshape.fill")
                                    }
                                    .tint(LifeOSTokens.primaryText.resolve(scheme))
                                    .accessibilityLabel("Settings")
                                }
                            }
                    }
                }
                Tab("Body", systemImage: "figure", value: AppTab.body) {
                    // Body had no stack of its own until Recovery gained a
                    // detail screen to push. Without one the trends link is
                    // inert rather than broken, which is worse.
                    NavigationStack {
                        BodyHubScreen(
                            activity: activity.snapshot,
                            weight: weight.snapshot,
                            recovery: recovery.snapshot,
                            wellness: wellness.snapshot,
                            onAddJournal: { showJournal = true },
                            section: $bodySection,
                            selectedDate: Binding(
                                get: { bodyDate },
                                set: { bodyDate = $0; selectBodyDate($0) }
                            )
                        )
                    }
                }
                Tab("Money", systemImage: "dollarsign.circle.fill", value: AppTab.money) {
                    MoneyScreen(snapshot: money.snapshot) { showAddMoney = true }
                }
                Tab("Plan", systemImage: "checklist", value: AppTab.plan) {
                    PlanScreen(
                        snapshot: plan.snapshot,
                        section: Binding(get: { plan.section }, set: { plan.section = $0 }),
                        onAdd: { showAddPlan = true },
                        onAdvance: { plan.advance(id: $0) },
                        onToggleHabit: { plan.toggleHabit(id: $0) },
                        onDelete: { plan.delete(id: $0) }
                    )
                }
            }
            // A sidebar on iPad, the tab bar on iPhone. One modifier, but it
            // restructures how the four tabs present, so it is verified by
            // screenshot rather than assumed.
            .tabViewStyle(.sidebarAdaptable)

            Button {
                showQuickLog = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(LifeOSTokens.primaryText.resolve(scheme)))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            }
            .padding(.trailing, metrics.gutter)
            .padding(.bottom, metrics.fabBottomInset)
            .accessibilityLabel("Quick log")
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
        .sheet(isPresented: $showSettings) {
            SettingsScreen(model: settings, whoop: whoop)
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
        .environment(\.layout, metrics)
        .task {
            attachAll()
            reloadAll()
        }
        // Event-driven, not polled: a save is the only thing that can change
        // what these screens show while the app is running.
        .task {
            for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
                reloadAll()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reloadAll() }
        }

    }

    private func selectBodyDate(_ date: Date) {
        activity.select(date)
        weight.select(date)
        recovery.select(date)
        wellness.select(date)
    }

    private func attachAll() {
        today.attach(context)
        weight.attach(context)
        activity.attach(context)
        recovery.attach(context)
        wellness.attach(context)
        money.attach(context)
        plan.attach(context)
        settings.attach(context)
        quickLog.attach(context)
    }

    private func reloadAll() {
        today.load()
        weight.load()
        activity.load()
        recovery.load()
        wellness.load()
        money.load()
        plan.load()
        settings.load()
    }
}

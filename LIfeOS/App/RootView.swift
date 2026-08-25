import SwiftUI
import SwiftData
import DesignSystem

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
    @State private var plan = PlanViewModel()
    @State private var settings = SettingsViewModel()
    @State private var quickLog = QuickLogViewModel()
    @State private var coach = CoachViewModel()

    @State private var healthSection = HealthSection.health
    @State private var healthDate = Date()
    @State private var showQuickLog = false
    @State private var showSettings = false
    @State private var showAddPlan = false
    @State private var showAddMoney = false
    @State private var showJournal = false
    @State private var showCoach = false
    @State private var showWhoop = false

    /// The tab bar's selection, stated rather than inferred from ordering.
    /// Deliberately not persisted: the requirement is that a cold launch lands
    /// on Today, and non-persisted `@State` delivers exactly that. Selection
    /// still survives backgrounding, because the scene stays alive.
    private enum AppTab: Hashable { case today, health, money, plan }

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
            SettingsScreen(model: settings, whoop: whoop, onSignOut: onSignOut)
        }
        .fullScreenCover(isPresented: $showCoach) {
            LifoCoachScreen(model: coach, onDismiss: { showCoach = false })
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

    /// Phone: the bar floats over the content, and the actions keep the corner.
    private var compactShell: some View {
        ZStack(alignment: .bottomTrailing) {
            content

            PillNavBar(selection: $tab, items: navItems)
                .frame(maxWidth: .infinity)          // centers the pill
                .padding(.bottom, 12)

            VStack(spacing: 14) {
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
                .overlay(alignment: .leading) {
                    PillNavBar(selection: $tab, items: navItems, axis: .vertical)
                        .padding(.leading, metrics.gutter)
                }
                .overlay(alignment: .bottomTrailing) {
                    VStack(spacing: 14) {
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
            PillNavItem(value: AppTab.plan, systemImage: "checklist", label: "Plan"),
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
                    TodayScreen(snapshot: today.snapshot, onSelectDay: { today.select($0) })
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
                MoneyScreen(snapshot: money.snapshot) { showAddMoney = true }
            case .plan:
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
        coach.attach(context)
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

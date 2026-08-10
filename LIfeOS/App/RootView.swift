import SwiftUI
import SwiftData
import DesignSystem

/// Composition root for the tab hierarchy: owns every feature's view model,
/// hands each one the model context, and reloads them when the store changes.
/// Views below this point never touch SwiftData.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase

    @State private var today = TodayViewModel()
    @State private var body_ = BodyViewModel()
    @State private var activity = ActivityViewModel()
    @State private var recovery = RecoveryViewModel()
    @State private var settings = SettingsViewModel()
    @State private var quickLog = QuickLogViewModel()

    @State private var showQuickLog = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView {
                Tab("Today", systemImage: "circle.grid.3x3.fill") {
                    TodayScreen(snapshot: today.snapshot)
                }
                Tab("Body", systemImage: "figure") {
                    BodyScreen(snapshot: body_.snapshot)
                }
                Tab("Activity", systemImage: "flame.fill") {
                    ActivityScreen(snapshot: activity.snapshot)
                }
                Tab("Recovery", systemImage: "bolt.heart.fill") {
                    RecoveryScreen(snapshot: recovery.snapshot)
                }
                Tab("Settings", systemImage: "gearshape.fill") {
                    SettingsScreen(model: settings)
                }
            }

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
            .padding(.trailing, 20)
            .padding(.bottom, 72)
            .accessibilityLabel("Quick log")
        }
        .sheet(isPresented: $showQuickLog) {
            QuickLogSheet(model: quickLog)
        }
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

    private func attachAll() {
        today.attach(context)
        body_.attach(context)
        activity.attach(context)
        recovery.attach(context)
        settings.attach(context)
        quickLog.attach(context)
    }

    private func reloadAll() {
        today.load()
        body_.load()
        activity.load()
        recovery.load()
        settings.load()
    }
}

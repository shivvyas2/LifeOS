#if DEBUG
import SwiftUI
import SwiftData
import DesignSystem
import Persistence
import Integrations

/// In-memory visual fixtures. Provider clients have empty, isolated credentials.
struct HealthActivityDesignPreview: View {
    @State private var fixture = HealthActivityFixture()
    @State private var section = HealthSection.health
    @State private var day = Date.now
    @State private var share = false
    @State private var checkResults = "Running checks…"
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var page: String { ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--page=") })?.dropFirst(7).description ?? "health" }
    var body: some View {
        Group {
            if page == "checks" {
                ScrollView { Text(checkResults).font(.body.monospaced()).padding(24) }
                    .task {
                        checkResults = await ActivityRecorderChecks.run()
                        let url = URL.documentsDirectory.appending(path: "recorder-checks.txt")
                        try? checkResults.write(to: url, atomically: true, encoding: .utf8)
                    }
            }
            else if page == "activity" {
                BeginActivityScreen(model: fixture.recorder)
                    .task {
                        guard ProcessInfo.processInfo.arguments.contains("--live"), !fixture.recorder.hasSession else { return }
                        fixture.recorder.selection = ProcessInfo.processInfo.arguments.contains("--strength") ? .strength : .run
                        let start = Date.now.addingTimeInterval(-724)
                        await fixture.recorder.start(at: start)
                        for second in stride(from: 0, to: 720, by: 2) {
                            fixture.recorder.sensor.onReading?(second < 120 ? 118 : second < 480 ? 146 : 156, start.addingTimeInterval(Double(second)))
                        }
                        fixture.recorder.sensor.onReading?(152, .now)
                    }
            }
            else if page == "profile" { ProfileDesignPreview() }
            else {
                NavigationStack {
                    if page == "settings" { SettingsScreen(model: fixture.settings, whoop: fixture.whoop, fitbit: fixture.fitbit, health: fixture.health, plaid: fixture.plaid) }
                    else if page == "connections" { ConnectionsSettingsScreen(whoop: fixture.whoop, fitbit: fixture.fitbit, health: fixture.health, plaid: fixture.plaid) }
                    else if page == "sharing" {
                        ScrollView { ProfileActivitySharingCard(isOn: $share).padding(20) }
                            .background(LifeOSTokens.canvas.resolve(.light)).navigationTitle("Together")
                    } else if page == "categories" {
                        ScrollView {
                            VStack(spacing: 16) {
                                StatGroup(title: "Movement", rows: [.init(label: "Steps", value: "8,240"), .init(label: "Exercise", value: "35 min"), .init(label: "Distance", value: "5.2 km"), .init(label: "Flights climbed", value: "8")], hue: .activity, icon: "figure.run")
                                StatGroup(title: "Heart and fitness", rows: [.init(label: "Resting heart rate", value: "54 bpm"), .init(label: "HRV", value: "62 ms"), .init(label: "Cardio fitness", value: "44 ml/kg/min")], hue: .habits, icon: "heart")
                                StatGroup(title: "Walking", rows: [.init(label: "Walking speed", value: "4.8 km/h"), .init(label: "Step length", value: "74 cm"), .init(label: "Asymmetry", value: "2.4%")], hue: .money, icon: "figure.walk")
                                WeightSection(snapshot: .init(weightKg: 77.4, weeklyDeltaKg: 0.2, recentWeights: fixture.weights))
                            }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
                        }.background(LifeOSTokens.canvas.resolve(.light)).navigationTitle("Your readings")
                    } else {
                        HealthHubScreen(activity: .init(steps: 8240, exerciseMinutes: 35, activeEnergyKcal: 460),
                            weight: .init(weightKg: 77.4, weeklyDeltaKg: 0.2, recentWeights: fixture.weights), recovery: fixture.recovery,
                            wellness: .init(journal: [.init(id: UUID(), text: "A long walk, a good conversation, and a little time for myself.", date: .now)]),
                            section: $section, selectedDate: $day)
                    }
                }
            }
        }
        .modelContainer(fixture.container)
        .defaultAppStorage(fixture.defaults)
        .environment(\.layout, .metrics(for: sizeClass == .regular ? .regular : .compact))
        .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("--large") ? .accessibility2 : .large)
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : .light)
    }
}

@MainActor private final class HealthActivityFixture {
    let container = try! LifeOSContainer.make(inMemory: true)
    let defaults = UserDefaults(suiteName: "almanac.design.activity")!
    let recorder: ActivityRecorder
    let settings = SettingsViewModel()
    let whoop = WhoopConnectionViewModel(tokens: InMemoryWhoopTokenStore())
    let fitbit: FitbitConnectionViewModel
    let health: HealthConnectionViewModel
    let plaid: PlaidConnectionViewModel
    let recovery = RecoverySnapshot(recoveryPct: 82, hrvMs: 62, restingHR: 54, sleepMinutes: 432,
        sleepPerformancePct: 89, sleepEfficiencyPct: 92, sleepConsistencyPct: 84, sleepDebtMinutes: 18,
        calories: 460, nights: [SleepComposition(date: .now, lightMinutes: 220, remMinutes: 112, swsMinutes: 100, awakeMinutes: 18)])
    let weights = (0..<14).map { WeightPoint(id: Date.now.addingTimeInterval(Double($0 - 13) * 86400), weightKg: $0 == 5 ? nil : 77.2 + Double($0 % 4) / 10) }
    init() {
        recorder = ActivityRecorder(defaults: defaults, liveActivitiesEnabled: false)
        recorder.saveToHealth = false
        recorder.birthDate = { Calendar.current.date(from: DateComponents(year: 1996, month: 6, day: 1)) }
        _ = try? MetricsStore(context: container.mainContext).upsert(date: .now) { $0.whoopRecoveryPct = 82; $0.whoopSleepPerformancePct = 89 }
        recorder.attach(container.mainContext)
        fitbit = FitbitConnectionViewModel(pending: InMemoryFitbitAuthStore(), sessions: InMemoryAuthSessionStore(), defaults: defaults)
        health = HealthConnectionViewModel(defaults: defaults)
        plaid = PlaidConnectionViewModel(items: UserDefaultsPlaidItemStore(defaults: defaults), sessions: InMemoryAuthSessionStore(), defaults: defaults)
        settings.attach(container.mainContext)
    }
}
#endif

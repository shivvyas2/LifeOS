#if DEBUG
import SwiftUI
import SwiftData
import DesignSystem
import Persistence
import Integrations
import AppSurfaces

/// In-memory visual fixtures. Provider clients have empty, isolated credentials.
struct HealthActivityDesignPreview: View {
    @State private var fixture = HealthActivityFixture()
    /// `--fitness` opens the hub on the Fitness half, where the library row
    /// lives, without a tap the capture script cannot make.
    @State private var section = ProcessInfo.processInfo.arguments.contains("--fitness") ? HealthSection.fitness : .health
    @State private var day = Date.now
    @State private var share = false
    @State private var checkResults = "Running checks…"
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var page: String { ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--page=") })?.dropFirst(7).description ?? "health" }
    fileprivate static var badmintonFixture: WorkoutRecord {
        let row = WorkoutRecord(externalID: "design-badminton", start: .now, durationMinutes: 32, activityName: "Badminton", energyKcal: 216)
        var analysis = SwingAnalysis(); analysis.sampledSeconds = 1852
        analysis.events = (0..<38).map { index in
            // Eight frames at least 0.12 s apart, as the watch keeps them: the
            // review validates what it shows, and rejects anything denser.
            let frames = (0..<8).map { i in
                let angle = sin(Double(i) / 7 * .pi) * 1.8
                return WristFrame(t: Double(i) * 0.12, x: sin(angle / 2), y: 0, z: 0, w: cos(angle / 2))
            }
            return SwingEvent(id: index, time: Double(index) * 47 + 10, duration: 0.96, peakRotation: 5.8 + Double(index % 7) * 0.6, peakAcceleration: 1.5 + Double(index % 5) * 0.3, frames: frames,
                              twist: index % 3 == 0 ? -3.2 : 2.9)
        }
        row.swingAnalysisData = try? JSONEncoder().encode(analysis)
        var tags = BadmintonShotTags()
        tags[0] = BadmintonShotTag(stroke: .backhand, type: .drive)
        tags[1] = BadmintonShotTag(stroke: .forehand, type: .smash)
        tags[2] = BadmintonShotTag(stroke: .forehand, type: .clear)
        row.shotTagsData = try? JSONEncoder().encode(tags)
        var match = BadmintonSession(format: .doubles, teammate: "Priya", opponents: ["Sam", "Alex"])
        // Each game's loser's points first, so the game ends on the winner's 21st.
        for side: BadmintonSide in Array(repeating: .them, count: 17) + Array(repeating: .us, count: 21) { match.record(side) }
        for side: BadmintonSide in Array(repeating: .us, count: 18) + Array(repeating: .them, count: 21) { match.record(side) }
        for side: BadmintonSide in Array(repeating: .them, count: 15) + Array(repeating: .us, count: 21) { match.record(side) }
        row.badmintonData = try? JSONEncoder().encode(match)
        return row
    }
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
                BeginActivityScreen(model: fixture.recorder,
                                    startsCollapsed: ProcessInfo.processInfo.arguments.contains("--hud-collapsed"))
                    .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("--anchor=bottom") ? .bottom : nil)
                    .task {
                        guard ProcessInfo.processInfo.arguments.contains("--live"), !fixture.recorder.hasSession else { return }
                        let arguments = ProcessInfo.processInfo.arguments
                        fixture.recorder.selection = arguments.contains("--strength") ? ActivityCatalog.strength
                            : arguments.contains("--badminton") ? (ActivityCatalog.type(named: "Badminton") ?? ActivityCatalog.run)
                            : ActivityCatalog.run
                        if arguments.contains("--badminton") {
                            fixture.recorder.badmintonSetup = BadmintonSession(format: .doubles, teammate: "Priya", opponents: ["Sam", "Alex"])
                        }
                        let start = Date.now.addingTimeInterval(-724)
                        await fixture.recorder.start(backdatedTo: start)
                        for second in stride(from: 0, to: 720, by: 2) {
                            fixture.recorder.sensor.onReading?(second < 120 ? 118 : second < 480 ? 146 : 156, start.addingTimeInterval(Double(second)))
                        }
                        fixture.recorder.sensor.onReading?(152, .now)
                        fixture.recorder.addRep(); fixture.recorder.addRep(); fixture.recorder.nextSet(); fixture.recorder.addRep()
                        if arguments.contains("--badminton") {
                            for _ in 0..<21 { fixture.recorder.scoreRally(.us) }
                            for side: BadmintonSide in [.them, .us, .us, .them, .us, .them, .them, .us, .us, .us] { fixture.recorder.scoreRally(side) }
                        }
                    }
            }
            else if page == "badminton-setup" {
                BeginActivityScreen(model: fixture.recorder)
                    .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("--anchor=bottom") ? .bottom : nil)
                    .task {
                        fixture.recorder.selection = ActivityCatalog.type(named: "Badminton") ?? ActivityCatalog.run
                        fixture.recorder.badmintonSetup = BadmintonSession(format: .doubles, teammate: "Priya", opponents: ["Sam", "Alex"])
                        // `--analysis-on` shows the status line as a set-up player sees it.
                        if ProcessInfo.processInfo.arguments.contains("--analysis-on") {
                            fixture.recorder.athlete = ActivityAthleteProfile(playingHand: .right, watchWrist: .right, motionEnabled: true)
                        }
                    }
            }
            else if page == "badminton" {
                // `--anchor=center|bottom` opens the review scrolled, so a
                // capture can reach the lower panels without a swipe.
                NavigationStack { BadmintonReviewScreen(workout: Self.badmintonFixture) }
                    .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("--anchor=bottom") ? .bottom
                                         : ProcessInfo.processInfo.arguments.contains("--anchor=center") ? .center : nil)
            }
            else if page == "badminton-history" || page == "badminton-history-empty" {
                NavigationStack { BadmintonHistoryScreen(onDemo: {}) }
                    .task { if page == "badminton-history" { fixture.seedBadmintonHistory() } }
            }
            // The script runs faster than the clock so a capture a few seconds
            // in shows a match under way, or, for `-done`, already finished.
            else if page == "badminton-demo" || page == "badminton-demo-done" {
                BeginActivityScreen(model: fixture.recorder)
                    .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("--anchor=bottom") ? .bottom : nil)
                    .task {
                        guard !fixture.recorder.hasSession else { return }
                        fixture.recorder.startDemo(tick: .milliseconds(50), timeScale: page == "badminton-demo-done" ? 400 : 12)
                    }
            }
            // The review a finished demo opens, without the tap: run the whole
            // script in a couple of seconds, then show what it left behind.
            else if page == "badminton-demo-review" {
                NavigationStack {
                    if let review = fixture.recorder.demoReview {
                        BadmintonReviewScreen(workout: review)
                            .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("--anchor=bottom") ? .bottom : nil)
                    } else {
                        ProgressView("Playing the demo…")
                    }
                }
                .task {
                    guard !fixture.recorder.hasSession, fixture.recorder.demoReview == nil else { return }
                    fixture.recorder.startDemo(tick: .milliseconds(20), timeScale: 600)
                }
            }
            else if page == "profile" { ProfileDesignPreview() }
            else if page == "money" || page.hasPrefix("nav") { EditorialDesignPreview(page: page) }
            else if page.hasPrefix("life") || page == "shell" { LifeDesignPreview(page: page) }
            else if ["today", "today-empty", "today-done", "today-custom", "today-arranging", "today-ipad-custom", "today-inbox", "month", "schedule", "calendar-find", "calendar-ask", "day", "day-past", "day-future", "day-far", "day-empty", "day-no-location", "day-github", "day-github-issues", "day-github-today-none", "day-github-reconnect", "day-github-stale", "notes", "notes-empty"].contains(page) { TodayDesignPreview(page: page) }
            else if ["notes-editor-new", "notes-filing", "notes-editor", "notes-editor-picker", "notes-walkthrough", "notes-walkthrough-live"].contains(page) { NotesDesignPreview(page: page) }
            else if ["coach", "coach-empty", "coach-voice"].contains(page) { CoachDesignPreview(page: page) }
            else if ["settings-clear-data", "settings-delete-account", "keep-account"].contains(page) { AccountControlsDesignPreview(page: page) }
            else if page == "projects" || page.hasPrefix("project-") { ProjectsDesignPreview(page: page) }
            else if ["assistant", "assistant-confirm", "assistant-empty"].contains(page) { AssistantDesignPreview(page: page) }
            else if page == "library" || page == "library-empty" {
                NavigationStack {
                    WorkoutLibraryScreen(model: fixture.library, recorder: fixture.recorder,
                                         startsScheduling: ProcessInfo.processInfo.arguments.contains("--schedule-sheet"))
                }
            }
            // `--video=<id>` picks another seed row, which is how the embed
            // spot-check plays more than one video without a tap.
            else if page == "player" {
                NavigationStack {
                    VideoWorkoutScreen(video: fixture.playerVideo, model: fixture.recorder)
                }
                .task {
                    guard ProcessInfo.processInfo.arguments.contains("--live"), !fixture.recorder.hasSession else { return }
                    let video = fixture.playerVideo
                    fixture.recorder.selection = VideoWorkoutScreen.activity(for: video.split)
                    let start = Date.now.addingTimeInterval(-724)
                    await fixture.recorder.start(backdatedTo: start,
                                                 following: (id: video.youtubeID, split: video.split,
                                                             title: video.title, channel: video.channel))
                    for second in stride(from: 0, to: 720, by: 2) {
                        fixture.recorder.sensor.onReading?(second < 120 ? 118 : second < 480 ? 146 : 156, start.addingTimeInterval(Double(second)))
                    }
                    fixture.recorder.sensor.onReading?(152, .now)
                    fixture.recorder.addRep(); fixture.recorder.addRep(); fixture.recorder.nextSet(); fixture.recorder.addRep()
                }
            }
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
                            library: fixture.library, recorder: fixture.recorder, section: $section, selectedDate: $day)
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
    // Typed step by step: the one-expression form times out the type checker
    // on slower machines.
    let weights: [WeightPoint] = (0..<14).map { (day: Int) -> WeightPoint in
        let date: Date = Date.now.addingTimeInterval(Double(day - 13) * 86400)
        let kg: Double? = day == 5 ? nil : 77.2 + Double(day % 4) / 10
        return WeightPoint(id: date, weightKg: kg)
    }
    /// The library reads the keychain for a token in the real app; the
    /// fixture hands it an empty in-memory store so a preview never reaches
    /// the network and the offline copy is what a capture shows.
    let library = WorkoutLibraryViewModel(sessions: InMemoryAuthSessionStore())
    /// The row the player page renders, chosen once so a re-render never
    /// rebuilds the web view under a running session.
    let playerVideo: CatalogVideo
    init() {
        let requested = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--video=") }.map { String($0.dropFirst(8)) }
        playerVideo = CatalogVideo(Self.catalog.first { $0.youtubeID == requested } ?? Self.catalog[0])
        recorder = ActivityRecorder(defaults: defaults, liveActivitiesEnabled: ProcessInfo.processInfo.arguments.contains("--live-activity"))
        recorder.saveToHealth = false
        recorder.birthDate = { Calendar.current.date(from: DateComponents(year: 1996, month: 6, day: 1)) }
        _ = try? MetricsStore(context: container.mainContext).upsert(date: .now) { $0.whoopRecoveryPct = 82; $0.whoopSleepPerformancePct = 89 }
        recorder.attach(container.mainContext)
        fitbit = FitbitConnectionViewModel(pending: InMemoryFitbitAuthStore(), sessions: InMemoryAuthSessionStore(), defaults: defaults)
        health = HealthConnectionViewModel(defaults: defaults)
        plaid = PlaidConnectionViewModel(items: UserDefaultsPlaidItemStore(defaults: defaults), sessions: InMemoryAuthSessionStore(), defaults: defaults)
        settings.attach(container.mainContext)
        seedLibrary()
        library.attach(container.mainContext)
    }

    /// Four past sessions for the history page: one with a motion review, one
    /// still waiting for its Watch, one whose motion the review rejects, and
    /// one imported from WHOOP with no motion at all.
    func seedBadmintonHistory() {
        let context = container.mainContext
        let reviewed = HealthActivityDesignPreview.badmintonFixture
        reviewed.start = .now.addingTimeInterval(-2 * 86400)
        context.insert(reviewed)
        let waiting = WorkoutRecord(externalID: "almanac-watch:\(UUID().uuidString)", start: .now.addingTimeInterval(-3600),
                                    durationMinutes: 41, activityName: "Badminton", energyKcal: 280)
        var singles = BadmintonSession(opponents: ["Dev"])
        for side: BadmintonSide in Array(repeating: .them, count: 12) + Array(repeating: .us, count: 21) { singles.record(side) }
        waiting.badmintonData = try? JSONEncoder().encode(singles)
        context.insert(waiting)
        let rejected = WorkoutRecord(externalID: "almanac-watch:\(UUID().uuidString)", start: .now.addingTimeInterval(-5 * 86400),
                                     durationMinutes: 10, activityName: "Badminton", energyKcal: 70)
        var tooLong = SwingAnalysis(); tooLong.sampledSeconds = 5000
        rejected.swingAnalysisData = try? JSONEncoder().encode(tooLong)
        context.insert(rejected)
        context.insert(WorkoutRecord(externalID: "whoop:118-\(UUID().uuidString)", start: .now.addingTimeInterval(-9 * 86400),
                                     durationMinutes: 55, activityName: "Badminton", energyKcal: 410))
        try? context.save()
    }

    /// Strength, dumbbells, thirty minutes, and a push day two days ago, so
    /// the planner lands on a pull day of about half an hour. `library-empty`
    /// keeps the preferences and leaves the catalog cache empty.
    private func seedLibrary() {
        let context = container.mainContext
        if let goals = try? MetricsStore(context: context).goals() {
            goals.trainingGoal = "strength"
            goals.equipmentRaw = ["dumbbells", "bands"]
            goals.sessionMinutes = 30
        }
        for (days, split, minutes) in [(2, "push", 32), (4, "legs", 41)] {
            let record = WorkoutRecord(externalID: "design-\(split)", start: .now.addingTimeInterval(Double(-days) * 86400),
                                       durationMinutes: minutes, activityName: "Strength")
            record.split = split
            context.insert(record)
        }
        if !ProcessInfo.processInfo.arguments.contains("--page=library-empty") {
            try? CatalogStore.upsert(Self.catalog, context: context)
            // One saved and one scheduled for today, both inside the plan's
            // own filter, so a capture shows the heart and the day chip.
            _ = try? BookmarkStore.toggleSaved("aFnUKszjprs", context: context)
            try? BookmarkStore.schedule("ifVk1E5My7M", on: .now, context: context)
        }
        try? context.save()
    }

    /// Six rows lifted from the shipped seed, in the shape the server returns
    /// them, so a capture shows the catalog's real thumbnails and titles.
    private static let catalog: [CatalogVideoRow] = [
        .init(youtubeID: "ifVk1E5My7M", title: "30 Min PULL DAY DUMBBELL WORKOUT | Back & Bicep | 13 of Hybrid Series",
              channel: "Tom Peto Training", durationS: 1_800, goal: ["strength", "hypertrophy"], split: "pull",
              muscles: ["back", "biceps"], equipment: ["dumbbells"], intensity: 2, verifiedAt: .now),
        .init(youtubeID: "aFnUKszjprs", title: "30 Minute Back & Biceps AMRAP Workout",
              channel: "Sydney Cummings Houdyshell", durationS: 1_800, goal: ["strength", "hypertrophy"], split: "pull",
              muscles: ["back", "biceps"], equipment: ["dumbbells"], intensity: 2, verifiedAt: .now),
        .init(youtubeID: "3pHz96dv8dE", title: "30 Minute Dumbbell Pull Workout For Strength & Mass Gain!",
              channel: "Midas Movement", durationS: 1_800, goal: ["strength", "hypertrophy"], split: "pull",
              muscles: ["back", "biceps"], equipment: ["dumbbells"], intensity: 3, verifiedAt: .now),
        .init(youtubeID: "KqZG-vlcYhg", title: "Biceps and Triceps Superset Strength Workout",
              channel: "FitnessBlender", durationS: 2_220, goal: ["strength", "hypertrophy"], split: "pull",
              muscles: ["biceps", "triceps"], equipment: ["none", "dumbbells"], intensity: 2, verifiedAt: .now),
        .init(youtubeID: "BoTAfri7Bec", title: "20 MIN PULL UP BAR + DUMBBELL WORKOUT | Follow Along",
              channel: "Tom Peto Training", durationS: 1_200, goal: ["strength", "hypertrophy"], split: "pull",
              muscles: ["back", "biceps"], equipment: ["dumbbells"], intensity: 2, verifiedAt: .now),
        .init(youtubeID: "1fahiYJIYgI", title: "10 Minute Chest and Triceps",
              channel: "FitnessBlender", durationS: 600, goal: ["strength", "hypertrophy"], split: "push",
              muscles: ["chest", "triceps"], equipment: ["dumbbells"], intensity: 1, verifiedAt: .now)
    ]
}
#endif

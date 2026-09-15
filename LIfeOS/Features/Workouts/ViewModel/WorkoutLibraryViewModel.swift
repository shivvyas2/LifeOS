import Foundation
import SwiftData
import Persistence
import Integrations
import Sectors

/// The band titles the chip rail renders. The bands themselves live in
/// `Sectors` beside the filter that reads them, so the rule and its names
/// cannot drift apart.
extension DurationBand {
    var title: String {
        switch self {
        case .under20: "Under 20"
        case .from20to40: "20 to 40"
        case .over40: "Over 40"
        }
    }
}

/// Today's session and the catalog filtered to it.
///
/// The cache is the source the screen renders; the network only ever adds to
/// it. A refresh that fails leaves the last catalog on screen and says so,
/// because a person on a train still wants the workout they saw yesterday.
@MainActor @Observable
final class WorkoutLibraryViewModel {
    /// The goal vocabulary the planner understands.
    static let goalOptions = ["strength", "hypertrophy", "endurance", "mobility"]
    /// The equipment vocabulary the catalog tags rows with.
    static let equipmentOptions = ["none", "dumbbells", "barbell", "bands", "machine", "kettlebell"]
    static let minuteOptions = Array(stride(from: 15, through: 90, by: 15))
    /// A catalog older than this is refetched when the library opens.
    static let refreshInterval: TimeInterval = 86_400

    private(set) var videos: [CatalogVideo] = []
    private(set) var filtered: [CatalogVideo] = []
    private(set) var plan: TrainingPlan?
    private(set) var capacity: Capacity?
    private(set) var status: String?
    private(set) var isRefreshing = false

    /// The person's overrides on top of the plan. Nil means "as planned":
    /// the plan's split, and its minutes give or take fifteen.
    var splitFilter: String? { didSet { applyFilters() } }
    var durationBand: DurationBand? { didSet { applyFilters() } }
    var equipmentFilter: String? { didSet { applyFilters() } }

    /// Drives the preferences sheet: true until a training goal is set, and
    /// settable so the toolbar can reopen it.
    var needsPreferences = false

    private var context: ModelContext?
    private var goals: UserGoals?
    /// Sticky across filter changes: a failed refresh stays explained until
    /// the next one succeeds.
    private var refreshNotice: String?
    private let calendar: Calendar
    private let sessions: any AuthSessionStoring
    private let now: () -> Date

    init(calendar: Calendar = .current,
         sessions: any AuthSessionStoring = KeychainAuthSessionStore(),
         now: @escaping () -> Date = { .now }) {
        self.calendar = calendar
        self.sessions = sessions
        self.now = now
    }

    func attach(_ context: ModelContext) {
        self.context = context
        load()
        // Raised once, on the first open with no goal. `load()` runs again on
        // every scene activation and Health sync, and deciding it there put
        // the sheet back up the moment a person dismissed it.
        needsPreferences = goals?.trainingGoal == nil
    }

    /// Everything the screen needs, read in one pass: preferences, the cache,
    /// today's battery, and the week of splits the rotation turns on.
    func load() {
        guard let context else { return }
        let store = MetricsStore(context: context, calendar: calendar)
        let today = now()
        goals = try? store.goals()
        videos = (try? CatalogStore.all(context: context)) ?? []
        capacity = CapacityInputs.todayCapacity(store: store, now: today, calendar: calendar)

        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let recent: [(date: Date, split: String)] = ((try? store.workouts(from: weekAgo, to: today)) ?? [])
            .compactMap { record in record.split.map { (date: record.start, split: $0) } }

        plan = WorkoutPlanner.plan(goal: goals?.trainingGoal, sessionMinutes: goals?.sessionMinutes,
                                   batteryPercent: capacity?.percent, recentSplits: recent,
                                   now: today, calendar: calendar)
        applyFilters()
    }

    // MARK: - Refresh

    /// Fetches the catalog when the newest cached row is more than a day old,
    /// or on pull to refresh. A failure never empties the cache.
    func refreshIfDue(force: Bool = false) async {
        guard let context, !isRefreshing else { return }
        let newest = videos.map(\.cachedAt).max()
        let due = force || newest.map { now().timeIntervalSince($0) > Self.refreshInterval } ?? true
        guard due else { return }

        guard let baseURL = AppConfig.supabaseURL, let anonKey = AppConfig.supabaseAnonKey else { noteOffline(); return }
        guard let token = sessions.load()?.accessToken else { noteSignedOut(); return }

        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let rows = try await WorkoutCatalogClient(baseURL: baseURL, anonKey: anonKey).videos(accessToken: token)
            // A 200 with no rows is far more often an unseeded table or a
            // policy that stopped matching than a library that really emptied.
            guard CatalogRefresh.shouldReplace(cacheCount: videos.count, incoming: rows.count) else {
                refreshNotice = "The catalog came back empty. Showing the last one we downloaded."
                applyFilters()
                return
            }
            try CatalogStore.upsert(rows, context: context, now: now())
            refreshNotice = nil
            load()
        } catch {
            noteOffline()
        }
    }

    private func noteOffline() {
        refreshNotice = videos.isEmpty
            ? "The library needs a connection the first time."
            : "Showing the last catalog we downloaded."
        applyFilters()
    }

    /// Not a connection problem: the catalog is read with the person's own
    /// token, so the way forward is signing in, not finding signal.
    private func noteSignedOut() {
        refreshNotice = "Sign in to download the library."
        applyFilters()
    }

    // MARK: - Filtering

    /// The rule itself lives in `Sectors` as a pure function with tests; this
    /// maps the cache into it and the chosen ids back out.
    private func applyFilters() {
        guard let plan else {
            filtered = videos
            status = refreshNotice
            return
        }
        let byID = Dictionary(videos.map { ($0.youtubeID, $0) }, uniquingKeysWith: { _, last in last })
        let result = WorkoutLibraryFilter.apply(
            videos: videos.map {
                LibraryVideo(id: $0.youtubeID, title: $0.title, split: $0.split, intensity: $0.intensity,
                             durationMinutes: $0.durationMinutes, goal: $0.goal, equipment: $0.equipment)
            },
            plan: plan, goal: goals?.trainingGoal, split: splitFilter, band: durationBand,
            equipment: equipmentFilter.map { Set([$0]) } ?? [])
        filtered = result.rows.compactMap { byID[$0.id] }
        // Both lines, not one: a person offline on a widened list needs to
        // know the list is short *and* that the catalog is stale.
        status = [result.note, refreshNotice].compactMap { $0 }.joined(separator: "\n").nilIfEmpty
    }

    /// The splits worth offering: the ones the cache actually holds, with the
    /// plan's own split first so the default filter reads as the default.
    var splitOptions: [String] {
        let present = Set(videos.map(\.split)).sorted()
        guard let planned = plan?.split else { return present }
        return [planned] + present.filter { $0 != planned }
    }

    /// Only the equipment the person said they have, per section 5.1.
    var equipmentOptions: [String] { goals?.equipmentRaw ?? [] }

    // MARK: - Readouts

    /// The readout's own vocabulary, so the number here and the number on the
    /// HUD are plainly the same number.
    var batteryLine: String? {
        guard let capacity else { return nil }
        return "Battery \(capacity.percent)% · up to zone \(EffortCeiling.forCapacity(capacity.percent).maxZone)"
    }

    var preferredGoal: String? { goals?.trainingGoal }
    var preferredEquipment: [String] { goals?.equipmentRaw ?? [] }
    var preferredMinutes: Int { goals?.sessionMinutes ?? 30 }

    // MARK: - Preferences

    func savePreferences(goal: String, equipment: [String], minutes: Int) {
        guard let context, let goals else { return }
        goals.trainingGoal = goal
        goals.equipmentRaw = equipment
        goals.sessionMinutes = minutes
        try? context.save()
        // The plan is built from these three, so it is recomputed, not nudged.
        load()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

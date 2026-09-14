import Foundation
import SwiftData
import Persistence
import Integrations
import Sectors

/// The three length bands the library filters by. Bounds are inclusive at the
/// bottom and exclusive at the top so every minute count lands in exactly one.
enum DurationBand: String, CaseIterable, Identifiable, Sendable {
    case under20, twentyToForty, overForty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .under20: "Under 20"
        case .twentyToForty: "20 to 40"
        case .overForty: "Over 40"
        }
    }

    func contains(_ minutes: Int) -> Bool {
        switch self {
        case .under20: minutes < 20
        case .twentyToForty: (20...40).contains(minutes)
        case .overForty: minutes > 40
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
        needsPreferences = goals?.trainingGoal == nil
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

        guard let baseURL = AppConfig.supabaseURL, let anonKey = AppConfig.supabaseAnonKey,
              let token = sessions.load()?.accessToken else { noteOffline(); return }

        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let rows = try await WorkoutCatalogClient(baseURL: baseURL, anonKey: anonKey).videos(accessToken: token)
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

    // MARK: - Filtering

    /// The plan first: its split, its intensity cap, its length give or take
    /// fifteen minutes. An empty result widens one step at a time and says
    /// which step it took, so a short list is never a mystery.
    private func applyFilters() {
        guard let plan else {
            filtered = videos
            status = refreshNotice
            return
        }
        let split = splitFilter ?? plan.split
        let base = videos.filter { video in
            video.intensity <= plan.maxIntensity
                && (equipmentFilter.map { video.equipment.contains($0) } ?? true)
        }
        func inBand(_ video: CatalogVideo) -> Bool {
            if let durationBand { return durationBand.contains(video.durationMinutes) }
            return abs(video.durationMinutes - plan.minutes) <= 15
        }

        var widened: String?
        var result = base.filter { $0.split == split && inBand($0) }
        if result.isEmpty {
            result = base.filter { $0.split == split }
            if !result.isEmpty { widened = "Widened to any length." }
        }
        if result.isEmpty {
            result = base.filter { video in goals?.trainingGoal.map { video.goal.contains($0) } ?? true }
            if !result.isEmpty { widened = "Widened to any split for your goal." }
        }

        filtered = result.sorted {
            let left = abs($0.durationMinutes - plan.minutes), right = abs($1.durationMinutes - plan.minutes)
            return left == right ? $0.title < $1.title : left < right
        }
        status = widened ?? refreshNotice
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

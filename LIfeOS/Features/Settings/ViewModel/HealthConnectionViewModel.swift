import Foundation
import SwiftData
import OSLog
import Integrations
import Persistence

private let healthLog = Logger(subsystem: "com.shivvyas.lifeos", category: "health")

/// Owns the Apple Health connection: the permission prompt and the sync.
///
/// Deliberately thinner than `WhoopConnectionViewModel`, because Health has no
/// OAuth, no tokens and no server. What it does have is a permission model that
/// refuses to tell us anything, which shapes everything below.
@MainActor @Observable
final class HealthConnectionViewModel {
    enum State: Equatable {
        /// iPad without Health, or a device that has none.
        case unavailable
        /// Never asked. The row offers to connect.
        case notAsked
        case syncing
        /// Asked, and days were read. The count is days touched, not days with
        /// data, because Health will not say which is which.
        case synced(days: Int)
        /// Asked, and nothing came back. Indistinguishable from a refusal by
        /// design, so the copy has to cover both without guessing.
        case noData
        case failed(String)
    }

    private(set) var state: State = .notAsked

    /// UserDefaults rather than Keychain: a sync timestamp is a convenience,
    /// not a secret, and this matches where the Whoop sync keeps its own.
    /// Internal rather than private: the one-time purge of seeded history
    /// clears this too, so the sync that follows backfills the whole window
    /// instead of only the days since the last run.
    static let lastSyncKey = "healthLastSyncedAt"
    /// Whether cycle metrics are read at all. Absent means "never decided",
    /// which is not the same as off: the first connect fills it in from what
    /// Health holds, and after that it is whatever the person set.
    private static let cycleTrackingKey = "healthReadsCycleTracking"
    /// Whether the user has ever been through the Health prompt. iOS shows it
    /// once and never again, so the row must stop offering "Connect" after
    /// that or it becomes a button that visibly does nothing.
    private static let hasAskedKey = "healthAuthorisationRequested"

    private let reader: HealthKitReader
    private let defaults: UserDefaults
    private var context: ModelContext?
    /// The in-flight sync, so a launch task and a foreground transition
    /// arriving together do one pass rather than two.
    private var running: Task<Void, Never>?
    /// The foreground watch on Health. One at a time; `startWatching` is
    /// idempotent so a tab change and a foreground transition cannot start a
    /// second.
    private var watching: Task<Void, Never>?

    /// Per account, because the sync cursor, the cycle switch and whether
    /// permission has been asked for are all facts about one person rather
    /// than about the phone.
    init(reader: HealthKitReader = HealthKitReader(), defaults: UserDefaults = .currentAccount) {
        self.reader = reader
        self.defaults = defaults
    }

    func attach(_ context: ModelContext) {
        self.context = context
        refreshState()
    }

    func refreshState() {
        guard reader.isAvailable else { state = .unavailable; return }
        guard defaults.bool(forKey: Self.hasAskedKey) else { state = .notAsked; return }
        if case .syncing = state { return }
        state = lastSync == nil ? .noData : .synced(days: 0)
    }

    var isConnected: Bool {
        switch state {
        case .synced, .noData: true
        case .unavailable, .notAsked, .syncing, .failed: false
        }
    }

    /// What the connection row shows.
    ///
    /// `.noData` deliberately does not say "denied". HealthKit never reports
    /// whether read access was granted, because admitting a refusal would leak
    /// that the user has no data of that type. Claiming a denial we cannot see
    /// would be a guess presented as a fact, so the copy covers both cases and
    /// points at the one place that knows.
    var statusDetail: String {
        switch state {
        case .unavailable:      "Not available on this device"
        case .notAsked:         "Steps, sleep, weight and heart data"
        case .syncing:          "Reading…"
        case .synced(let days): days > 0 ? "Read \(days) days" : "Connected"
        case .noData:           "No data yet. Check Almanac in Health > Sharing"
        case .failed(let why):  why
        }
    }

    private var lastSync: Date? {
        defaults.object(forKey: Self.lastSyncKey) as? Date
    }

    /// Whether the app reads menstrual and cycle data.
    ///
    /// Deliberately not derived from the gender asked at signup. That field
    /// says how someone wants to be addressed, and its own comment says so:
    /// it is "not a biological-sex field wearing a friendlier label". Using it
    /// here would get the answer wrong in both directions, and would strand
    /// everyone who chose "Prefer not to say", which is the default.
    ///
    /// The default comes from Health's own sex characteristic, which is the
    /// user's setting in Apple's app and the same thing Health itself uses to
    /// decide whether to show Cycle Tracking. A default, not a rule: a trans
    /// man may track a cycle and a woman past menopause may not want to, so
    /// the switch is offered to everyone either way.
    var readsCycleTracking: Bool {
        defaults.bool(forKey: Self.cycleTrackingKey)
    }

    /// Turns cycle reading on or off. Turning it on asks for the extra
    /// permission there and then, so the prompt arrives with the tap that
    /// caused it rather than at some later sync.
    func setCycleTracking(_ enabled: Bool) async {
        defaults.set(enabled, forKey: Self.cycleTrackingKey)
        guard enabled, reader.isAvailable else { return }
        do {
            try await reader.requestCycleAuthorisation()
        } catch {
            healthLog.error("cycle authorisation failed: \(String(describing: error), privacy: .public)")
        }
        await sync()
    }

    /// Asks for permission, then reads. The prompt only ever appears once;
    /// after that this is just a sync.
    func connect() async {
        guard reader.isAvailable else { state = .unavailable; return }
        do {
            try await reader.requestAuthorisation()
            defaults.set(true, forKey: Self.hasAskedKey)
            await decideCycleDefault()
        } catch {
            healthLog.error("authorisation failed: \(String(describing: error), privacy: .public)")
            state = .failed("Could not open Health")
            return
        }
        await sync()
        // Straight after the first read, so the person who just connected sees
        // the numbers move rather than waiting for the next foreground.
        startWatching()
    }

    /// Re-reads the window since the last sync. Safe to call on every launch:
    /// a sync minutes old costs one day of queries.
    func syncIfConnected() async {
        guard reader.isAvailable, defaults.bool(forKey: Self.hasAskedKey) else { return }
        await sync()
    }

    /// Re-reads today whenever Health records something, for as long as the
    /// app is in front.
    ///
    /// This is what makes a step count on screen climb rather than sit at
    /// whatever it was when the tab was opened. The pass writes through
    /// `MetricsStore`, which saves, and `RootView` reloads every snapshot on
    /// `ModelContext.didSave` — so nothing here knows about a screen, and the
    /// tiles repaint through the path they already used.
    func startWatching() {
        guard watching == nil, reader.isAvailable,
              defaults.bool(forKey: Self.hasAskedKey) else { return }
        watching = Task { [weak self, reader] in
            for await _ in await reader.changes() {
                guard let self, !Task.isCancelled else { return }
                await self.syncIfConnected()
                // A day's steps arrive in dozens of batches, and re-reading ten
                // metrics for each one would spend the afternoon in HealthKit
                // to move a numeral. The stream buffers one event, so whatever
                // landed during this pause is still waiting when it ends.
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    /// Stops the watch. Called when the app leaves the foreground, so a phone
    /// in a pocket is not running ten queries a quarter minute.
    func stopWatching() {
        watching?.cancel()
        watching = nil
        Task { [reader] in await reader.stopObserving() }
    }

    /// Runs once, after the first authorisation, when nothing has been decided
    /// yet. Someone who has already chosen keeps their choice.
    private func decideCycleDefault() async {
        guard defaults.object(forKey: Self.cycleTrackingKey) == nil else { return }
        let isFemale = await reader.healthSuggestsCycleTracking()
        defaults.set(isFemale, forKey: Self.cycleTrackingKey)
        // Only the people it applies to see a second prompt, and only right
        // after the first, where it reads as part of the same setup.
        if isFemale {
            try? await reader.requestCycleAuthorisation()
        }
    }

    private func sync() async {
        if let running {
            await running.value
            return
        }
        guard let context else { return }

        let readsCycle = readsCycleTracking
        let task = Task { @MainActor [reader, defaults] in
            state = .syncing
            let store = MetricsStore(context: context)
            let window = HealthSyncWindow.days(since: defaults.object(forKey: Self.lastSyncKey) as? Date)
            var written = 0

            for day in window {
                let health = await reader.day(day, includingCycle: readsCycle)
                // A day Health knows nothing about is skipped rather than
                // written: an upsert would create an empty row and put a blank
                // day on the calendar that nothing ever fills.
                guard !health.values.isEmpty else { continue }
                do {
                    try HealthApply.write(health, into: store)
                    written += 1
                } catch {
                    healthLog.error("write failed for \(day, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }

            defaults.set(Date.now, forKey: Self.lastSyncKey)
            state = written > 0 ? .synced(days: written) : .noData
            healthLog.info("health sync wrote \(written) of \(window.count) days")
        }
        running = task
        await task.value
        running = nil
    }
}

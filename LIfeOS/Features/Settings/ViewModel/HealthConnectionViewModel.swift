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
    private static let lastSyncKey = "healthLastSyncedAt"
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

    init(reader: HealthKitReader = HealthKitReader(), defaults: UserDefaults = .standard) {
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

    /// Asks for permission, then reads. The prompt only ever appears once;
    /// after that this is just a sync.
    func connect() async {
        guard reader.isAvailable else { state = .unavailable; return }
        do {
            try await reader.requestAuthorisation()
            defaults.set(true, forKey: Self.hasAskedKey)
        } catch {
            healthLog.error("authorisation failed: \(String(describing: error), privacy: .public)")
            state = .failed("Could not open Health")
            return
        }
        await sync()
    }

    /// Re-reads the window since the last sync. Safe to call on every launch:
    /// a sync minutes old costs one day of queries.
    func syncIfConnected() async {
        guard reader.isAvailable, defaults.bool(forKey: Self.hasAskedKey) else { return }
        await sync()
    }

    private func sync() async {
        if let running {
            await running.value
            return
        }
        guard let context else { return }

        let task = Task { @MainActor [reader, defaults] in
            state = .syncing
            let store = MetricsStore(context: context)
            let window = HealthSyncWindow.days(since: defaults.object(forKey: Self.lastSyncKey) as? Date)
            var written = 0

            for day in window {
                let health = await reader.day(day)
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

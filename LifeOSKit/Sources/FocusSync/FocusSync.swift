import Foundation
import SwiftData
import OSLog
import Integrations
import Persistence

private let log = Logger(subsystem: "com.shivvyas.lifeos", category: "focus-sync")

/// Sends finished sessions up and brings the week's sessions down.
///
/// Every failure leaves state as it was: an unsent record stays pending and
/// goes on the next run. A run is never retried in a loop; the next trigger
/// (a save, the app becoming active, the network returning) is the retry.
@MainActor
public final class FocusSync {
    private let store: FocusStore
    private let remote: any FocusRemote
    /// The account this store belongs to. A session for anyone else is
    /// refused, so an account switch mid-run can never mix two accounts.
    private let owner: String
    private let session: @MainActor () -> AuthSession?
    private var running: Task<Void, Never>?

    public init(context: ModelContext, remote: any FocusRemote, owner: String,
                session: @escaping @MainActor () -> AuthSession?) {
        self.store = FocusStore(context: context)
        self.remote = remote
        self.owner = owner
        self.session = session
    }

    public var pendingCount: Int { (try? store.pending().count) ?? 0 }

    /// Upload, then pull. A call while a run is in flight joins that run.
    public func run() async {
        if let running { return await running.value }
        let task = Task { _ = await uploadPending(); _ = await pullWeek() }
        running = task
        await task.value
        running = nil
    }

    public func uploadPending() async -> Int {
        guard let token = usableToken() else { return 0 }
        guard let records = try? store.pending(), !records.isEmpty else { return 0 }
        let snapshots = records.map(\.snapshot)
        do {
            let body = try FocusRow.encoder.encode(snapshots.map(FocusRow.init))
            try await remote.insertIgnoringDuplicates(table: "focus_sessions", body: body, accessToken: token)
            try store.markSynced(ids: snapshots.map(\.id))
            return snapshots.count
        } catch {
            log.info("upload deferred: \(String(describing: error), privacy: .public)")
            return 0
        }
    }

    public func pullWeek(now: Date = .now, calendar: Calendar = .current) async -> Int {
        guard let token = usableToken(),
              let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        do {
            let data = try await remote.focusRows(since: start, accessToken: token)
            let rows = try FocusRow.decoder.decode([FocusRow].self, from: data)
            return try store.merge(remote: rows.map(\.snapshot))
        } catch {
            log.info("pull deferred: \(String(describing: error), privacy: .public)")
            return 0
        }
    }

    /// A token only while signed in as the owner and unexpired. Refreshing is the auth
    /// layer's job, done on foreground; this never refreshes on its own.
    private func usableToken() -> String? {
        guard let current = session(), current.userID == owner, !current.isExpired() else { return nil }
        return current.accessToken
    }
}

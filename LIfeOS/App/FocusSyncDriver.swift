import Foundation
import Network
import SwiftData
import FocusSync
import Integrations

/// Decides when focus sessions sync: on launch, on becoming active, after a
/// session is saved, and when the network comes back. `FocusSync` decides
/// what; this only pulls the trigger. History from before sync existed goes
/// up on the first run, because every old record is still pending.
@MainActor
final class FocusSyncDriver {
    static let shared = FocusSyncDriver()
    private var sync: FocusSync?
    private let monitor = NWPathMonitor()
    private var monitoring = false
    private var wasOffline = false

    /// Called by each account's root view. A new context replaces the old
    /// one: the shell is re-rooted per account, so the newest attach is
    /// always the account on screen, and its token is read fresh per run.
    func attach(_ context: ModelContext) {
        // Pinned to the account current now, which is the one whose store
        // this context is. Each run still reads the current session (which
        // also finds a pre-accounts session in the legacy slot), and FocusSync
        // refuses it unless it is this owner's.
        guard let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey,
              let owner = KeychainAuthSessionStore().load()?.userID else { return }
        sync = FocusSync(context: context, remote: SupabaseREST(baseURL: url, anonKey: key), owner: owner,
                         session: { KeychainAuthSessionStore().load() })
        startMonitoring()
    }

    func request() {
        guard let sync else { return }
        Task { await sync.run() }
    }

    private func startMonitoring() {
        guard !monitoring else { return }
        monitoring = true
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                if path.status == .satisfied, self.wasOffline { self.request() }
                self.wasOffline = path.status != .satisfied
            }
        }
        monitor.start(queue: .global(qos: .utility))
    }
}

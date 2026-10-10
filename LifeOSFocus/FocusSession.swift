import Foundation
import FocusExperience
import FocusSync
import Integrations

/// The signed-in Focus app for one account: the shared per-account focus
/// session, plus the sync that sends its sessions to the account LifeOS
/// also reads.
@MainActor @Observable
final class FocusSession {
    let account: FocusAccountSession
    private var sync: FocusSync?

    var owner: String { account.owner }

    init(owner: String, inMemory: Bool = false) {
        var syncRef: FocusSync?
        account = FocusAccountSession(owner: owner, inMemory: inMemory, sessionSaved: {
            if let syncRef { Task { await syncRef.run() } }
        })
        if !inMemory, let url = FocusConfig.supabaseURL, let key = FocusConfig.supabaseAnonKey {
            sync = FocusSync(context: account.container.mainContext, remote: SupabaseREST(baseURL: url, anonKey: key),
                             owner: owner, session: { KeychainAuthSessionStore().load() })
        }
        syncRef = sync
    }

    /// Up and down, then the caller re-reads the store.
    func syncNow() async { await sync?.run() }

    /// The account is going away: end anything running, leave nothing behind.
    func close() { account.close() }
}

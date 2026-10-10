import Foundation
import SwiftData
import FocusExperience
import FocusSync
import Integrations
import Persistence
import Soundscape

/// Everything a signed-in Focus app runs: its store, the session model, and
/// the sync that sends sessions to the account LifeOS also reads.
@MainActor @Observable
final class FocusSession {
    let owner: String
    let container: ModelContainer
    let model: FocusSessionModel
    var request: FocusLauncher.Request?
    private let sync: FocusSync?

    init(owner: String, inMemory: Bool = false) {
        self.owner = owner
        // The Focus app's own store, in its own sandbox. Same schema as
        // LifeOS, so FocusStore and FocusSync work unchanged.
        container = (try? LifeOSContainer.make(inMemory: inMemory)) ?? (try! LifeOSContainer.make(inMemory: true))
        if !inMemory, let url = FocusConfig.supabaseURL, let key = FocusConfig.supabaseAnonKey {
            sync = FocusSync(context: container.mainContext, remote: SupabaseREST(baseURL: url, anonKey: key),
                             owner: owner, session: { KeychainAuthSessionStore().load() })
        } else {
            sync = nil
        }
        let sync = self.sync
        // Weather and recovery arrive in slice 3c; until then the composer
        // works without them, as it does whenever an input is missing.
        model = FocusSessionModel(hooks: FocusHooks(
            gatherInputs: { _ in FocusInputs() },
            sessionSaved: { if let sync { Task { await sync.run() } } },
            heartRate: nil))
    }

    func open(mood: Mood?) { request = FocusLauncher.Request(mood: mood) }

    func syncNow() { if let sync { Task { await sync.run() } } }
}

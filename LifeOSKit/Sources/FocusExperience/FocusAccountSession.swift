#if os(iOS)
import Foundation
import SwiftData
import Persistence
import Soundscape

/// One account's focus in an app that can switch accounts: its own store, its
/// own settings (and so its own record of a running session), one-tap starts,
/// and a clean close when the account goes away.
///
/// Scoped the way LifeOS scopes everything (`LifeOSContainer.make(for:)`), so
/// a second account on the same phone never sees, or uploads, the first
/// account's sessions.
@MainActor @Observable
public final class FocusAccountSession {
    public let owner: String
    public let container: ModelContainer
    public let defaults: UserDefaults
    public let model: FocusSessionModel
    /// Set to open the setup sheet; nil when it is closed.
    public var request: FocusLauncher.Request?

    /// `notifies: false` only where there is no app to post to (tests).
    public init(owner: String, base: URL? = nil, inMemory: Bool = false, notifies: Bool = true,
                sessionSaved: @escaping @MainActor () -> Void) {
        self.owner = owner
        defaults = Self.defaults(for: owner)
        if inMemory {
            container = try! LifeOSContainer.make(inMemory: true)
        } else if let scoped = try? LifeOSContainer.make(for: UserScope(id: owner), base: base) {
            container = scoped
        } else {
            // A store that cannot open (a schema change without a default,
            // a full disk) still lets the person focus; nothing is kept.
            print("FocusAccountSession: store for \(owner) did not open; running in memory")
            container = try! LifeOSContainer.make(inMemory: true)
        }
        // Weather and recovery arrive in a later slice; the composer works
        // without them, as it does whenever an input is missing.
        model = FocusSessionModel(defaults: defaults, notifies: notifies, hooks: FocusHooks(
            gatherInputs: { _ in FocusInputs() }, sessionSaved: sessionSaved, heartRate: nil))
    }

    /// One tap: the mood's last settings, straight into a session. No mood
    /// means the last mood used.
    public func quickStart(_ mood: Mood?) async {
        let mood = mood ?? model.preferences.lastMood
        await model.start(model.preferences.setup(for: mood), inputs: FocusInputs(), context: container.mainContext)
    }

    public func openSetup(mood: Mood? = nil) { request = FocusLauncher.Request(mood: mood) }

    /// The account is going away (signed out, refused, switched). A running
    /// session is ended and recorded as the time it was, sound and bells
    /// stop, and nothing is left for the next account to resume.
    public func close() {
        if case .running = model.stage { model.end() }
        if case .summary = model.stage { model.dismissSummary() }
        ActiveFocusSession.clear(from: defaults)
        request = nil
    }

    static func suiteName(for owner: String) -> String { "ai.lifeos.focus.\(owner)" }
    static func defaults(for owner: String) -> UserDefaults { UserDefaults(suiteName: suiteName(for: owner)) ?? .standard }
}
#endif

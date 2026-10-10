#if os(iOS)
import Testing
import Foundation
import SwiftData
import Persistence
import Soundscape
@testable import FocusExperience

/// A per-account focus session: its own store and settings, one-tap starts,
/// and a clean close when the account goes away.
@MainActor
struct FocusAccountSessionTests {
    /// Settings that start silent, so no audio engine runs in the test.
    private func silentPreferences(for owner: String) {
        let defaults = FocusAccountSession.defaults(for: owner)
        defaults.removePersistentDomain(forName: FocusAccountSession.suiteName(for: owner))
        var preferences = FocusPreferences()
        for mood in Mood.allCases {
            var setup = FocusSetup.standard(for: mood)
            setup.source = .silence
            preferences.remember(setup)
        }
        preferences.save(to: defaults, key: FocusSessionModel.preferencesKey)
    }

    @Test func twoAccountsDoNotShareSessions() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("focus-accounts-\(UUID())")
        let a = FocusAccountSession(owner: "a-\(UUID())", base: base, notifies: false, sessionSaved: {})
        try FocusStore(context: a.container.mainContext).record(mood: "focus", source: "silence", startedAt: .now,
            endedAt: .now, focusedSeconds: 600, blocksCompleted: 1, projectTaskID: nil)
        let b = FocusAccountSession(owner: "b-\(UUID())", base: base, notifies: false, sessionSaved: {})
        #expect(try FocusStore(context: b.container.mainContext).recent().isEmpty)
        #expect(try FocusStore(context: a.container.mainContext).recent().count == 1)
    }

    @Test func quickStartRunsTheMoodsLastSetup() async {
        let owner = "quick-\(UUID())"
        silentPreferences(for: owner)
        let session = FocusAccountSession(owner: owner, inMemory: true, notifies: false, sessionSaved: {})
        await session.quickStart(.relax)
        #expect(session.model.stage == .running)
        #expect(session.model.setup.mood == .relax)
        session.close()
    }

    @Test func closeEndsARunningSessionAndForgetsIt() async throws {
        let owner = "close-\(UUID())"
        silentPreferences(for: owner)
        var saved = 0
        let session = FocusAccountSession(owner: owner, inMemory: true, notifies: false, sessionSaved: { saved += 1 })
        await session.quickStart(.focus)
        #expect(ActiveFocusSession.load(from: session.defaults) != nil)
        session.close()
        #expect(!session.model.isPresented)
        #expect(ActiveFocusSession.load(from: session.defaults) == nil)
        #expect(saved == 1)
        #expect(try FocusStore(context: session.container.mainContext).recent().count == 1)
    }
}
#endif

#if os(iOS)
import Testing
import Foundation
import SwiftData
import Persistence
import Soundscape
@testable import FocusExperience

@MainActor
struct FocusHooksTests {
    @Test func sessionSavedHookRunsOnEnd() async throws {
        let container = try LifeOSContainer.make(inMemory: true)
        defer { withExtendedLifetime(container) {} }
        var saved = 0
        let hooks = FocusHooks(gatherInputs: { _ in FocusInputs() }, sessionSaved: { saved += 1 }, heartRate: nil)
        let model = FocusSessionModel(defaults: UserDefaults(suiteName: "focus.hooks.\(UUID())")!, notifies: false, hooks: hooks)
        var setup = FocusSetup.standard(for: .focus)
        setup.source = .silence
        await model.start(setup, inputs: FocusInputs(), context: container.mainContext)
        model.end()
        #expect(saved == 1)
    }
}
#endif

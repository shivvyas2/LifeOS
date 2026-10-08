import Testing
import Foundation
@testable import Soundscape

@Suite struct ActiveFocusSessionTests {
    @Test func aSessionSurvivesBeingSavedAndCleared() {
        let defaults = UserDefaults(suiteName: "ActiveFocusSessionTests-\(UUID())")!
        #expect(ActiveFocusSession.load(from: defaults) == nil)
        let start = Date(timeIntervalSince1970: 2_000_000)
        var timer = FocusTimer(plan: .countdown(1200), startedAt: start)
        timer.pause(at: start.addingTimeInterval(60))
        let session = ActiveFocusSession(setup: FocusSetup.standard(for: .relax), source: .silence, timer: timer,
                                         startedAt: start, taskID: UUID(), taskTitle: "Write")
        session.save(to: defaults)
        #expect(ActiveFocusSession.load(from: defaults) == session)
        ActiveFocusSession.clear(from: defaults)
        #expect(ActiveFocusSession.load(from: defaults) == nil)
    }
}

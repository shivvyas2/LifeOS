#if DEBUG
import Foundation
import SwiftData
import Persistence
import Integrations

/// Runs only from the isolated design preview, using disposable suites and an in-memory store.
@MainActor enum ActivityRecorderChecks {
    static func run() async -> String {
        let suite = "almanac.recorder.checks.\(UUID().uuidString)"
        let otherSuite = suite + ".other"
        let defaults = UserDefaults(suiteName: suite)!
        let otherDefaults = UserDefaults(suiteName: otherSuite)!
        defer { defaults.removePersistentDomain(forName: suite); otherDefaults.removePersistentDomain(forName: otherSuite) }
        var results: [String] = []
        func check(_ condition: Bool, _ name: String) { results.append("\(condition ? "PASS" : "FAIL"): \(name)") }
        do {
            let container = try LifeOSContainer.make(inMemory: true)
            let context = container.mainContext
            let recorder = ActivityRecorder(defaults: defaults, liveActivitiesEnabled: false)
            recorder.attach(context); recorder.saveToHealth = false
            await recorder.start()
            check(recorder.isRunning && recorder.timer != nil, "Timer starts without Health access")
            let id = recorder.timer?.id
            recorder.togglePause()
            let paused = recorder.timer?.elapsed()
            check(recorder.isPaused && recorder.timer?.elapsed(at: .now.addingTimeInterval(600)) == paused, "Paused time stays fixed")
            recorder.togglePause()
            check(recorder.isRunning, "Resume keeps the activity")
            let restored = ActivityRecorder(defaults: defaults, liveActivitiesEnabled: false)
            restored.attach(context)
            check(restored.timer?.id == id && restored.isRunning && !restored.busy, "Timer-only draft restores without Health recovery")
            let other = ActivityRecorder(defaults: otherDefaults, liveActivitiesEnabled: false)
            other.attach(context)
            check(other.timer == nil, "Other account cannot see the draft")
            await restored.finish()
            check(restored.saved && !restored.healthSaved, "Finish saves locally without claiming a Health save")
            await restored.finish()
            check(try context.fetchCount(FetchDescriptor<WorkoutRecord>()) == 1, "Repeated save creates one workout")
            let afterSave = ActivityRecorder(defaults: defaults, liveActivitiesEnabled: false)
            afterSave.attach(context)
            check(afterSave.timer == nil, "Saved draft is cleared")
            recorder.deactivate()
            await recorder.start()
            check(recorder.timer == nil && !recorder.hasSession, "Account transition stops recording and rejects late starts")
            restored.deactivate(); other.deactivate(); afterSave.deactivate()
        } catch { results.append("FAIL: \(error)") }
        return results.joined(separator: "\n")
    }
}
#endif

#if DEBUG
import Foundation
import SwiftData
import Persistence
import Integrations
import AppSurfaces

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
            recorder.birthDate = { Calendar.current.date(from: DateComponents(year: 1996, month: 6, day: 1)) }
            _ = try MetricsStore(context: context).upsert(date: .now) { $0.whoopRecoveryPct = 80; $0.whoopSleepPerformancePct = 90 }
            recorder.attach(context); recorder.saveToHealth = false
            await recorder.start()
            check(recorder.isRunning && recorder.timer != nil, "Timer starts without Health access")
            check(recorder.capacity?.percent == 82 && recorder.readout?.batteryPercent == 82, "Capacity comes from today's recovery at start")
            let base = Date.now.addingTimeInterval(-30)
            for second in 0..<30 { recorder.sensor.onReading?(140, base.addingTimeInterval(Double(second))) }
            check(recorder.readout?.heartRate == 140 && recorder.readout?.zone == 3 && (recorder.readout?.effort ?? 0) > 0, "Readings yield zone and effort")
            let beforePauseEffort = recorder.readout?.effort
            let beforePauseHeartRate = recorder.readout?.heartRate
            let id = recorder.timer?.id
            recorder.togglePause()
            for offset in 1...5 { recorder.sensor.onReading?(140, base.addingTimeInterval(30 + Double(offset))) }
            check(recorder.readout?.effort == beforePauseEffort && recorder.readout?.heartRate == beforePauseHeartRate, "Paused readings accrue nothing")
            let paused = recorder.timer?.elapsed()
            check(recorder.isPaused && recorder.timer?.elapsed(at: .now.addingTimeInterval(600)) == paused, "Paused time stays fixed")
            recorder.togglePause()
            check(recorder.isRunning, "Resume keeps the activity")
            let resumeEffort = recorder.readout?.effort
            let resumeDate = Date.now
            recorder.sensor.onReading?(175, resumeDate)
            let afterFirstResumeReading = recorder.readout?.effort
            recorder.sensor.onReading?(175, resumeDate.addingTimeInterval(1))
            check(afterFirstResumeReading == resumeEffort && (recorder.readout?.effort ?? 0) > (afterFirstResumeReading ?? 0),
                  "First reading after resume credits nothing, the second accrues")
            let restored = ActivityRecorder(defaults: defaults, liveActivitiesEnabled: false)
            restored.birthDate = recorder.birthDate
            restored.attach(context)
            check(restored.timer?.id == id && restored.isRunning && !restored.busy, "Timer-only draft restores without Health recovery")
            check(restored.capacity?.percent == 82 && (restored.readout?.effort ?? 0) > 0, "Draft restores capacity and effort")
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
            defaults.set(UUID().uuidString, forKey: "lastHeartRateSensorID")
            let remembering = ActivityRecorder(defaults: defaults, liveActivitiesEnabled: false)
            check(remembering.sensor.rememberedPeripheralID != nil, "Remembered sensor survives relaunch")
            let stranger = ActivityRecorder(defaults: otherDefaults, liveActivitiesEnabled: false)
            check(stranger.sensor.rememberedPeripheralID == nil, "Other account has no remembered sensor")
            remembering.sensor.forget()
            check(defaults.string(forKey: "lastHeartRateSensorID") == nil, "Forget clears the remembered sensor")
            remembering.deactivate(); stranger.deactivate()
            recorder.deactivate()
            await recorder.start()
            check(recorder.timer == nil && !recorder.hasSession, "Account transition stops recording and rejects late starts")
            restored.deactivate(); other.deactivate(); afterSave.deactivate()
        } catch { results.append("FAIL: \(error)") }
        return results.joined(separator: "\n")
    }
}
#endif

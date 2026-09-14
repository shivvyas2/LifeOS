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
            let lifter = ActivityRecorder(defaults: UserDefaults(suiteName: suite + ".lift")!, liveActivitiesEnabled: false)
            lifter.attach(context); lifter.saveToHealth = false; lifter.selection = .strength
            await lifter.start()
            check(lifter.source == .phone && lifter.reps == 0 && lifter.setIndex == 1, "A phone strength session starts at set 1 with zero reps")
            lifter.addRep(); lifter.addRep(); lifter.nextSet(); lifter.addRep()
            check(lifter.reps == 1 && lifter.setIndex == 2 && lifter.completedSets == [2] && lifter.readout?.reps == 1, "Manual reps and sets count on the phone")
            var toAPhone = WatchPacket(sentAt: .now); toAPhone.reps = 40
            lifter.receiveWatchPacket(try WatchWire.encode(toAPhone))
            check(lifter.reps == 1, "A watch packet never reaches a phone session")
            await lifter.finish()
            let lifted = try context.fetch(FetchDescriptor<WorkoutRecord>()).first { $0.activityName == "Strength" }
            check(lifted?.sets == [2, 1], "Finishing writes the sets, current set included")
            // The strength check shares the walk's context; remove its row so a
            // later count of all workouts still reflects only the walk's saves.
            if let lifted { context.delete(lifted); try context.save() }
            lifter.deactivate()
            UserDefaults(suiteName: suite + ".lift")?.removePersistentDomain(forName: suite + ".lift")
            let waiter = ActivityRecorder(defaults: UserDefaults(suiteName: suite + ".watch")!, liveActivitiesEnabled: false)
            waiter.attach(context); waiter.saveToHealth = true
            waiter.watchAvailable = { true }; waiter.watchHandoffTimeout = 0.5
            // Health saving on is what offers the workout to the watch, and the
            // hand-off now asks for Health access before it does: grant it here
            // rather than raising a permission sheet an unattended run can
            // never answer. Once the recorder is waiting on a watch that will
            // never answer, take the toggle off again so the fall-through does
            // not re-run the phone's own Health path either.
            waiter.healthAuthorizationForHandoff = { true }
            let handoff = Task { await waiter.start() }
            var spins = 0
            while waiter.source != .watch, spins < 200 { spins += 1; try? await Task.sleep(for: .milliseconds(5)) }
            check(waiter.notice == ActivityRecorder.waitingForWatch, "The wait for the watch says so")
            waiter.saveToHealth = false
            await handoff.value
            check(waiter.source == .phone && waiter.hasSession && waiter.notice?.contains("did not answer") == true, "A watch that does not answer falls back to the phone")
            waiter.deactivate()
            UserDefaults(suiteName: suite + ".watch")?.removePersistentDomain(forName: suite + ".watch")
            // A watch-owned workout the phone only mirrors: the draft is the
            // only way into that path without a watch, and it is the one place
            // the packet decoder and the local save meet.
            let watchSuite = suite + ".watchdraft"
            let watchDefaults = UserDefaults(suiteName: watchSuite)!
            ActivityRecorder.seedWatchDraft(into: watchDefaults)
            let mirrored = ActivityRecorder(defaults: watchDefaults, liveActivitiesEnabled: false)
            mirrored.watch = nil
            mirrored.birthDate = recorder.birthDate
            mirrored.attach(context)
            var recoveries = 0
            while mirrored.busy, recoveries < 400 { recoveries += 1; try? await Task.sleep(for: .milliseconds(5)) }
            check(mirrored.source == .watch && mirrored.selection == .strength && mirrored.hasSession,
                  "A watch draft restores as a watch session")
            check(mirrored.saveToHealth, "A watch draft leaves Health saving on")
            var unknown = WatchPacket(sentAt: .now); unknown.v = 99; unknown.reps = 40; unknown.heartRate = 200
            unknown.heartRateAt = .now
            mirrored.receiveWatchPacket(try WatchWire.encode(unknown))
            check(mirrored.reps == 0 && mirrored.heartRate == nil, "A packet with an unknown version changes nothing")
            var live = WatchPacket(sentAt: .now); live.reps = 3; live.setIndex = 1; live.heartRate = 130; live.heartRateAt = .now
            mirrored.receiveWatchPacket(try WatchWire.encode(live))
            check(mirrored.reps == 3 && mirrored.heartRate == 130 && mirrored.readout?.reps == 3,
                  "A current-version packet carries reps and heart rate through")
            await mirrored.finish()
            let fromWatch = try context.fetch(FetchDescriptor<WorkoutRecord>()).first { $0.activityName == "Strength" }
            check(fromWatch?.sets == [3] && mirrored.saved && !mirrored.healthSaved,
                  "Finishing a watch session writes the local record and its sets")
            if let fromWatch { context.delete(fromWatch); try context.save() }
            mirrored.deactivate()
            watchDefaults.removePersistentDomain(forName: watchSuite)
            let phoneOnly = ActivityRecorder(defaults: UserDefaults(suiteName: suite + ".phoneonly")!, liveActivitiesEnabled: false)
            phoneOnly.attach(context); phoneOnly.saveToHealth = false
            phoneOnly.watchAvailable = { true }; phoneOnly.watchHandoffTimeout = 0.5
            await phoneOnly.start()
            check(phoneOnly.source == .phone && phoneOnly.hasSession && phoneOnly.notice == nil, "Health saving off keeps the session on the phone")
            phoneOnly.deactivate()
            UserDefaults(suiteName: suite + ".phoneonly")?.removePersistentDomain(forName: suite + ".phoneonly")
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

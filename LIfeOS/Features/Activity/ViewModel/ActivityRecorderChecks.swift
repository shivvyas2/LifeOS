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
            let follower = ActivityRecorder(defaults: UserDefaults(suiteName: suite + ".follower")!, liveActivitiesEnabled: false)
            follower.attach(context); follower.saveToHealth = false
            await follower.start(following: (id: "abcdefghijk", split: "pull", title: "A pull day", channel: "A channel"))
            let followerID = "almanac:\(follower.timer!.id.uuidString)"
            await follower.finish()
            var followerFetch = FetchDescriptor<WorkoutRecord>(predicate: #Predicate { $0.externalID == followerID })
            followerFetch.fetchLimit = 1
            let followed = try context.fetch(followerFetch).first
            check(followed?.activityName == "Walk" && followed?.videoID == "abcdefghijk" && followed?.split == "pull",
                  "Finishing stamps the video and split")
            if let followed { context.delete(followed); try context.save() }
            follower.deactivate()
            UserDefaults(suiteName: suite + ".follower")?.removePersistentDomain(forName: suite + ".follower")
            // A start that never reaches a session must not leave the video
            // behind for whatever the person starts next. Health authorisation
            // cannot be refused unattended, so the bail is engineered from the
            // hand-off: the app goes away while the watch is being offered the
            // workout, which is exactly the shape of a start that sets the
            // video and then returns with no timer.
            let stale = ActivityRecorder(defaults: UserDefaults(suiteName: suite + ".stale")!, liveActivitiesEnabled: false)
            stale.attach(context); stale.saveToHealth = true
            stale.watchAvailable = { true }; stale.watchHandoffTimeout = 5
            stale.healthAuthorizationForHandoff = { true }
            let bail = Task { await stale.start(following: (id: "abcdefghijk", split: "pull", title: "A pull day", channel: "A channel")) }
            var offers = 0
            while stale.source != .watch, offers < 400 { offers += 1; try? await Task.sleep(for: .milliseconds(5)) }
            // Not `deactivate()`, which discards and would clear the fields by
            // itself: this is the start alone failing, with the state it left.
            stale.active = false
            await bail.value
            let bailed = !stale.hasSession && stale.pendingVideoID == "abcdefghijk"
            stale.active = true; stale.saveToHealth = false; stale.selection = .walk
            await stale.start()
            let staleID = "almanac:\(stale.timer?.id.uuidString ?? "none")"
            await stale.finish()
            var staleFetch = FetchDescriptor<WorkoutRecord>(predicate: #Predicate { $0.externalID == staleID })
            staleFetch.fetchLimit = 1
            let plain = try context.fetch(staleFetch).first
            check(bailed && stale.pendingVideoID == nil && stale.pendingSplit == nil && stale.following == nil
                  && plain?.activityName == "Walk" && plain?.videoID == nil && plain?.split == nil,
                  "A failed start does not stamp the next session")
            if let plain { context.delete(plain); try context.save() }
            stale.deactivate()
            UserDefaults(suiteName: suite + ".stale")?.removePersistentDomain(forName: suite + ".stale")
            // A workout started on the wrist is not the video the player was
            // queuing. `adoptMirroredSession` needs a real HKWorkoutSession,
            // which no harness can build, so the clearing it calls is
            // exercised directly, on both sides of its one guard.
            let wrist = ActivityRecorder(defaults: UserDefaults(suiteName: suite + ".wrist")!, liveActivitiesEnabled: false)
            wrist.attach(context); wrist.saveToHealth = true
            wrist.watchAvailable = { true }; wrist.watchHandoffTimeout = 5
            wrist.healthAuthorizationForHandoff = { true }
            let offer = Task { await wrist.start(following: (id: "abcdefghijk", split: "pull", title: "A pull day", channel: "A channel")) }
            var waits = 0
            while wrist.source != .watch, waits < 400 { waits += 1; try? await Task.sleep(for: .milliseconds(5)) }
            // Mid hand-off `busy` is true: the session the watch is about to
            // send back is this player's, so the video must survive.
            wrist.clearPendingVideoIfIdle()
            let keptDuringHandoff = wrist.pendingVideoID == "abcdefghijk" && wrist.following != nil
            wrist.active = false
            await offer.value
            wrist.active = true
            // Idle: nothing here asked for the session, so it follows nothing.
            wrist.clearPendingVideoIfIdle()
            check(keptDuringHandoff && wrist.pendingVideoID == nil && wrist.pendingSplit == nil && wrist.following == nil,
                  "A wrist-started session carries no stale video")
            wrist.deactivate()
            UserDefaults(suiteName: suite + ".wrist")?.removePersistentDomain(forName: suite + ".wrist")
            // A relaunch mid-video: the draft carries the video, so the record
            // the restored session finally writes still names it.
            let restoredSuite = suite + ".videodraft"
            let restoredDefaults = UserDefaults(suiteName: restoredSuite)!
            ActivityRecorder.seedDraft(into: restoredDefaults, videoID: "zyxwvutsrqp", split: "legs",
                                       title: "A legs day", channel: "A channel")
            let resumed = ActivityRecorder(defaults: restoredDefaults, liveActivitiesEnabled: false)
            resumed.watch = nil
            resumed.birthDate = recorder.birthDate
            resumed.attach(context)
            let resumedID = "almanac:\(resumed.timer?.id.uuidString ?? "none")"
            await resumed.finish()
            var resumedFetch = FetchDescriptor<WorkoutRecord>(predicate: #Predicate { $0.externalID == resumedID })
            resumedFetch.fetchLimit = 1
            let resumedRow = try context.fetch(resumedFetch).first
            check(resumed.following?.title == "A legs day" && resumedRow?.videoID == "zyxwvutsrqp"
                  && resumedRow?.split == "legs", "A restored draft keeps its video")
            if let resumedRow { context.delete(resumedRow); try context.save() }
            resumed.deactivate()
            restoredDefaults.removePersistentDomain(forName: restoredSuite)
            recorder.deactivate()
            await recorder.start()
            check(recorder.timer == nil && !recorder.hasSession, "Account transition stops recording and rejects late starts")
            restored.deactivate(); other.deactivate(); afterSave.deactivate()
        } catch { results.append("FAIL: \(error)") }
        return results.joined(separator: "\n")
    }
}
#endif

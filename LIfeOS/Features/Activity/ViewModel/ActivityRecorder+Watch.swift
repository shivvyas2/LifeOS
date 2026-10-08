import Foundation
import HealthKit
import Integrations
import AppSurfaces

/// The half of the recorder that belongs to a watch-owned session: offering
/// the workout to the wrist, adopting the session that comes back, and the
/// packets and commands that flow while it runs. The phone never creates a
/// `HKWorkoutSession` here; the watch owns it and saves it to Health.
extension ActivityRecorder {
    static let waitingForWatch = "Asking your Apple Watch…"

    /// The hand-off from spec 3.1. Returns true when `start()` must stop:
    /// the watch has taken the workout, or this recorder was deactivated
    /// while waiting for it.
    ///
    /// Only offered when this workout is meant for Health, since the watch
    /// writes it there; a person who turned Health saving off keeps the phone.
    /// No timer starts until the watch answers, so nothing counts a session
    /// the watch may never take, and `busy` keeps Start showing "Starting…".
    func handOffToWatch() async -> Bool {
        guard saveToHealth, watchAvailable(), let watch, !watch.hasSession else { return false }
        // Ask on the phone first. Authorization is shared with the paired
        // watch, so without this the first prompt a person ever sees is on the
        // wrist, while the phone is already counting down its ten seconds.
        guard await healthAuthorizationForHandoff() else { return false }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = selection.healthType
        configuration.locationType = .unknown
        source = .watch
        notice = Self.waitingForWatch
        try? await WatchSessionBridge.startWatchApp(configuration)
        let deadline = Date.now.addingTimeInterval(watchHandoffTimeout)
        while Date.now < deadline, watch.session.map(WatchSessionBridge.isFocus) ?? true, active {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard active else { return true }
        if let mirrored = watch.session, !WatchSessionBridge.isFocus(mirrored) {
            // `adoptMirroredSession` normally ran from the bridge's callback as
            // the session arrived; adopt here if that callback was missed.
            if timer == nil { adoptMirroredSession(mirrored) }
            if notice == Self.waitingForWatch { notice = nil }
            return true
        }
        source = .phone
        notice = "Apple Watch did not answer. Recording on iPhone."
        return false
    }

    /// The watch's session arrived: either the hand-off answered, or the
    /// person started on the watch. Adopt it; never run two sessions.
    func adoptMirroredSession(_ mirrored: HKWorkoutSession) {
        guard active else { return }
        if hasSession, source == .phone {
            notice = "Already recording on iPhone; the watch session was ignored."
            // `discard`, not `end`: `end` on the wrist means finish and save,
            // which would leave a stub workout in Health beside this one.
            watch?.end(after: .discard); return
        }
        // A finished, saved timer is the resting "Done" screen. A workout
        // started on the wrist now is a new one, not a continuation of it.
        let isDifferentWorkout = timer.map { abs($0.startedAt.timeIntervalSince(mirrored.startDate ?? $0.startedAt)) > 1 } ?? false
        if timer == nil || saved || isDifferentWorkout {
            // Before the fresh timer, because the record this session
            // eventually saves reads these three.
            clearPendingVideoIfIdle()
            watchSessionID = nil; lastWatchPacketAt = nil; swingCount = nil; swingMoments = []; peakWristRotation = nil
            // A hand-off in flight (`busy`) already set up this workout's
            // badminton session in `start()`; only a workout begun on the
            // wrist arrives without one, and the watch scores that itself.
            if !busy { badminton = nil }
            saved = false; healthSaved = false
            selection = ActivityCatalog.type(healthRawValue: mirrored.workoutConfiguration.activityType.rawValue) ?? ActivityCatalog.other
            recents.record(selection)
            zones = HeartRateZones(birthDate: birthDate()); capacity = loadCapacity()
            effort = EffortAccumulator(); lastReadingAt = nil
            energy = nil; distance = nil; heartRate = nil; heartRateDate = nil
            // Start where the watch started, not where the mirroring landed,
            // and take the id of any Live Activity the background launch put
            // on screen before this timer existed, so it is updated in place.
            timer = ActivitySessionState(id: watch?.placeholderSessionID ?? UUID(),
                                         activity: selection.name, at: mirrored.startDate ?? .now)
            if selection.countsReps { reps = 0; setIndex = 1; completedSets = [] }
            else { reps = nil; setIndex = nil; completedSets = [] }
        }
        source = .watch
        // Whichever path built the timer, it now owns the Live Activity: end
        // any placeholder or leftover card keyed to another session.
        endStrayLiveActivities()
        watch?.clearPlaceholder()
        // The watch streams its own heart rate; a strap as well would double
        // every reading into the effort accrual.
        sensor.stopStreaming()
        // The watch saves this workout to Health, so the draft must not claim
        // a Health session of the phone's own for a relaunch to recover.
        recordingHealth = false
        persist()
        // The profile rides along: the watch read its own copy once, when the
        // workout started, and may never have received the phone's at all.
        watch?.send(.configure, maxHeartRate: zones?.maxHeartRate, badminton: badminton, athlete: athlete)
    }

    func mirroredStateChanged(_ state: HKWorkoutSessionState, at date: Date) {
        guard active, source == .watch else { return }
        switch state {
        case .paused: timer?.pause(at: date)
        case .running: timer?.resume(at: date); lastReadingAt = nil
        case .stopped, .ended:
            timer?.finish(at: date); persist()
            Task { await self.saveFinished() }
        default: break
        }
        persist()
    }

    /// Raw bytes from the mirrored session, or from the demo feed, which
    /// speaks the same wire. Anything not a current-version packet is
    /// dropped without changing state.
    func receiveWatchPacket(_ data: Data) {
        guard active, hasSession, source == .watch || source == .demo, let packet = WatchWire.packet(from: data) else { return }
        guard packet.sentAt >= Date.now.addingTimeInterval(-30), packet.sentAt <= Date.now.addingTimeInterval(60),
              lastWatchPacketAt.map({ packet.sentAt > $0 }) ?? true else { return }
        if let owner = packet.ownerID, owner != SurfaceCoordinator.shared.workoutOwnerID {
            watch?.end()
            source = .phone; discard()
            notice = "This Watch workout belongs to another account."
            return
        }
        if let id = packet.sessionID {
            guard watchSessionID == nil || watchSessionID == id else { return }
            watchSessionID = id
        }
        lastWatchPacketAt = packet.sentAt
        if selection.name == "Badminton" {
            if let count = packet.swingCount, (0...SwingAnalysis.eventLimit).contains(count) {
                let added = count - (swingCount ?? 0)
                if added > 0 {
                    swingMoments += Array(repeating: packet.sentAt, count: min(added, 10))
                    swingMoments.removeAll { packet.sentAt.timeIntervalSince($0) > 180 }
                }
                swingCount = count
            }
            if let peak = packet.peakWristRotation, peak.isFinite, (0...100).contains(peak) { peakWristRotation = peak }
            if let session = packet.badminton, session.isValid { badminton = session }
        }
        if let elapsed = packet.elapsed, let paused = packet.paused {
            timer?.synchronize(elapsed: elapsed, paused: paused, at: packet.sentAt)
        }
        if let distance = packet.distanceMeters, distance.isFinite, distance >= 0 { self.distance = distance }
        // A reading refreshes through `receiveHeartRate`; only a packet without
        // one has to refresh here, so each packet refreshes exactly once. The
        // counts are applied before that reading, so the one refresh carries
        // this packet's reps rather than the previous packet's.
        let refreshes = packet.heartRate != nil && packet.heartRateAt != nil && isRunning
        if let energy = packet.energyKcal { self.energy = energy }
        if selection.countsReps {
            if let value = packet.reps { reps = value }
            if let value = packet.setIndex { setIndex = value }
            if let value = packet.completedSets { completedSets = value }
        }
        if let bpm = packet.heartRate, let at = packet.heartRateAt { receiveHeartRate(bpm, at: at) }
        if !refreshes { persistReading(at: packet.sentAt) }
    }

    /// Manual counting. On the watch source the command echoes back in the
    /// next packet; on the phone it counts here.
    func addRep() {
        guard hasSession, selection.countsReps else { return }
        if source == .watch { watch?.send(.addRep); return }
        reps = (reps ?? 0) + 1
        persist()
    }
    /// The correction to `addRep`, on the same two paths. Zero is the floor:
    /// a session cannot have counted fewer reps than none. An unknown count
    /// stays unknown, because turning a dash into a 0 would claim no reps
    /// were done.
    func removeRep() {
        guard hasSession, selection.countsReps else { return }
        if source == .watch { watch?.send(.removeRep); return }
        if let current = reps { reps = max(0, current - 1) }
        persist()
    }
    // MARK: - Staying in step with the watch

    /// True while the phone is timing a watch workout it can no longer reach.
    /// The controls switch to ending the workout here instead of asking the
    /// watch, which would fail or wait forever.
    var watchUnreachable: Bool { source == .watch && hasSession && !(watch?.hasSession ?? false) }

    func watchDisconnected() {
        guard active, source == .watch, hasSession else { return }
        busy = false
        notice = "Apple Watch disconnected. It keeps recording and syncs when it is back in range. You can also end the workout on iPhone."
        persist()
    }

    /// Ends a watch workout on the phone alone, for when the watch cannot be
    /// reached. The record is saved under the watch workout's own id, so the
    /// watch's summary, whenever it arrives, enriches this row instead of
    /// adding a second one.
    func finishOnPhone() async {
        guard active, source == .watch, hasSession, timer?.phase != .finished else { return }
        timer?.finish()
        watch?.end()
        notice = "Ended on iPhone. Your watch's full workout replaces this one when it syncs."
        persist()
        await saveFinished()
    }

    /// The watch finished a workout and its summary was imported, perhaps
    /// long after the mirrored session dropped. If that is the workout this
    /// phone is still timing, close the timer: the row already exists, so
    /// there is nothing left to save, only a stale clock to stop.
    func watchWorkoutImported(_ summary: WatchWorkoutSummary) {
        guard active, source == .watch, hasSession, let timer else { return }
        let sameWorkout = watchSessionID == summary.id
            || (watchSessionID == nil && abs(timer.startedAt.timeIntervalSince(summary.startedAt)) < 2)
        guard sameWorkout else { return }
        self.timer?.finish(at: summary.endedAt)
        if let session = summary.badminton, session.isValid { badminton = session }
        watch?.end()
        liveActivity.end()
        saved = true
        defaults.removeObject(forKey: Self.draftKey)
        busy = false; error = nil
        notice = "Your watch workout synced."
        onSaved?()
    }

    /// One rally won, from the phone's scoreboard. On the watch source the
    /// tap goes to the wrist and comes back in the next packet, as `addRep`
    /// does, so the two devices never hold different scores.
    func scoreRally(_ side: BadmintonSide) {
        guard hasSession, selection.name == Self.badminton else { return }
        if source == .watch { watch?.send(side == .us ? .scoreUs : .scoreThem); return }
        var session = badminton ?? BadmintonSession()
        guard session.kind == .match, !(session.score?.isOver ?? true) else { return }
        session.record(side)
        badminton = session
        persist()
    }
    func undoRally() {
        guard hasSession, badminton?.score?.rallies.isEmpty == false else { return }
        if source == .watch { watch?.send(.undoRally); return }
        badminton?.undo()
        persist()
    }

    func nextSet() {
        guard hasSession, selection.countsReps else { return }
        if source == .watch { watch?.send(.nextSet); return }
        completedSets.append(reps ?? 0)
        reps = 0; setIndex = (setIndex ?? 1) + 1
        persist()
    }
}

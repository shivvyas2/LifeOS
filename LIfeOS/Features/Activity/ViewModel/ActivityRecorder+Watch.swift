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
        while Date.now < deadline, watch.session == nil, active {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard active else { return true }
        if let mirrored = watch.session {
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
            watchSessionID = nil; lastWatchPacketAt = nil
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
        watch?.send(.configure, maxHeartRate: zones?.maxHeartRate)
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

    /// Raw bytes from the mirrored session. Anything not a current-version
    /// packet is dropped without changing state.
    func receiveWatchPacket(_ data: Data) {
        guard active, hasSession, source == .watch, let packet = WatchWire.packet(from: data) else { return }
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
    func nextSet() {
        guard hasSession, selection.countsReps else { return }
        if source == .watch { watch?.send(.nextSet); return }
        completedSets.append(reps ?? 0)
        reps = 0; setIndex = (setIndex ?? 1) + 1
        persist()
    }
}

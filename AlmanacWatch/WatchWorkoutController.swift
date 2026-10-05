import Foundation
import HealthKit
import CoreMotion
import AppSurfaces
import Motion
import WatchConnectivity
import WatchKit

/// Runs the workout on the wrist and mirrors it to the phone. Heart rate and
/// energy come from the live builder; reps from `RepCounter` on device
/// motion for strength. Packets go out once a second and on every rep.
@MainActor @Observable
final class WatchWorkoutController: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    enum State { case idle, starting, running, paused, ending }

    private(set) var state: State = .idle
    private(set) var activityName = ""
    /// The catalog entry for the running session, nil when idle.
    private(set) var activity: ActivityType?
    private(set) var startedAt: Date?
    /// The workout clock, kept the way `ActivitySessionState` keeps it on the
    /// phone: a pause banks the time so far, a resume starts a new run. The
    /// screen reads both so its timer does not count through a pause.
    private(set) var accumulated: TimeInterval = 0
    private(set) var runningSince: Date?
    private(set) var heartRate: Int?
    private(set) var energyKcal: Double?
    private(set) var distanceMeters: Double?
    private(set) var heartHistory: [Double] = []
    private(set) var result: String?
    private(set) var workoutID = UUID()
    private(set) var ownerID: String?
    var accountID: String?
    var athlete: ActivityAthleteProfile?
    var needsAthleteSetup = false
    private var pendingStart: HKWorkoutConfiguration?
    private var swingDetector = BadmintonSwingDetector()
    private(set) var swingAnalysis: SwingAnalysis?
    private(set) var motionStatus = "Swing analysis is off"
    private var analyzesSwings: Bool { activityName == "Badminton" && swingAnalysis != nil }
    /// The match or practice this badminton workout is. Set by the phone's
    /// setup when it starts the workout; on a workout started on the wrist it
    /// stays nil until the first point is scored, so a session nobody scored
    /// is never saved as an unfinished match.
    private(set) var badminton: BadmintonSession?
    var onFinished: ((WatchWorkoutSummary) -> Void)?
    private var heartbeat: Task<Void, Never>?
    private var mirrorAttemptAt: Date = .distantPast
    private var finishing = false
    private var checkpointKey: String { "watch.workout.checkpoint.v1" }
    private struct Checkpoint: Codable {
        var id: UUID; var ownerID: String?; var startedAt: Date
        var reps: Int?; var setIndex: Int?; var completedSets: [Int]
        var swingAnalysis: SwingAnalysis?
        /// Optional, so a checkpoint written before scoring existed decodes.
        var badminton: BadmintonSession?
    }
    var elapsed: TimeInterval { accumulated + (runningSince.map { max(0, Date.now.timeIntervalSince($0)) } ?? 0) }
    var freshHeartRate: Int? {
        guard let heartRateAt, Date.now.timeIntervalSince(heartRateAt) <= 20 else { return nil }
        return heartRate
    }
    var layout: WatchWorkoutLayout { .forActivity(activity ?? ActivityCatalog.other) }
    private(set) var reps: Int?
    private(set) var setIndex: Int?
    private(set) var completedSets: [Int] = []
    private(set) var maxHeartRate: Int?
    private(set) var mirroringFailed = false
    /// Set when the workout could not be written to Health, so the screen can
    /// say so rather than ending in silence.
    private(set) var lastError: String?
    var isStrength: Bool { activity?.countsReps == true }

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private let motion = CMMotionManager()
    private var counter = RepCounter()
    /// Taps on "+1", kept apart from the counter so the next automatic rep
    /// adds to them instead of overwriting them.
    private var manualReps = 0
    /// When the most recent heart rate was actually measured, not when it was sent.
    private var heartRateAt: Date?
    private var lastPacketAt: Date = .distantPast

    /// A first launch from iPhone can arrive before WatchConnectivity has
    /// delivered the account binding. Give that handshake a short head start.
    func startFromPhone(_ configuration: HKWorkoutConfiguration) {
        Task {
            for _ in 0..<15 where accountID == nil {
                try? await Task.sleep(for: .milliseconds(200))
            }
            start(configuration, asksForSetup: false)
        }
    }

    func start(type: HKWorkoutActivityType) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = type
        configuration.locationType = .unknown
        start(configuration)
    }

    /// Only swing analysis reads the athlete profile, so only a badminton
    /// start tapped on the Watch pauses for setup. A start sent from the
    /// phone never waits on a form nobody is looking at.
    func start(_ configuration: HKWorkoutConfiguration, asksForSetup: Bool = true) {
        guard state == .idle else { return }
        if asksForSetup, athlete == nil, configuration.activityType == .badminton {
            pendingStart = configuration; needsAthleteSetup = true; return
        }
        // Synchronous, before the Task: the authorization prompt can take a
        // while and a second Start tap must not open a second session.
        state = .starting
        lastError = nil; result = nil
        workoutID = UUID(); ownerID = accountID
        activity = ActivityCatalog.type(healthRawValue: configuration.activityType.rawValue) ?? ActivityCatalog.other
        activityName = activity?.name ?? "Other"
        swingAnalysis = activityName == "Badminton" && athlete?.canAnalyzeSwings == true ? SwingAnalysis(profile: athlete) : nil
        swingDetector = BadmintonSwingDetector(profile: athlete)
        Task {
            do {
                let quantities: [HKQuantityTypeIdentifier] = [.heartRate, .activeEnergyBurned, .distanceWalkingRunning, .distanceCycling, .distanceSwimming, .distanceWheelchair, .distanceRowing, .distancePaddleSports, .distanceSkatingSports, .distanceDownhillSnowSports]
                let share: Set<HKSampleType> = Set(quantities.compactMap { HKQuantityType.quantityType(forIdentifier: $0) } + [HKObjectType.workoutType()])
                var read = Set<HKObjectType>(share)
                read.insert(HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!)
                try await healthStore.requestAuthorization(toShare: share, read: read)
                // Recording has not begun yet. A first-time linking response
                // that arrived during authorization can own this new session.
                if ownerID == nil { ownerID = accountID }
                guard ownerID == nil || ownerID == accountID else { throw CancellationError() }
                guard healthStore.authorizationStatus(for: .workoutType()) == .sharingAuthorized else {
                    throw NSError(domain: "Almanac", code: 1, userInfo: [NSLocalizedDescriptionKey: "Allow workout access in Health to start recording."])
                }
                if let birthday = try? healthStore.dateOfBirthComponents(),
                   let birth = Calendar.current.date(from: birthday),
                   let age = Calendar.current.dateComponents([.year], from: birth, to: .now).year, (13...100).contains(age) {
                    maxHeartRate = Int((208 - 0.7 * Double(age)).rounded())
                }
                let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
                let builder = session.associatedWorkoutBuilder()
                builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
                session.delegate = self; builder.delegate = self
                self.session = session; self.builder = builder
                let started = Date.now
                startedAt = started; accumulated = 0; runningSince = started
                session.startActivity(with: started)
                try await builder.beginCollection(at: started)
                guard self.session === session else { return }
                await connectMirror()
                guard self.session === session else { return }
                state = .running
                if isStrength { reps = 0; setIndex = 1; completedSets = []; manualReps = 0; startMotion() }
                if analyzesSwings { startMotion() }
                persistCheckpoint(); startHeartbeat()
                sendPacket(force: true)
            } catch {
                lastError = error.localizedDescription
                // A throw after `startActivity` leaves a live session behind.
                // Detach it first so no late delegate callback can put this
                // controller back into `.running` on a session that is gone.
                session?.delegate = nil
                builder?.delegate = nil
                session?.end()
                builder?.discardWorkout()
                stopMotion()
                self.session = nil; self.builder = nil
                startedAt = nil; accumulated = 0; runningSince = nil
                activityName = ""; activity = nil; mirroringFailed = false
                state = .idle
            }
        }
    }

    /// Adopts a HealthKit session that is still active when watchOS
    /// relaunches the app (`WatchAppDelegate.handleActiveWorkoutRecovery()`),
    /// e.g. after the system killed the app mid-workout. Wired the same way
    /// `start(_:)` is wired to `handle(_:)`.
    func recover() async {
        guard state == .idle else { return }
        // Synchronous, before the first await, for the same reason as
        // `start`: a second recovery call must not race this into a second
        // attempt.
        state = .starting
        lastError = nil
        guard let recovered = try? await healthStore.recoverActiveWorkoutSession() else {
            state = .idle
            return
        }
        let session = recovered
        let builder = recovered.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: session.workoutConfiguration)
        session.delegate = self; builder.delegate = self
        self.session = session; self.builder = builder
        activity = ActivityCatalog.type(healthRawValue: session.workoutConfiguration.activityType.rawValue) ?? ActivityCatalog.other
        activityName = activity?.name ?? "Other"
        let started = recovered.startDate ?? .now
        startedAt = started
        let saved = UserDefaults.standard.data(forKey: checkpointKey).flatMap { try? JSONDecoder().decode(Checkpoint.self, from: $0) }
        if let saved, abs(saved.startedAt.timeIntervalSince(started)) < 1 {
            workoutID = saved.id; ownerID = saved.ownerID
            reps = saved.reps; setIndex = saved.setIndex; completedSets = saved.completedSets
            swingAnalysis = saved.swingAnalysis
            swingAnalysis?.interrupted = true
            badminton = saved.badminton.flatMap { $0.isValid ? $0 : nil }
            swingDetector = BadmintonSwingDetector(restoring: swingAnalysis)
        } else { workoutID = UUID(); ownerID = accountID }
        if let ownerID, ownerID != accountID { discard(); return }
        if recovered.state == .stopped || recovered.state == .ended {
            state = .ending
            accumulated = max(0, builder.elapsedTime)
            await finish(at: .now)
            return
        }
        await connectMirror()
        // The builder restores active time without counting disconnected pauses.
        accumulated = max(0, builder.elapsedTime)
        state = recovered.state == .paused ? .paused : .running
        if state == .running { runningSince = .now }
        // Resume from the persisted rep tally; raw motion is never stored.
        if isStrength {
            setIndex = setIndex ?? 1; manualReps = reps ?? 0
            startMotion()
        }
        if analyzesSwings { startMotion() }
        startHeartbeat(); sendPacket(force: true)
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }
    func end() {
        guard state != .ending, let session else { return }
        if let since = runningSince { accumulated += max(0, Date.now.timeIntervalSince(since)) }
        runningSince = nil
        state = .ending
        stopMotion()
        sendPacket(force: true)
        session.stopActivity(with: .now)
    }
    /// The phone refused this session, or the person discarded it there:
    /// throw the workout away rather than writing a stub into Health. The
    /// delegate comes off first, so no late `.ended` re-enters the teardown.
    func discard() {
        guard state != .ending, let session else { return }
        state = .ending
        stopMotion()
        session.delegate = nil
        builder?.delegate = nil
        builder?.discardWorkout()
        session.end()
        resetAfterEnd()
    }
    func completeAthleteSetup(_ profile: ActivityAthleteProfile) {
        guard profile.isValid else { return }
        athlete = profile
        if let accountID { profile.save(to: UserDefaults(suiteName: "watch.athlete.\(accountID)") ?? .standard) }
        needsAthleteSetup = false
        if let pendingStart { self.pendingStart = nil; start(pendingStart) }
    }
    /// Dismissing setup still starts the workout, just without swings.
    func skipAthleteSetup() {
        guard let pendingStart else { return }
        self.pendingStart = nil
        start(pendingStart, asksForSetup: false)
    }
    func accountChanged(to next: String?) {
        athlete = next.flatMap { UserDefaults(suiteName: "watch.athlete.\($0)") }.flatMap { ActivityAthleteProfile.load(from: $0) }
        needsAthleteSetup = false; pendingStart = nil
        accountID = next
        if let ownerID, ownerID != next, state != .idle { discard() }
    }
    func retrySave() { Task { await finish(at: .now) } }
    func addRep() {
        guard isStrength, state == .running || state == .paused else { return }
        manualReps += 1
        reps = counter.reps + manualReps
        sendPacket(force: true)
    }
    /// A correction, not a count. It spends the manual tally first and then
    /// offsets the automatic one, so the number on the wrist is what falls by
    /// one, and it never falls below zero.
    func removeRep() {
        guard isStrength, state == .running || state == .paused else { return }
        // Nothing to correct while the count is unknown, which is where a
        // recovered session starts: a dash must not become a zero.
        guard let current = reps else { return }
        manualReps = max(-counter.reps, manualReps - 1)
        reps = max(0, current - 1)
        sendPacket(force: true)
    }
    func nextSet() {
        guard isStrength, state == .running || state == .paused else { return }
        completedSets.append(reps ?? 0)
        counter.reset(); manualReps = 0; reps = 0
        setIndex = (setIndex ?? 1) + 1
        sendPacket(force: true)
    }

    #if DEBUG
    func loadPreview(_ name: String) {
        activity = ActivityCatalog.type(named: name) ?? ActivityCatalog.other
        activityName = activity!.name; state = .paused
        accumulated = 32 * 60 + 20; startedAt = .now.addingTimeInterval(-accumulated)
        heartRate = 142; heartRateAt = .now; energyKcal = 216; maxHeartRate = 190
        heartHistory = [112, 118, 115, 124, 131, 129, 136, 145, 139, 142]
        distanceMeters = activity?.tracksDistance == true ? 4820 : nil
        if isStrength { reps = 8; setIndex = 3; completedSets = [12, 10] }
    }
    #endif

    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { motionStatus = "Motion sensor unavailable"; swingAnalysis?.interrupted = true; return }
        motionStatus = "Wrist motion · experimental"
        counter.reset()
        motion.deviceMotionUpdateInterval = 1.0 / 50.0
        // `.main` is the main-thread queue, so the handler is already on the
        // main actor: `assumeIsolated` keeps every sample in order rather than
        // scattering 50 hops a second through `Task`.
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                guard let data else { self.motionStatus = "Motion unavailable · check permission"; self.swingAnalysis?.interrupted = true; return }
                guard self.state == .running else { return }
                let acceleration = data.userAcceleration
                if self.analyzesSwings {
                    let rotation = data.rotationRate; let q = data.attitude.quaternion
                    let t = self.elapsed
                    let sample = BadmintonSwingDetector.Sample(time: t,
                        acceleration: sqrt(acceleration.x * acceleration.x + acceleration.y * acceleration.y + acceleration.z * acceleration.z),
                        rotation: sqrt(rotation.x * rotation.x + rotation.y * rotation.y + rotation.z * rotation.z),
                        frame: WristFrame(t: 0, x: q.x, y: q.y, z: q.z, w: q.w),
                        // The watch's y axis runs along the forearm, so its
                        // rotation rate is the forehand or backhand twist.
                        twist: rotation.y)
                    let detected = self.swingDetector.add(sample)
                    // Publish at event boundaries; the 5-second checkpoint also snapshots coverage.
                    if detected { self.swingAnalysis = self.swingDetector.analysis; self.sendPacket(force: true) }
                } else if self.counter.add(RepCounter.Sample(t: data.timestamp, x: acceleration.x, y: acceleration.y, z: acceleration.z)) {
                    self.reps = self.counter.reps + self.manualReps
                    self.sendPacket(force: true)
                }
            }
        }
    }
    private func stopMotion() { motion.stopDeviceMotionUpdates() }

    /// The one teardown path: everything the next workout must not inherit.
    private func resetAfterEnd() {
        stopMotion()
        heartbeat?.cancel(); heartbeat = nil
        UserDefaults.standard.removeObject(forKey: checkpointKey)
        session = nil; builder = nil
        startedAt = nil; accumulated = 0; runningSince = nil
        heartRate = nil; heartRateAt = nil; energyKcal = nil; distanceMeters = nil; heartHistory = []
        reps = nil; setIndex = nil; completedSets = []; manualReps = 0
        counter.reset(); swingAnalysis = nil; swingDetector = BadmintonSwingDetector(); motionStatus = "Swing analysis is off"
        badminton = nil
        activityName = ""; activity = nil; mirroringFailed = false; maxHeartRate = nil
        state = .idle
    }

    private func sendPacket(force: Bool) {
        guard let session, state != .idle else { return }
        let now = Date.now
        guard force || now.timeIntervalSince(lastPacketAt) >= 1 else { return }
        lastPacketAt = now
        persistCheckpoint()
        var packet = WatchPacket(sentAt: now)
        packet.sessionID = workoutID; packet.ownerID = ownerID
        packet.elapsed = elapsed; packet.paused = state != .running
        packet.distanceMeters = distanceMeters
        packet.heartRate = heartRate; packet.heartRateAt = heartRate == nil ? nil : heartRateAt
        packet.energyKcal = energyKcal
        if let swingAnalysis { packet.swingCount = swingAnalysis.events.count; packet.peakWristRotation = swingAnalysis.peakRotation }
        packet.badminton = badminton
        if isStrength {
            packet.reps = reps; packet.setIndex = setIndex
            packet.completedSets = completedSets.isEmpty ? nil : completedSets
        }
        guard let data = try? WatchWire.encode(packet) else { return }
        session.sendToRemoteWorkoutSession(data: data) { [weak self] success, _ in
            Task { @MainActor in
                guard let self, self.session === session else { return }
                self.mirroringFailed = !success
            }
        }
    }

    private func handle(_ envelope: PhoneCommandEnvelope) {
        guard Date.now.timeIntervalSince(envelope.sentAt) < 15,
              envelope.sentAt <= Date.now.addingTimeInterval(60) else { return }
        switch envelope.command {
        case .configure:
            if let value = envelope.maxHeartRate, (80...240).contains(value) { maxHeartRate = value }
            // The phone's setup only lands on a badminton workout that has no
            // score yet: a late configure must never wipe points already won.
            if let setup = envelope.badminton, setup.isValid, activityName == "Badminton",
               badminton?.score?.rallies.isEmpty ?? true {
                badminton = setup; sendPacket(force: true)
            }
        case .pause: pause()
        case .resume: resume()
        case .end: end()
        case .discard: discard()
        case .nextSet: nextSet()
        case .addRep: addRep()
        case .removeRep: removeRep()
        case .scoreUs: score(.us)
        case .scoreThem: score(.them)
        case .undoRally: undoRally()
        }
    }

    /// One rally won. The first point on an unscored badminton workout makes
    /// it a singles match; the phone's setup, when there was one, already did.
    func score(_ side: BadmintonSide) {
        guard activityName == "Badminton", state == .running || state == .paused else { return }
        var session = badminton ?? BadmintonSession()
        guard session.kind == .match, !(session.score?.isOver ?? true) else { return }
        session.record(side)
        badminton = session
        WKInterfaceDevice.current().play(session.score?.isOver == true ? .success : .click)
        sendPacket(force: true)
    }
    func undoRally() {
        guard badminton?.score?.rallies.isEmpty == false else { return }
        badminton?.undo()
        sendPacket(force: true)
    }

    private func persistCheckpoint() {
        guard let startedAt else { return }
        if analyzesSwings { swingAnalysis = swingDetector.analysis }
        let value = Checkpoint(id: workoutID, ownerID: ownerID, startedAt: startedAt, reps: reps, setIndex: setIndex, completedSets: completedSets, swingAnalysis: swingAnalysis, badminton: badminton)
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: checkpointKey) }
    }
    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self, self.state != .idle else { return }
                if self.mirroringFailed && Date.now.timeIntervalSince(self.mirrorAttemptAt) >= 20 { await self.connectMirror() }
                self.sendPacket(force: true)
            }
        }
    }
    private func connectMirror() async {
        guard let session, ownerID != nil else { mirroringFailed = true; return }
        mirrorAttemptAt = .now
        do { try await session.startMirroringToCompanionDevice(); mirroringFailed = false }
        catch { mirroringFailed = true }
    }
    private func finish(at date: Date) async {
        guard !finishing else { return }
        finishing = true
        defer { finishing = false }
        // Captured before the first suspension: `self.builder` and
        // `self.session` can be nil by the time these awaits resume.
        let builder = self.builder
        let session = self.session
        guard let builder, let session else { return }
        // `try?` on the collection call alone: a builder recovered after its
        // session already ended throws here, and letting that skip the finish
        // would drop a workout HealthKit is still holding. A throw from the
        // save itself is the one worth telling the person about.
        try? await builder.endCollection(at: date)
        do {
            guard let saved = try await builder.finishWorkout() else { throw CocoaError(.fileWriteUnknown) }
            if let ownerID, let startedAt {
                onFinished?(WatchWorkoutSummary(id: workoutID, ownerID: ownerID, activity: activityName,
                    startedAt: startedAt, endedAt: saved.endDate, elapsed: saved.duration,
                    energyKcal: energyKcal, distanceMeters: distanceMeters,
                    sets: isStrength ? completedSets + [reps ?? 0] : [], healthWorkoutID: saved.uuid, swingAnalysis: swingAnalysis,
                    badminton: badminton))
            }
            result = ownerID == nil ? "Workout saved to Apple Health." : "Workout saved. Your iPhone syncs when available."
            lastError = nil
            session.end()
            resetAfterEnd()
        } catch {
            lastError = "Could not save to Health. Retry to keep this workout."
            state = .ending
        }
    }

    private func collect(_ identifiers: [HKQuantityTypeIdentifier]) {
        guard let builder else { return }
        for identifier in identifiers {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier), let stats = builder.statistics(for: type) else { continue }
            switch identifier {
            case .heartRate:
                heartRate = stats.mostRecentQuantity().map { Int($0.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))) }
                let measuredAt = stats.mostRecentQuantityDateInterval()?.end
                if measuredAt != heartRateAt, let heartRate { heartHistory.append(Double(heartRate)); heartHistory = Array(heartHistory.suffix(30)) }
                heartRateAt = heartRate == nil ? nil : measuredAt
            case .activeEnergyBurned:
                energyKcal = stats.sumQuantity()?.doubleValue(for: .kilocalorie())
            case .distanceWalkingRunning, .distanceCycling, .distanceSwimming, .distanceWheelchair, .distanceRowing, .distancePaddleSports, .distanceSkatingSports, .distanceDownhillSnowSports:
                distanceMeters = stats.sumQuantity()?.doubleValue(for: .meter())
            default: break
            }
        }
        sendPacket(force: false)
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            switch toState {
            case .running:
                self.state = .running
                if self.runningSince == nil { self.runningSince = date }
            case .paused:
                self.manualReps = self.reps ?? 0; self.counter.reset()
                self.swingDetector.interrupt()
                self.state = .paused
                if let since = self.runningSince { self.accumulated += max(0, date.timeIntervalSince(since)) }
                self.runningSince = nil
            case .stopped:
                if let since = self.runningSince { self.accumulated += max(0, date.timeIntervalSince(since)) }
                self.runningSince = nil; self.state = .ending; self.stopMotion()
                await self.finish(at: date)
            case .ended: self.resetAfterEnd()
            default: break
            }
            self.sendPacket(force: true)
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            self.lastError = error.localizedDescription; self.resetAfterEnd()
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            for item in data { if let envelope = WatchWire.command(from: item) { self.handle(envelope) } } }
    }
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let identifiers = collectedTypes.compactMap { ($0 as? HKQuantityType).map { HKQuantityTypeIdentifier(rawValue: $0.identifier) } }
        Task { @MainActor in
            guard self.builder === workoutBuilder else { return }
            self.collect(identifiers)
        }
    }
}

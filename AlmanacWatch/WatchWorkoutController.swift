import Foundation
import HealthKit
import CoreMotion
import AppSurfaces
import Motion

/// Runs the workout on the wrist and mirrors it to the phone. Heart rate and
/// energy come from the live builder; reps from `RepCounter` on device
/// motion for strength. Packets go out once a second and on every rep.
@MainActor @Observable
final class WatchWorkoutController: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    enum State { case idle, starting, running, paused, ending }
    static let startable: [(name: String, type: HKWorkoutActivityType)] = [
        ("Walk", .walking), ("Run", .running), ("Cycle", .cycling), ("Strength", .traditionalStrengthTraining), ("Yoga", .yoga), ("Other", .other)]

    private(set) var state: State = .idle
    private(set) var activityName = ""
    private(set) var startedAt: Date?
    private(set) var heartRate: Int?
    private(set) var energyKcal: Double?
    private(set) var reps: Int?
    private(set) var setIndex: Int?
    private(set) var completedSets: [Int] = []
    private(set) var maxHeartRate: Int?
    private(set) var mirroringFailed = false
    /// Set when the workout could not be written to Health, so the screen can
    /// say so rather than ending in silence.
    private(set) var lastError: String?
    var isStrength: Bool { session?.workoutConfiguration.activityType == .traditionalStrengthTraining }
    var elapsed: TimeInterval { startedAt.map { Date.now.timeIntervalSince($0) } ?? 0 }

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

    func start(type: HKWorkoutActivityType) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = type
        configuration.locationType = .unknown
        start(configuration)
    }

    func start(_ configuration: HKWorkoutConfiguration) {
        guard state == .idle else { return }
        // Synchronous, before the Task: the authorization prompt can take a
        // while and a second Start tap must not open a second session.
        state = .starting
        lastError = nil
        activityName = Self.startable.first { $0.type == configuration.activityType }?.name ?? "Other"
        Task {
            do {
                let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType.quantityType(forIdentifier: .heartRate)!, HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!]
                let read: Set<HKObjectType> = [HKObjectType.workoutType(), HKQuantityType.quantityType(forIdentifier: .heartRate)!, HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!]
                try await healthStore.requestAuthorization(toShare: share, read: read)
                let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
                let builder = session.associatedWorkoutBuilder()
                builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
                session.delegate = self; builder.delegate = self
                self.session = session; self.builder = builder
                let started = Date.now
                startedAt = started
                session.startActivity(with: started)
                try await builder.beginCollection(at: started)
                mirroringFailed = false
                do {
                    try await session.startMirroringToCompanionDevice()
                } catch {
                    mirroringFailed = true
                }
                state = .running
                if isStrength { reps = 0; setIndex = 1; completedSets = []; manualReps = 0; startMotion() }
                sendPacket(force: true)
            } catch {
                // A throw after `startActivity` leaves a live session behind.
                // Detach it first so no late delegate callback can put this
                // controller back into `.running` on a session that is gone.
                session?.delegate = nil
                builder?.delegate = nil
                session?.end()
                builder?.discardWorkout()
                stopMotion()
                self.session = nil; self.builder = nil
                startedAt = nil; activityName = ""; mirroringFailed = false
                state = .idle
            }
        }
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }
    func end() {
        guard state != .ending, let session else { return }
        state = .ending
        stopMotion()
        session.stopActivity(with: .now)
    }
    func addRep() {
        guard isStrength, state == .running || state == .paused else { return }
        manualReps += 1
        reps = counter.reps + manualReps
        sendPacket(force: true)
    }
    func nextSet() {
        guard isStrength, state == .running || state == .paused else { return }
        completedSets.append(reps ?? 0)
        counter.reset(); manualReps = 0; reps = 0
        setIndex = (setIndex ?? 1) + 1
        sendPacket(force: true)
    }

    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        counter.reset()
        motion.deviceMotionUpdateInterval = 1.0 / 50.0
        // `.main` is the main-thread queue, so the handler is already on the
        // main actor: `assumeIsolated` keeps every sample in order rather than
        // scattering 50 hops a second through `Task`.
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            MainActor.assumeIsolated {
                guard self.state == .running else { return }
                let acceleration = data.userAcceleration
                if self.counter.add(RepCounter.Sample(t: data.timestamp, x: acceleration.x, y: acceleration.y, z: acceleration.z)) {
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
        session = nil; builder = nil
        startedAt = nil; heartRate = nil; heartRateAt = nil; energyKcal = nil
        reps = nil; setIndex = nil; completedSets = []; manualReps = 0
        counter.reset()
        activityName = ""; mirroringFailed = false; maxHeartRate = nil
        state = .idle
    }

    private func sendPacket(force: Bool) {
        guard let session, state != .idle else { return }
        let now = Date.now
        guard force || now.timeIntervalSince(lastPacketAt) >= 1 else { return }
        lastPacketAt = now
        var packet = WatchPacket(sentAt: now)
        packet.heartRate = heartRate; packet.heartRateAt = heartRate == nil ? nil : heartRateAt
        packet.energyKcal = energyKcal
        if isStrength {
            packet.reps = reps; packet.setIndex = setIndex
            packet.completedSets = completedSets.isEmpty ? nil : completedSets
        }
        guard let data = try? WatchWire.encode(packet) else { return }
        session.sendToRemoteWorkoutSession(data: data) { _, _ in }
    }

    private func handle(_ envelope: PhoneCommandEnvelope) {
        switch envelope.command {
        case .configure: maxHeartRate = envelope.maxHeartRate
        case .pause: pause()
        case .resume: resume()
        case .end: end()
        case .nextSet: nextSet()
        case .addRep: addRep()
        }
    }

    private func finish(at date: Date) async {
        // Captured before the first suspension: `self.builder` and
        // `self.session` can be nil by the time these awaits resume.
        let builder = self.builder
        let session = self.session
        guard let builder, let session else { return }
        do {
            try await builder.endCollection(at: date)
            _ = try await builder.finishWorkout()
        } catch {
            lastError = "Could not save to Health"
        }
        session.end()
    }

    private func collect(_ identifiers: [HKQuantityTypeIdentifier]) {
        guard let builder else { return }
        for identifier in identifiers {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier), let stats = builder.statistics(for: type) else { continue }
            switch identifier {
            case .heartRate:
                heartRate = stats.mostRecentQuantity().map { Int($0.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))) }
                heartRateAt = heartRate == nil ? nil : stats.mostRecentQuantityDateInterval()?.end
            case .activeEnergyBurned:
                energyKcal = stats.sumQuantity()?.doubleValue(for: .kilocalorie())
            default: break
            }
        }
        sendPacket(force: false)
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            switch toState {
            case .running: self.state = .running
            case .paused: self.state = .paused
            case .stopped: await self.finish(at: date)
            case .ended: self.resetAfterEnd()
            default: break
            }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.resetAfterEnd() }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in for item in data { if let envelope = WatchWire.command(from: item) { self.handle(envelope) } } }
    }
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let identifiers = collectedTypes.compactMap { ($0 as? HKQuantityType).map { HKQuantityTypeIdentifier(rawValue: $0.identifier) } }
        Task { @MainActor in self.collect(identifiers) }
    }
}

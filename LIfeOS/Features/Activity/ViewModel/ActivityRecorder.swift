import Foundation
import HealthKit
import SwiftData
import Persistence
import Integrations
import AppSurfaces

enum RecordedActivity: String, CaseIterable, Identifiable {
    case walk = "Walk", run = "Run", cycle = "Cycle", strength = "Strength", yoga = "Yoga", other = "Other"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .walk: "figure.walk"
        case .run: "figure.run"
        case .cycle: "figure.outdoor.cycle"
        case .strength: "dumbbell"
        case .yoga: "figure.yoga"
        case .other: "figure.mixed.cardio"
        }
    }
    var healthType: HKWorkoutActivityType {
        switch self {
        case .walk: .walking
        case .run: .running
        case .cycle: .cycling
        case .strength: .traditionalStrengthTraining
        case .yoga: .yoga
        case .other: .other
        }
    }
}

@MainActor @Observable
final class ActivityRecorder: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    var selection: RecordedActivity = .walk
    var saveToHealth = HKHealthStore.isHealthDataAvailable()
    private(set) var timer: ActivitySessionState?
    private(set) var busy = false
    private(set) var saved = false
    private(set) var healthSaved = false
    private(set) var energy: Double?
    private(set) var distance: Double?
    private(set) var heartRate: Double?
    private(set) var heartRateDate: Date?
    private(set) var capacity: Capacity?
    private(set) var readout: LiveSessionReadout?
    var error: String?
    var notice: String?
    let sensor = LiveHeartRateSensor()
    /// Injected so previews and checks can fix an age without a profile.
    var birthDate: () -> Date? = { ProfileStore.load().birthDate }
    /// Whether the WHOOP cloud account is connected; decides auto-pairing.
    var whoopConnected: () -> Bool = { false }
    private var zones: HeartRateZones?
    private var effort = EffortAccumulator()
    private var lastReadingAt: Date?
    private var lastDraftWriteAt: Date?
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var context: ModelContext?
    private let defaults: UserDefaults
    private var active = true
    private let liveActivity = WorkoutLiveActivityController()
    private let liveActivitiesEnabled: Bool
    private var collectionEnded = false
    private var finishing = false
    private var recordingHealth = false
    private static let draftKey = "activeWorkoutDraft"
    var onSaved: (() -> Void)?
    var zonesAvailable: Bool { zones != nil }

    private struct Draft: Codable {
        var timer: ActivitySessionState
        var healthSaved: Bool
        var recordsHealth: Bool?
        var energy: Double?
        var distance: Double?
        var capacity: Capacity?
        var effortLoad: Double?
    }

    init(defaults: UserDefaults = .currentAccount, liveActivitiesEnabled: Bool = true) {
        self.defaults = defaults
        self.liveActivitiesEnabled = liveActivitiesEnabled
        super.init()
        sensor.onReading = { [weak self] bpm, date in self?.receiveHeartRate(bpm, at: date) }
    }
    var hasSession: Bool { timer != nil && !saved }
    var isRunning: Bool { timer?.phase == .running }
    var isPaused: Bool { timer?.phase == .paused }

    func attach(_ context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
        guard let data = defaults.data(forKey: Self.draftKey),
              let draft = try? JSONDecoder().decode(Draft.self, from: data) else { return }
        recordingHealth = draft.recordsHealth == true
        saveToHealth = recordingHealth
        timer = draft.timer; healthSaved = draft.healthSaved; energy = draft.energy; distance = draft.distance
        capacity = draft.capacity; effort = EffortAccumulator(load: draft.effortLoad ?? 0)
        zones = HeartRateZones(birthDate: birthDate())
        selection = RecordedActivity(rawValue: draft.timer.activity) ?? .other
        persist()
        notice = "Your activity timer was restored. Reconnect a sensor for live heart rate."
        if recordingHealth, HKHealthStore.isHealthDataAvailable(), !healthSaved {
            busy = true
            healthStore.recoverActiveWorkoutSession { [weak self] recovered, _ in
                Task { @MainActor in
                    guard let self, self.active else { recovered?.end(); return }
                    self.busy = false
                    guard let recovered else {
                        self.notice = "Timer restored. This activity can be saved to Almanac; its Health session is no longer available."
                        return
                    }
                    self.session = recovered
                    self.builder = recovered.associatedWorkoutBuilder()
                    self.collectionEnded = self.builder?.endDate != nil
                    recovered.delegate = self; self.builder?.delegate = self
                    self.builder?.dataSource = HKLiveWorkoutDataSource(healthStore: self.healthStore, workoutConfiguration: recovered.workoutConfiguration)
                    if recovered.state == .paused { self.timer?.pause() }
                    if recovered.state == .stopped || recovered.state == .ended {
                        self.timer?.finish(at: self.builder?.endDate ?? .now); self.notice = "Your interrupted activity is ready to save."
                    }
                    self.persist()
                }
            }
        }
    }

    func start(at started: Date = .now) async {
        guard active, !busy, !hasSession else { return }
        busy = true; error = nil; saved = false; healthSaved = false; collectionEnded = false
        zones = HeartRateZones(birthDate: birthDate())
        capacity = loadCapacity()
        effort = EffortAccumulator(); lastReadingAt = nil
        sensor.prepareForSession(whoopConnected: whoopConnected())
        recordingHealth = saveToHealth
        defer { busy = false }
        do {
            if saveToHealth {
                let types: Set<HKSampleType> = [HKObjectType.workoutType(), .quantityType(forIdentifier: .heartRate)!,
                    .quantityType(forIdentifier: .activeEnergyBurned)!, .quantityType(forIdentifier: .distanceWalkingRunning)!,
                    .quantityType(forIdentifier: .distanceCycling)!]
                try await healthStore.requestAuthorization(toShare: types, read: types)
                guard active else { return }
                guard healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
                    error = "Allow workout saving in Health, or turn off Save to Apple Health to use the timer."
                    return
                }
                let configuration = HKWorkoutConfiguration()
                configuration.activityType = selection.healthType
                configuration.locationType = .unknown
                let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
                self.session = session
                let builder = session.associatedWorkoutBuilder()
                self.builder = builder
                session.delegate = self; builder.delegate = self
                builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
                timer = ActivitySessionState(activity: selection.rawValue, at: started)
                session.startActivity(with: started)
                try await builder.beginCollection(at: started)
                guard active else { session.end(); builder.discardWorkout(); return }
            } else {
                timer = ActivitySessionState(activity: selection.rawValue, at: started)
            }
            persist()
        } catch {
            session?.end(); builder?.discardWorkout(); session = nil; builder = nil; timer = nil
            self.error = "Could not start activity: \(error.localizedDescription)"
        }
    }
    func togglePause() {
        guard !busy else { return }
        if isRunning { timer?.pause(); session?.pause() }
        else if isPaused { timer?.resume(); session?.resume(); lastReadingAt = nil }
        persist()
    }
    func finish() async {
        guard active, !busy, timer != nil, !saved else { return }
        busy = true; error = nil
        self.timer?.finish(); persist()
        if let session, !healthSaved, session.state == .running || session.state == .paused {
            session.stopActivity(with: self.timer?.endedAt)
            // The delegate completes collection after HealthKit reaches stopped.
            return
        }
        await saveFinished()
    }
    private func saveFinished() async {
        guard active, !finishing, timer?.phase == .finished else { busy = false; return }
        finishing = true
        defer { busy = false; finishing = false }
        do {
            if let builder, !healthSaved {
                if !collectionEnded {
                    try await builder.endCollection(at: timer?.endedAt ?? .now)
                    collectionEnded = true
                }
                guard active else { return }
                let workout = try await builder.finishWorkout()
                guard active else { return }
                guard workout != nil else { throw CocoaError(.fileWriteUnknown) }
                healthSaved = true; persist(); session?.end()
            }
            guard active, let context, let timer else { return }
            let id = "almanac:\(timer.id.uuidString)"
            var fetch = FetchDescriptor<WorkoutRecord>(predicate: #Predicate { $0.externalID == id })
            fetch.fetchLimit = 1
            if try context.fetch(fetch).isEmpty {
                let row = WorkoutRecord(externalID: id, start: timer.startedAt,
                    durationMinutes: Int(timer.elapsed() / 60), activityName: timer.activity, energyKcal: energy)
                row.distanceMeters = distance
                context.insert(row)
            }
            try context.save()
            liveActivity.end()
            saved = true; defaults.removeObject(forKey: Self.draftKey)
            sensor.disconnect(); session = nil; builder = nil
            onSaved?()
        } catch {
            self.error = "Your activity is kept here. Saving failed: \(error.localizedDescription). Try Save again."
        }
    }
    func discard() {
        liveActivity.end()
        session?.delegate = nil; builder?.delegate = nil
        session?.end(); builder?.discardWorkout(); session = nil; builder = nil
        sensor.disconnect(); timer = nil; saved = false; healthSaved = false
        energy = nil; distance = nil; heartRate = nil; heartRateDate = nil
        capacity = nil; readout = nil; effort = EffortAccumulator(); lastReadingAt = nil; zones = nil; lastDraftWriteAt = nil
        error = nil; notice = nil; busy = false
        defaults.removeObject(forKey: Self.draftKey)
    }
    func deactivate() {
        active = false; discard(); context = nil; onSaved = nil
    }
    /// State changes: always write the draft and sync.
    private func persist() {
        refreshReadout()
        writeDraft()
        syncLiveActivity()
    }
    /// Readings arrive every second: always refresh and sync (the controller
    /// throttles the publish), but write the draft at most every ten seconds.
    private func persistReading(at date: Date) {
        refreshReadout()
        if lastDraftWriteAt.map({ date.timeIntervalSince($0) >= 10 }) ?? true { writeDraft(at: date) }
        syncLiveActivity()
    }
    private func writeDraft(at date: Date = .now) {
        guard active, let timer,
              let data = try? JSONEncoder().encode(Draft(timer: timer, healthSaved: healthSaved, recordsHealth: recordingHealth,
                                                         energy: energy, distance: distance, capacity: capacity, effortLoad: effort.load)) else { return }
        defaults.set(data, forKey: Self.draftKey)
        lastDraftWriteAt = date
    }
    private func syncLiveActivity() {
        guard liveActivitiesEnabled, let timer, let readout else { return }
        liveActivity.sync(readout, timer: timer, icon: selection.icon)
    }
    private func refreshReadout() {
        guard let timer else { readout = nil; return }
        readout = LiveReadoutBuilder.readout(timer: timer, heartRate: heartRate.map { Int($0) }, zones: zones, effort: effort,
                                             capacity: capacity, energyKcal: energy, distanceMeters: distance)
    }
    /// Today's row, or yesterday's while today has not synced. A week of
    /// rows behind it gives the Health path its HRV baseline.
    private func loadCapacity() -> Capacity? {
        guard let context else { return nil }
        let rows = (try? MetricsStore(context: context).metrics(from: .now.addingTimeInterval(-9 * 86400), to: .now)) ?? []
        let days = rows.map {
            RecoveryDay(date: $0.date, whoopRecoveryPct: $0.whoopRecoveryPct, whoopIsCalibrating: $0.whoopRecoveryIsCalibrating,
                        sleepPerformancePct: $0.whoopSleepPerformancePct, hrvMs: $0.hrvMs, sleepMinutes: $0.sleepMinutes)
        }
        return CapacityMath.capacity(days: days, now: .now)
    }
    private func receiveHeartRate(_ bpm: Int, at date: Date) {
        guard active, isRunning else { return }
        heartRate = Double(bpm); heartRateDate = date
        if let zones {
            effort.add(zone: zones.zone(for: bpm), seconds: EffortAccumulator.credit(previous: lastReadingAt, at: date))
        }
        lastReadingAt = date
        persistReading(at: date)
        guard let builder, healthStore.authorizationStatus(for: .quantityType(forIdentifier: .heartRate)!) == .sharingAuthorized else { return }
        let sample = HKQuantitySample(type: .quantityType(forIdentifier: .heartRate)!,
            quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: Double(bpm)), start: date, end: date)
        builder.add([sample]) { _, _ in }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                     from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor [weak self] in
            guard let self, self.active, self.session === workoutSession else { return }
            switch toState {
            case .paused: self.timer?.pause(at: date)
            case .running: self.timer?.resume(at: date)
            case .stopped:
                self.timer?.finish(at: date); self.persist()
                if self.busy { await self.saveFinished() }
            default: break
            }
            self.persist()
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            guard let self, self.active, self.session === workoutSession else { return }
            self.timer?.pause(); self.busy = false
            self.error = "Health recording stopped: \(message). Your timer is kept."
            self.persist()
        }
    }
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor [weak self] in
            guard let self, self.active, self.builder === workoutBuilder else { return }
            for type in collectedTypes {
                guard let type = type as? HKQuantityType, let stats = workoutBuilder.statistics(for: type) else { continue }
                switch type.identifier {
                case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
                    self.energy = stats.sumQuantity()?.doubleValue(for: .kilocalorie())
                case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue, HKQuantityTypeIdentifier.distanceCycling.rawValue:
                    self.distance = stats.sumQuantity()?.doubleValue(for: .meter())
                case HKQuantityTypeIdentifier.heartRate.rawValue:
                    if let bpm = stats.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
                       let date = stats.mostRecentQuantityDateInterval()?.end, date != self.heartRateDate {
                        self.heartRate = bpm; self.heartRateDate = date
                        if self.isRunning, let zones = self.zones {
                            self.effort.add(zone: zones.zone(for: Int(bpm)), seconds: EffortAccumulator.credit(previous: self.lastReadingAt, at: date))
                            self.lastReadingAt = date
                        }
                    }
                default: break
                }
            }
            self.persist()
        }
    }
}

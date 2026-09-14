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
    // The watch path in `ActivityRecorder+Watch.swift` writes this state, and
    // Swift has no setter that is internal to the module but closed to the
    // views, so these read as plain `var`. Only the recorder touches them.
    var timer: ActivitySessionState?
    private(set) var busy = false
    var saved = false
    var healthSaved = false
    var energy: Double?
    var distance: Double?
    var heartRate: Double?
    var heartRateDate: Date?
    var capacity: Capacity?
    private(set) var readout: LiveSessionReadout?
    var source: SessionSource = .phone
    var reps: Int?
    var setIndex: Int?
    var completedSets: [Int] = []
    var error: String?
    var notice: String?
    let sensor: LiveHeartRateSensor
    /// Injected so checks can simulate a watch that never answers.
    var watchAvailable: () -> Bool = { WatchSessionBridge.watchAvailable }
    var watchHandoffTimeout: TimeInterval = 10
    var watch: WatchSessionBridge? = .shared
    /// The phone asks for Health access before the watch is offered the
    /// workout, so the wrist is never the first prompt a person sees.
    /// Injected so checks can answer it without a permission sheet.
    var healthAuthorizationForHandoff: () async -> Bool = { await ActivityRecorder.authorizeWorkoutTypes() }
    /// Injected so previews and checks can fix an age without a profile.
    var birthDate: () -> Date? = { ProfileStore.load().birthDate }
    /// Whether the WHOOP cloud account is connected; decides auto-pairing.
    var whoopConnected: () -> Bool = { false }
    var zones: HeartRateZones?
    var effort = EffortAccumulator()
    var lastReadingAt: Date?
    private var lastDraftWriteAt: Date?
    let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var context: ModelContext?
    private let defaults: UserDefaults
    var active = true
    private let liveActivity = WorkoutLiveActivityController()
    private let liveActivitiesEnabled: Bool
    private var collectionEnded = false
    private var finishing = false
    var recordingHealth = false
    private static let draftKey = "activeWorkoutDraft"
    /// Everything a workout writes. The hand-off asks for the same set the
    /// phone branch does, so one grant covers both devices.
    private static let workoutTypes: Set<HKSampleType> = [HKObjectType.workoutType(), .quantityType(forIdentifier: .heartRate)!,
        .quantityType(forIdentifier: .activeEnergyBurned)!, .quantityType(forIdentifier: .distanceWalkingRunning)!,
        .quantityType(forIdentifier: .distanceCycling)!]

    /// Asks once, on the phone, and reports whether workouts may be written.
    static func authorizeWorkoutTypes(store: HKHealthStore = HKHealthStore()) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        try? await store.requestAuthorization(toShare: workoutTypes, read: workoutTypes)
        return store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }
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
        var source: SessionSource?
        var reps: Int?
        var setIndex: Int?
        var completedSets: [Int]?
    }

    init(defaults: UserDefaults = .currentAccount, liveActivitiesEnabled: Bool = true) {
        self.defaults = defaults
        self.liveActivitiesEnabled = liveActivitiesEnabled
        sensor = LiveHeartRateSensor(defaults: defaults)
        super.init()
        sensor.onReading = { [weak self] bpm, date in self?.receiveHeartRate(bpm, at: date) }
    }
    var hasSession: Bool { timer != nil && !saved }
    var isRunning: Bool { timer?.phase == .running }
    var isPaused: Bool { timer?.phase == .paused }

    func attach(_ context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
        // Only the recorder a screen actually attached listens to the bridge.
        // A throwaway instance from a re-render must not steal the callbacks
        // and then be deallocated, which would leave the live one deaf.
        watch?.onSession = { [weak self] session in self?.adoptMirroredSession(session) }
        watch?.onPacket = { [weak self] data in self?.receiveWatchPacket(data) }
        watch?.onStateChange = { [weak self] state, date in self?.mirroredStateChanged(state, at: date) }
        // A session that arrived while HealthKit was launching the app in the
        // background is already held by the bridge: replay it once the draft
        // below has been restored, whichever way this returns.
        defer { if let mirrored = watch?.session { adoptMirroredSession(mirrored) } }
        guard let data = defaults.data(forKey: Self.draftKey),
              let draft = try? JSONDecoder().decode(Draft.self, from: data) else { return }
        recordingHealth = draft.recordsHealth == true
        // A watch draft records to Health on the wrist, so `recordsHealth` is
        // false for it; reading that back as the toggle would silently turn
        // Health saving, and with it the next hand-off, off.
        saveToHealth = recordingHealth || draft.source == .watch
        timer = draft.timer; healthSaved = draft.healthSaved; energy = draft.energy; distance = draft.distance
        capacity = draft.capacity; effort = EffortAccumulator(load: draft.effortLoad ?? 0)
        source = draft.source ?? .phone; reps = draft.reps; setIndex = draft.setIndex; completedSets = draft.completedSets ?? []
        zones = HeartRateZones(birthDate: birthDate())
        selection = RecordedActivity(rawValue: draft.timer.activity) ?? .other
        persist()
        notice = "Your activity timer was restored. Reconnect a sensor for live heart rate."
        if source == .watch {
            // The watch owns this workout and saves it to Health itself. A
            // recovered session belongs to the bridge, never to `session` and
            // `builder` here, or the phone would write the workout a second time.
            guard HKHealthStore.isHealthDataAvailable(), !healthSaved else { return }
            busy = true
            healthStore.recoverActiveWorkoutSession { [weak self] recovered, _ in
                Task { @MainActor in
                    guard let self, self.active else { return }
                    self.busy = false
                    guard let recovered else {
                        self.notice = "Your watch is still recording. It reconnects when the workout ends or Almanac opens on the watch."
                        self.persist()
                        return
                    }
                    self.watch?.adopt(recovered)
                    if recovered.state == .stopped || recovered.state == .ended {
                        self.timer?.finish(at: recovered.endDate ?? .now)
                        self.notice = "Your watch finished this workout. Save it here."
                    }
                    self.persist()
                }
            }
            return
        }
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

    /// `backdatedStart` exists for the design fixture only; real sessions
    /// start when the clock is read, after Health has answered.
    func start(backdatedTo backdatedStart: Date? = nil) async {
        guard active, !busy, !hasSession else { return }
        // `!hasSession` means the timer is either nil or a finished, saved one
        // from the last workout; either way this start owns a fresh one.
        busy = true; error = nil; saved = false; healthSaved = false; collectionEnded = false; timer = nil
        zones = HeartRateZones(birthDate: birthDate())
        capacity = loadCapacity()
        effort = EffortAccumulator(); lastReadingAt = nil
        source = .phone
        if selection == .strength { reps = 0; setIndex = 1; completedSets = [] } else { reps = nil; setIndex = nil; completedSets = [] }
        recordingHealth = saveToHealth
        defer { busy = false }
        if await handOffToWatch() { return }
        // Only the phone's own session wants a strap: a watch session streams
        // its own heart rate, and two feeds would double the readings.
        sensor.prepareForSession(whoopConnected: whoopConnected())
        do {
            // Never for `.watch`: the watch owns that session and saves it.
            if saveToHealth && source == .phone {
                try await healthStore.requestAuthorization(toShare: Self.workoutTypes, read: Self.workoutTypes)
                // A mirrored session can arrive during that await; if it did,
                // the watch owns the workout and this branch must stand down.
                guard active, source == .phone else { return }
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
                let started = backdatedStart ?? .now
                if timer == nil { timer = ActivitySessionState(activity: selection.rawValue, at: started) }
                session.startActivity(with: started)
                try await builder.beginCollection(at: started)
                guard active else { session.end(); builder.discardWorkout(); return }
            } else if timer == nil {
                timer = ActivitySessionState(activity: selection.rawValue, at: backdatedStart ?? .now)
            }
            persist()
        } catch {
            session?.end(); builder?.discardWorkout(); session = nil; builder = nil; timer = nil
            self.error = "Could not start activity: \(error.localizedDescription)"
        }
    }
    func togglePause() {
        guard !busy else { return }
        if isRunning { timer?.pause(); if source == .watch { watch?.send(.pause) } else { session?.pause() } }
        else if isPaused { timer?.resume(); if source == .watch { watch?.send(.resume) } else { session?.resume() }; lastReadingAt = nil }
        persist()
    }
    func finish() async {
        guard active, !busy, timer != nil, !saved else { return }
        busy = true; error = nil
        self.timer?.finish(); persist()
        if source == .watch {
            watch?.end(after: .end)
            await saveFinished()
            return
        }
        if let session, !healthSaved, session.state == .running || session.state == .paused {
            session.stopActivity(with: self.timer?.endedAt)
            // The delegate completes collection after HealthKit reaches stopped.
            return
        }
        await saveFinished()
    }
    func saveFinished() async {
        guard active, !finishing, !saved, timer?.phase == .finished else { busy = false; return }
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
                if selection == .strength { row.sets = completedSets + [reps ?? 0] }
                context.insert(row)
            }
            try context.save()
            liveActivity.end()
            saved = true; defaults.removeObject(forKey: Self.draftKey)
            sensor.stopStreaming()
            // Never for `.watch`: `finish()` already dropped the bridge in its
            // send completion, and dropping it here would race that send.
            if source == .phone { watch?.end() }
            session = nil; builder = nil
            onSaved?()
        } catch {
            self.error = "Your activity is kept here. Saving failed: \(error.localizedDescription). Try Save again."
        }
    }
    func discard() {
        liveActivity.end()
        // `discard`, not `end`: on the wrist `end` means finish and save, so
        // ending here would write to Health the workout the person threw away.
        if source == .watch { watch?.end(after: .discard) }
        session?.delegate = nil; builder?.delegate = nil
        session?.end(); builder?.discardWorkout(); session = nil; builder = nil
        sensor.stopStreaming(); timer = nil; saved = false; healthSaved = false
        energy = nil; distance = nil; heartRate = nil; heartRateDate = nil
        capacity = nil; readout = nil; effort = EffortAccumulator(); lastReadingAt = nil; zones = nil; lastDraftWriteAt = nil
        source = .phone; reps = nil; setIndex = nil; completedSets = []
        error = nil; notice = nil; busy = false
        defaults.removeObject(forKey: Self.draftKey)
    }
    func deactivate() {
        active = false; discard(); context = nil; onSaved = nil
        watch?.onSession = nil; watch?.onPacket = nil; watch?.onStateChange = nil
    }
    /// State changes: always write the draft and sync.
    func persist() {
        refreshReadout()
        writeDraft()
        syncLiveActivity()
    }
    /// Readings arrive every second: always refresh and sync (the controller
    /// throttles the publish), but write the draft at most every ten seconds.
    func persistReading(at date: Date) {
        refreshReadout()
        if lastDraftWriteAt.map({ date.timeIntervalSince($0) >= 10 }) ?? true { writeDraft(at: date) }
        syncLiveActivity()
    }
    private func writeDraft(at date: Date = .now) {
        guard active, let timer,
              let data = try? JSONEncoder().encode(Draft(timer: timer, healthSaved: healthSaved, recordsHealth: recordingHealth,
                                                         energy: energy, distance: distance, capacity: capacity, effortLoad: effort.load,
                                                         source: source, reps: reps, setIndex: setIndex, completedSets: completedSets)) else { return }
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
                                             capacity: capacity, energyKcal: energy, distanceMeters: distance,
                                             reps: reps, setIndex: setIndex)
    }
    /// Today's row, or yesterday's while today has not synced. A week of
    /// rows behind it gives the Health path its HRV baseline.
    func loadCapacity() -> Capacity? {
        guard let context else { return nil }
        let rows = (try? MetricsStore(context: context).metrics(from: .now.addingTimeInterval(-9 * 86400), to: .now)) ?? []
        let days = rows.map {
            RecoveryDay(date: $0.date, whoopRecoveryPct: $0.whoopRecoveryPct, whoopIsCalibrating: $0.whoopRecoveryIsCalibrating,
                        sleepPerformancePct: $0.whoopSleepPerformancePct, hrvMs: $0.hrvMs, sleepMinutes: $0.sleepMinutes)
        }
        return CapacityMath.capacity(days: days, now: .now)
    }
    func receiveHeartRate(_ bpm: Int, at date: Date) {
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
            case .running: self.timer?.resume(at: date); self.lastReadingAt = nil
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

    #if DEBUG
    /// Writes a `.watch` draft the way a real watch session would, so the
    /// in-simulator checks can exercise the restore path without a watch.
    /// It lives here because `Draft` is the recorder's own private shape.
    static func seedWatchDraft(into defaults: UserDefaults, activity: String = "Strength", at date: Date = .now) {
        let draft = Draft(timer: ActivitySessionState(activity: activity, at: date), healthSaved: false,
                          recordsHealth: false, energy: nil, distance: nil, capacity: nil, effortLoad: 0,
                          source: .watch, reps: 0, setIndex: 1, completedSets: [])
        guard let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: draftKey)
    }
    #endif
}

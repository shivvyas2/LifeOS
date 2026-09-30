import Foundation
import ActivityKit
import HealthKit
import SwiftData
import Persistence
import Integrations
import AppSurfaces

@MainActor @Observable
final class ActivityRecorder: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    var selection: ActivityType = ActivityCatalog.walk
    /// The last six activities started on this account, for the picker.
    /// Same defaults as the draft, so the design preview's disposable suite
    /// keeps its own list.
    var recents: ActivityRecents
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
    var watchSessionID: UUID?
    var lastWatchPacketAt: Date?
    var source: SessionSource = .phone
    var reps: Int?
    var setIndex: Int?
    var completedSets: [Int] = []
    /// Set by the player screen before `finish()` so the saved record carries
    /// which video and which split the session followed.
    var pendingVideoID: String?
    var pendingSplit: String?
    /// The video the player screen is following, for the in-session line.
    var following: (title: String, channel: String)?
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
    private let healthStore = HKHealthStore()
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
    static let draftKey = "activeWorkoutDraft"
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

    struct Draft: Codable {
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
        /// Optional, so a draft written before this slice still decodes. A
        /// session restored after a relaunch mid-video keeps the "Following:"
        /// line and, more importantly, still stamps the saved record.
        var videoID: String?
        var split: String?
        var followingTitle: String?
        var followingChannel: String?
        var watchSessionID: UUID?
    }

    init(defaults: UserDefaults = .currentAccount, liveActivitiesEnabled: Bool = true) {
        self.defaults = defaults
        recents = ActivityRecents(defaults: defaults)
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
        watch?.onControlFailure = { [weak self] message in self?.error = message }
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
        watchSessionID = draft.watchSessionID
        pendingVideoID = draft.videoID; pendingSplit = draft.split
        if let title = draft.followingTitle, let channel = draft.followingChannel { following = (title, channel) }
        zones = HeartRateZones(birthDate: birthDate())
        selection = ActivityCatalog.type(named: draft.timer.activity) ?? ActivityCatalog.other
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
    ///
    /// `following` belongs to *this* start, not to the recorder: set before
    /// the call, a start that bails (Health refused, a mirrored watch session
    /// arriving) left the fields behind and the next freeform Walk was saved
    /// stamped with a video nobody watched. Passing it here means every start
    /// that is not from the player clears them.
    func start(backdatedTo backdatedStart: Date? = nil,
               following video: (id: String, split: String, title: String, channel: String)? = nil) async {
        guard active, !busy, !hasSession else { return }
        if let video {
            pendingVideoID = video.id; pendingSplit = video.split; following = (video.title, video.channel)
        } else {
            pendingVideoID = nil; pendingSplit = nil; following = nil
        }
        // `!hasSession` means the timer is either nil or a finished, saved one
        // from the last workout; either way this start owns a fresh one.
        watchSessionID = nil; lastWatchPacketAt = nil
        busy = true; error = nil; saved = false; healthSaved = false; collectionEnded = false; timer = nil
        zones = HeartRateZones(birthDate: birthDate())
        capacity = loadCapacity()
        effort = EffortAccumulator(); lastReadingAt = nil
        source = .phone
        if selection.countsReps { reps = 0; setIndex = 1; completedSets = [] } else { reps = nil; setIndex = nil; completedSets = [] }
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
                if timer == nil { timer = ActivitySessionState(activity: selection.name, at: started) }
                session.startActivity(with: started)
                try await builder.beginCollection(at: started)
                guard active else { session.end(); builder.discardWorkout(); return }
            } else if timer == nil {
                timer = ActivitySessionState(activity: selection.name, at: backdatedStart ?? .now)
            }
            // Only a session that actually started belongs in the recents
            // list; a refused or failed start above already returned or is
            // about to throw, so it never reaches here.
            recents.record(selection)
            persist()
        } catch {
            session?.end(); builder?.discardWorkout(); session = nil; builder = nil; timer = nil
            self.error = "Could not start activity: \(error.localizedDescription)"
        }
    }
    func togglePause() {
        guard !busy else { return }
        if source == .watch {
            // The primary session confirms the state; an offline command
            // must not pretend it paused the Watch.
            if isRunning { watch?.send(.pause) }
            else if isPaused { watch?.send(.resume) }
            return
        }
        if isRunning { timer?.pause(); session?.pause() }
        else if isPaused { timer?.resume(); session?.resume(); lastReadingAt = nil }
        persist()
    }
    func finish() async {
        guard active, !busy, timer != nil, !saved else { return }
        busy = true; error = nil
        if source == .watch {
            if timer?.phase == .finished { await saveFinished(); return }
            guard let watch else { busy = false; error = "Finish this workout on your Apple Watch."; return }
            watch.send(.end) { [weak self] success in
                guard let self else { return }
                if !success { self.busy = false }
            }
            // State confirmation normally saves through mirroredStateChanged.
            // Keep controls recoverable if the connection drops after sending.
            let expectedID = timer?.id
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard let self, self.active, self.timer?.id == expectedID, self.busy, !self.saved else { return }
                self.busy = false
                self.error = "Waiting for Apple Watch. Check the workout there; it will sync when connected."
            }
            return
        }
        self.timer?.finish(); persist()
        if let session, !healthSaved, session.state == .running || session.state == .paused {
            session.stopActivity(with: self.timer?.endedAt)
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
            var id = watchSessionID.map { "almanac-watch:\($0.uuidString)" } ?? "almanac:\(timer.id.uuidString)"
            if source == .watch, watchSessionID == nil {
                let start = timer.startedAt
                let activity = timer.activity
                let candidates = try context.fetch(FetchDescriptor<WorkoutRecord>(predicate: #Predicate { $0.start == start && $0.activityName == activity }))
                if let synced = candidates.first(where: { $0.externalID.hasPrefix("almanac-watch:") }) { id = synced.externalID }
            }
            var fetch = FetchDescriptor<WorkoutRecord>(predicate: #Predicate { $0.externalID == id })
            fetch.fetchLimit = 1
            if try context.fetch(fetch).isEmpty {
                let row = WorkoutRecord(externalID: id, start: timer.startedAt,
                    durationMinutes: Int(timer.elapsed() / 60), activityName: timer.activity, energyKcal: energy)
                row.distanceMeters = distance
                row.videoID = pendingVideoID; row.split = pendingSplit
                if selection.countsReps { row.sets = completedSets + [reps ?? 0] }
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
    /// A workout the person started on their wrist is not the video the
    /// player was queuing. `busy` is the tell: it is true only while
    /// `start(following:)` is still in flight, which is the one case these
    /// fields were set for the session now arriving. Idle means nobody here
    /// asked for this session, so nothing it saves should name a video.
    func clearPendingVideoIfIdle() {
        guard !busy else { return }
        pendingVideoID = nil; pendingSplit = nil; following = nil
    }
    func discard() {
        if active, source == .watch, hasSession, let watch {
            watch.send(.discard) { [weak self] success in
                guard success, let self else { return }
                self.clearDiscardedWorkout()
            }
            return
        }
        clearDiscardedWorkout()
    }
    private func clearDiscardedWorkout() {
        liveActivity.end()
        // `discard`, not `end`: on the wrist `end` means finish and save, so
        // ending here would write to Health the workout the person threw away.
        if source == .watch {
            if active { watch?.end() } else { watch?.end(after: .discard) }
        }
        session?.delegate = nil; builder?.delegate = nil
        session?.end(); builder?.discardWorkout(); session = nil; builder = nil
        sensor.stopStreaming(); timer = nil; saved = false; healthSaved = false
        energy = nil; distance = nil; heartRate = nil; heartRateDate = nil
        capacity = nil; readout = nil; effort = EffortAccumulator(); lastReadingAt = nil; zones = nil; lastDraftWriteAt = nil
        watchSessionID = nil; lastWatchPacketAt = nil
        source = .phone; reps = nil; setIndex = nil; completedSets = []
        pendingVideoID = nil; pendingSplit = nil; following = nil
        error = nil; notice = nil; busy = false
        defaults.removeObject(forKey: Self.draftKey)
    }
    func deactivate() {
        active = false; discard(); context = nil; onSaved = nil
        watch?.onSession = nil; watch?.onPacket = nil; watch?.onStateChange = nil; watch?.onControlFailure = nil
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
        // A saved workout has no draft to leave behind: `saveFinished` removes
        // the key, and a later refresh must not write it back.
        guard active, !saved, let timer,
              let data = try? JSONEncoder().encode(Draft(timer: timer, healthSaved: healthSaved, recordsHealth: recordingHealth,
                                                         energy: energy, distance: distance, capacity: capacity, effortLoad: effort.load,
                                                         source: source, reps: reps, setIndex: setIndex, completedSets: completedSets,
                                                         videoID: pendingVideoID, split: pendingSplit,
                                                         followingTitle: following?.title, followingChannel: following?.channel, watchSessionID: watchSessionID)) else { return }
        defaults.set(data, forKey: Self.draftKey)
        lastDraftWriteAt = date
    }
    /// A card the bridge put up before this timer existed, or one left by a
    /// workout that ended without a recorder watching, is not this session's.
    /// Only one activity belongs on screen, so end every other one.
    func endStrayLiveActivities() {
        guard liveActivitiesEnabled, let timer else { return }
        let strays = Activity<WorkoutActivityAttributes>.activities.filter { $0.attributes.sessionID != timer.id }
        guard !strays.isEmpty else { return }
        Task { for activity in strays { await activity.end(nil, dismissalPolicy: .immediate) } }
    }
    private func syncLiveActivity() {
        guard liveActivitiesEnabled, let timer, let readout else { return }
        liveActivity.sync(readout, timer: timer, icon: selection.symbol)
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
        context.map { CapacityInputs.todayCapacity(store: MetricsStore(context: $0)) } ?? nil
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

    /// The same, for a phone session that was following a video, so the checks
    /// can prove a relaunch mid-video still stamps the saved record.
    static func seedDraft(into defaults: UserDefaults, activity: String = "Strength", at date: Date = .now,
                          videoID: String, split: String, title: String, channel: String) {
        let draft = Draft(timer: ActivitySessionState(activity: activity, at: date), healthSaved: false,
                          recordsHealth: false, energy: nil, distance: nil, capacity: nil, effortLoad: 0,
                          source: .phone, reps: 0, setIndex: 1, completedSets: [],
                          videoID: videoID, split: split, followingTitle: title, followingChannel: channel)
        guard let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: draftKey)
    }
    #endif
}

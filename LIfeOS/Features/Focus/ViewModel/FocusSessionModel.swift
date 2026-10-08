import Foundation
import SwiftData
import AVFoundation
import UIKit
import Persistence
import Soundscape

/// One focus session: the clock, the sound, and what the sound listens to.
@MainActor @Observable
final class FocusSessionModel {
    struct Summary: Equatable {
        var mood: Mood
        var focusedSeconds: TimeInterval
        var blocks: Int
        var taskID: UUID?
        var taskTitle: String?
    }

    enum Stage: Equatable { case idle, running, summary(Summary) }

    private(set) var stage: Stage = .idle
    private(set) var setup = FocusSetup.standard(for: .focus)
    private(set) var reading: TimerReading?
    private(set) var parameters: SoundParameters?
    private(set) var heartRate: Int?
    private(set) var notice: String?
    private(set) var activeSource: SoundSource = .soundscape
    private(set) var taskTitle: String?
    private(set) var preferences: FocusPreferences
    var isPresented: Bool { stage != .idle }

    static let preferencesKey = "focus.preferences"

    private var engine = SoundscapeEngine()
    private let music = MusicSource()
    private let watch = FocusHeartRate()
    private let nowPlaying = FocusNowPlaying()
    private let notifications = FocusNotifications()
    private let defaults: UserDefaults
    private var timer: FocusTimer?
    private var inputs = FocusInputs()
    private var context: ModelContext?
    private var taskID: UUID?
    private var startedAt = Date.now
    private var ticker: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var lastPhase: TimerPhase?
    private var lastPush = Date.distantPast
    /// Off in the design preview, so no permission prompt covers UI tests.
    private let notifies: Bool
    /// Bumped on every engine start and stop, so `soundPlaying` re-reads it.
    private var soundEpoch = 0
    /// Bumped when a session starts or ends. Work that resumes after an
    /// await checks it, so an End tapped mid-start leaves nothing running.
    private var generation = 0
    /// A mood change while paused on Apple Music waits for Resume.
    private var musicMoodPending = false

    /// Whether sound is coming out: a soundscape stopped by a route change is not.
    var soundPlaying: Bool { _ = soundEpoch; return activeSource != .soundscape || engine.isRunning }

    init(defaults: UserDefaults = .standard, notifies: Bool = true) {
        self.defaults = defaults
        self.notifies = notifies
        self.preferences = FocusPreferences.load(from: defaults, key: Self.preferencesKey)
        wireEngine()
    }

    func resumeSound() { try? engine.resume(); soundEpoch += 1 }

    func start(_ setup: FocusSetup, inputs: FocusInputs, context: ModelContext, taskID: UUID? = nil, taskTitle: String? = nil) async {
        guard stage != .running else { return }
        preferences.remember(setup)
        preferences.save(to: defaults, key: Self.preferencesKey)
        let now = Date.now
        begin(setup: setup, timer: FocusTimer(plan: setup.plan, startedAt: now), startedAt: now,
              inputs: inputs, context: context, taskID: taskID, taskTitle: taskTitle)
        let gen = generation

        let availability: MusicAvailability = setup.source == .appleMusic ? await music.availability() : .unknown
        guard isCurrent(gen) else { return }
        let resolved = resolveSource(setup.source, music: availability)
        activeSource = resolved.source
        notice = resolved.notice
        persist()
        await run(gen)
    }

    /// A session saved before the app was closed or killed: carry on with
    /// it, or, if its time ran out meanwhile, record it and show the summary.
    func restore(context: ModelContext, providers: DayProviders?) async {
        guard stage == .idle, let saved = ActiveFocusSession.load(from: defaults) else { return }
        let reading = saved.timer.reading(at: .now)
        if reading.phase == .finished {
            ActiveFocusSession.clear(from: defaults)
            if notifies { await notifications.cancel() }
            try? FocusStore(context: context).record(mood: saved.setup.mood.rawValue, source: saved.source.rawValue,
                                                     startedAt: saved.startedAt, endedAt: .now,
                                                     focusedSeconds: reading.focusedSeconds,
                                                     blocksCompleted: reading.completedBlocks, projectTaskID: saved.taskID)
            self.context = context
            stage = .summary(Summary(mood: saved.setup.mood, focusedSeconds: reading.focusedSeconds,
                                     blocks: reading.completedBlocks, taskID: saved.taskID, taskTitle: saved.taskTitle))
            return
        }
        begin(setup: saved.setup, timer: saved.timer, startedAt: saved.startedAt, inputs: FocusInputs(),
              context: context, taskID: saved.taskID, taskTitle: saved.taskTitle)
        let gen = generation
        activeSource = saved.source
        let inputs = await FocusInputs.gather(context: context, providers: providers)
        guard isCurrent(gen) else { return }
        self.inputs = inputs
        await run(gen)
    }

    private func begin(setup: FocusSetup, timer: FocusTimer, startedAt: Date, inputs: FocusInputs,
                       context: ModelContext, taskID: UUID?, taskTitle: String?) {
        generation += 1
        self.setup = setup
        self.inputs = inputs
        self.context = context
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.startedAt = startedAt
        self.timer = timer
        reading = timer.reading(at: .now)
        lastPhase = reading?.phase
        notice = nil
        heartRate = nil
        musicMoodPending = false
        stage = .running
    }

    private func isCurrent(_ gen: Int) -> Bool { stage == .running && generation == gen }

    /// Everything after the source is known: sound, heart rate, notifications
    /// and the once-a-second clock, each step abandoned if the session ended.
    private func run(_ gen: Int) async {
        await startSound(gen)
        guard isCurrent(gen) else { return }
        if reading?.isPaused == true { haltSound() }
        watch.onHeartRate = { [weak self] rate in self?.heartRate = rate; self?.push(force: false) }
        await watch.start()
        guard isCurrent(gen) else { watch.stop(); return }
        observe()
        await reschedule()
        guard isCurrent(gen) else { return }
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func startSound(_ gen: Int) async {
        switch activeSource {
        case .soundscape:
            let p = makeParameters()
            parameters = p
            do { try engine.start(mood: setup.mood, parameters: p) } catch { notice = "The soundscape couldn't start. Timer only." }
            soundEpoch += 1
            nowPlaying.activate(title: "\(setup.mood.title) · Soundscape",
                                onPlay: { [weak self] in self?.resume() },
                                onPause: { [weak self] in self?.pause() },
                                onSkip: { [weak self] in self?.skip() })
        case .appleMusic:
            do {
                try await music.play(setup.mood)
                if !isCurrent(gen) { music.stop() }
            } catch {
                guard isCurrent(gen) else { return }
                activeSource = .soundscape
                notice = "No Apple Music playlist fits right now. Playing a soundscape instead."
                persist()
                await startSound(gen)
            }
        case .silence:
            break
        }
    }

    private func makeParameters() -> SoundParameters {
        let phase = reading.map(SoundPhase.init) ?? .work
        let conditions = Conditions(date: .now, heartRate: heartRate.map(Double.init),
                                    restingHeartRate: inputs.restingHeartRate, phase: phase,
                                    weather: inputs.weather, recovery: inputs.recovery, texture: setup.texture)
        return .make(.for(setup.mood), conditions)
    }

    /// New parameters at most every five seconds, or at once on a phase change.
    private func push(force: Bool) {
        guard activeSource == .soundscape, stage == .running else { return }
        guard force || Date.now.timeIntervalSince(lastPush) >= 5 else { return }
        lastPush = .now
        let p = makeParameters()
        parameters = p
        engine.update(p)
    }

    private func tick() {
        guard stage == .running, let timer else { return }
        let reading = timer.reading(at: .now)
        self.reading = reading
        if reading.phase != lastPhase {
            phaseChanged(to: reading.phase)
            lastPhase = reading.phase
            push(force: true)
        } else {
            push(force: false)
        }
        if activeSource == .soundscape {
            nowPlaying.update(title: "\(setup.mood.title) · \(phaseTitle(reading.phase))",
                              elapsed: (reading.phaseLength ?? 0) - (reading.remaining ?? 0),
                              duration: reading.phaseLength, playing: !reading.isPaused)
        }
        if reading.phase == .finished { end() }
    }

    /// Apple Music plays straight through breaks: a paused player lets iOS
    /// suspend the app, and nothing would be left to start it again.
    private func phaseChanged(to new: TimerPhase) {
        guard UIApplication.shared.applicationState == .active, new != .finished else { return }
        if activeSource == .soundscape { engine.chime() }
        else { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    func phaseTitle(_ phase: TimerPhase) -> String {
        switch phase {
        case .work(let block):
            // The running timer's plan, not one rebuilt from the setup: a mood
            // change keeps the clock, so it must keep the block count too.
            if case .pomodoro(_, _, _, _, let blocks) = timer?.plan ?? setup.plan, let blocks { return "Focus \(block) of \(blocks)" }
            return "Focus \(block)"
        case .rest: return "Break"
        case .longRest: return "Long break"
        case .open: return setup.mood == .sleep ? "Sleep" : setup.mood.title
        case .fading: return "Fading out"
        case .finished: return "Done"
        }
    }

    private func haltSound() {
        switch activeSource {
        case .soundscape: engine.pause(); soundEpoch += 1
        case .appleMusic: music.pause()
        case .silence: break
        }
    }

    func pause() {
        guard stage == .running, var timer, !timer.reading(at: .now).isPaused else { return }
        timer.pause(at: .now); self.timer = timer
        reading = timer.reading(at: .now)
        haltSound()
        persist()
        Task { await notifications.cancel() }
    }

    func resume() {
        guard stage == .running, var timer, timer.reading(at: .now).isPaused else { return }
        timer.resume(at: .now); self.timer = timer
        reading = timer.reading(at: .now)
        switch activeSource {
        case .soundscape: try? engine.resume(); soundEpoch += 1
        case .appleMusic:
            let mood = setup.mood, pending = musicMoodPending
            musicMoodPending = false
            Task { if pending { try? await music.play(mood) } else { await music.resume() } }
        case .silence: break
        }
        persist()
        Task { await reschedule() }
    }

    func skip() {
        guard stage == .running, var timer else { return }
        timer.skip(at: .now); self.timer = timer
        persist()
        tick()
        Task { await reschedule() }
    }

    /// A new mood crossfades; the clock is untouched.
    func changeMood(_ mood: Mood) {
        guard stage == .running, mood != setup.mood else { return }
        let remembered = preferences.setup(for: mood)
        setup.mood = mood
        setup.texture = remembered.texture
        persist()
        switch activeSource {
        case .soundscape:
            let p = makeParameters()
            parameters = p
            engine.change(to: mood, parameters: p)
        case .appleMusic:
            if reading?.isPaused == true { musicMoodPending = true } else { Task { try? await music.play(mood) } }
        case .silence: break
        }
    }

    func end() {
        guard stage == .running, let timer else { return }
        generation += 1
        let reading = timer.reading(at: .now)
        ticker?.cancel(); ticker = nil
        engine.stop(); music.stop(); watch.stop(); nowPlaying.clear()
        soundEpoch += 1
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        ActiveFocusSession.clear(from: defaults)
        Task { await notifications.cancel() }
        if let context {
            try? FocusStore(context: context).record(mood: setup.mood.rawValue, source: activeSource.rawValue,
                                                     startedAt: startedAt, endedAt: .now,
                                                     focusedSeconds: reading.focusedSeconds,
                                                     blocksCompleted: reading.completedBlocks, projectTaskID: taskID)
        }
        self.timer = nil
        stage = .summary(Summary(mood: setup.mood, focusedSeconds: reading.focusedSeconds,
                                 blocks: reading.completedBlocks, taskID: taskID, taskTitle: taskTitle))
    }

    func markTaskDone() {
        guard case .summary(let summary) = stage, let id = summary.taskID, let context else { return }
        try? ProjectsStore(context: context).moveTask(id: id, to: .done, at: 0)
    }

    func dismissSummary() { stage = .idle; taskID = nil; taskTitle = nil }

    private func persist() {
        guard stage == .running, let timer else { return }
        ActiveFocusSession(setup: setup, source: activeSource, timer: timer, startedAt: startedAt,
                           taskID: taskID, taskTitle: taskTitle).save(to: defaults)
    }

    private func reschedule() async {
        guard notifies, let timer else { return }
        await notifications.schedule(timer.upcomingEnds(after: .now, limit: 12), plan: timer.plan)
    }

    private func wireEngine() {
        engine.onStopped = { [weak self] in self?.soundEpoch += 1 }
    }

    private func observe() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            MainActor.assumeIsolated {
                guard let self, self.stage == .running, self.activeSource == .soundscape else { return }
                if raw == AVAudioSession.InterruptionType.began.rawValue {
                    self.engine.pause()
                } else if AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume),
                          self.reading?.isPaused == false {
                    try? self.engine.resume()
                }
                self.soundEpoch += 1
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                guard let self, self.stage == .running, reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue,
                      self.activeSource == .soundscape else { return }
                self.engine.pause()
                self.soundEpoch += 1
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // Every audio object is invalid after a reset: build a new
                // engine and, unless the session is paused, start it again.
                guard let self, self.stage == .running, self.activeSource == .soundscape else { return }
                self.engine.stop()
                self.engine = SoundscapeEngine()
                self.wireEngine()
                let p = self.makeParameters()
                self.parameters = p
                if self.reading?.isPaused == false { try? self.engine.start(mood: self.setup.mood, parameters: p) }
                self.soundEpoch += 1
            }
        })
        observers.append(center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                let state = ProcessInfo.processInfo.thermalState
                self?.engine.setLight(state == .serious || state == .critical)
            }
        })
    }
}

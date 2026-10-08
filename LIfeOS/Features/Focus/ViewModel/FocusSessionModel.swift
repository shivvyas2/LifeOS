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

    private let engine = SoundscapeEngine()
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

    /// Whether sound is coming out: a soundscape paused by a route change is not.
    var soundPlaying: Bool { _ = soundEpoch; return activeSource != .soundscape || engine.isRunning }

    init(defaults: UserDefaults = .standard, notifies: Bool = true) {
        self.defaults = defaults
        self.notifies = notifies
        self.preferences = FocusPreferences.load(from: defaults, key: Self.preferencesKey)
    }

    func resumeSound() { try? engine.resume(); soundEpoch += 1 }

    func start(_ setup: FocusSetup, inputs: FocusInputs, context: ModelContext, taskID: UUID? = nil, taskTitle: String? = nil) async {
        guard stage != .running else { return }
        self.setup = setup
        self.inputs = inputs
        self.context = context
        self.taskID = taskID
        self.taskTitle = taskTitle
        preferences.remember(setup)
        preferences.save(to: defaults, key: Self.preferencesKey)
        startedAt = .now
        timer = FocusTimer(plan: setup.plan, startedAt: startedAt)
        reading = timer?.reading(at: .now)
        lastPhase = reading?.phase
        notice = nil
        heartRate = nil
        stage = .running

        let availability: MusicAvailability = setup.source == .appleMusic ? await music.availability() : .unknown
        let resolved = resolveSource(setup.source, music: availability)
        activeSource = resolved.source
        notice = resolved.notice
        await startSound()

        watch.onHeartRate = { [weak self] rate in self?.heartRate = rate; self?.push(force: false) }
        await watch.start()
        observe()
        await reschedule()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func startSound() async {
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
            do { try await music.play(setup.mood) } catch {
                activeSource = .soundscape
                notice = "No Apple Music playlist fits right now. Playing a soundscape instead."
                await startSound()
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

    private func phaseChanged(to new: TimerPhase) {
        if UIApplication.shared.applicationState == .active, new != .finished {
            if activeSource == .soundscape { engine.chime() }
            else { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        }
        guard activeSource == .appleMusic else { return }
        switch new {
        case .rest, .longRest: music.pause()
        case .work: Task { await music.resume() }
        default: break
        }
    }

    func phaseTitle(_ phase: TimerPhase) -> String {
        switch phase {
        case .work(let block):
            if case .pomodoro(_, _, _, _, let blocks) = setup.plan, let blocks { return "Focus \(block) of \(blocks)" }
            return "Focus \(block)"
        case .rest: return "Break"
        case .longRest: return "Long break"
        case .open: return setup.mood == .sleep ? "Sleep" : setup.mood.title
        case .fading: return "Fading out"
        case .finished: return "Done"
        }
    }

    func pause() {
        guard stage == .running, var timer, !timer.reading(at: .now).isPaused else { return }
        timer.pause(at: .now); self.timer = timer
        reading = timer.reading(at: .now)
        switch activeSource {
        case .soundscape: engine.pause(); soundEpoch += 1
        case .appleMusic: music.pause()
        case .silence: break
        }
        Task { await notifications.cancel() }
    }

    func resume() {
        guard stage == .running, var timer, timer.reading(at: .now).isPaused else { return }
        timer.resume(at: .now); self.timer = timer
        reading = timer.reading(at: .now)
        switch activeSource {
        case .soundscape: try? engine.resume(); soundEpoch += 1
        case .appleMusic:
            if case .work = reading?.phase { Task { await music.resume() } }
        case .silence: break
        }
        Task { await reschedule() }
    }

    func skip() {
        guard stage == .running, var timer else { return }
        timer.skip(at: .now); self.timer = timer
        tick()
        Task { await reschedule() }
    }

    /// A new mood crossfades; the clock is untouched.
    func changeMood(_ mood: Mood) {
        guard stage == .running, mood != setup.mood else { return }
        let remembered = preferences.setup(for: mood)
        setup.mood = mood
        setup.texture = remembered.texture
        switch activeSource {
        case .soundscape:
            let p = makeParameters()
            parameters = p
            engine.change(to: mood, parameters: p)
        case .appleMusic:
            Task { try? await music.play(mood) }
        case .silence: break
        }
    }

    func end() {
        guard stage == .running, let timer else { return }
        let reading = timer.reading(at: .now)
        ticker?.cancel(); ticker = nil
        engine.stop(); music.stop(); watch.stop(); nowPlaying.clear()
        soundEpoch += 1
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
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

    private func reschedule() async {
        guard notifies, let timer else { return }
        await notifications.schedule(timer.upcomingEnds(after: .now, limit: 12), plan: timer.plan)
    }

    private func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            MainActor.assumeIsolated {
                guard let self, self.activeSource == .soundscape else { return }
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
                guard let self, reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue,
                      self.activeSource == .soundscape else { return }
                self.engine.pause()
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

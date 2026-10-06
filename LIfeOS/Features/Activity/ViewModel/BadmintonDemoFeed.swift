import Foundation
import AppSurfaces
import Integrations

/// Plays the scripted demo match into a recorder the way a Watch would: one
/// packet a tick, through the same wire and the same gate, carrying what the
/// script holds at that moment. When the script runs out, the demo finishes
/// itself.
///
/// `timeScale` runs the script faster than the clock, for the checks and the
/// design captures; the shipped demo runs at one.
@MainActor final class BadmintonDemoFeed {
    let script: BadmintonDemoScript
    let timeScale: Double
    private let tick: Duration
    private weak var recorder: ActivityRecorder?
    private var task: Task<Void, Never>?
    private(set) var ralliesApplied = 0

    init(recorder: ActivityRecorder, script: BadmintonDemoScript = BadmintonDemoScript(),
         tick: Duration = .seconds(1), timeScale: Double = 1) {
        self.recorder = recorder; self.script = script; self.tick = tick; self.timeScale = timeScale
    }

    /// Seconds of the script the timer has reached. Pauses do not count,
    /// as they do not on a Watch.
    func scriptElapsed(_ timer: ActivitySessionState, at date: Date = .now) -> Double {
        timer.elapsed(at: date) * timeScale
    }

    func start() {
        guard task == nil else { return }
        let tick = self.tick
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: tick)
                guard let self, !Task.isCancelled, await self.step() else { return }
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    /// One tick. False once there is nothing left to send.
    private func step() async -> Bool {
        guard let recorder, recorder.active, recorder.source == .demo, !recorder.saved,
              let timer = recorder.timer, timer.phase != .finished else { return false }
        let elapsed = scriptElapsed(timer)
        if elapsed >= BadmintonDemoScript.length {
            await recorder.finish()
            return false
        }
        let (packet, applied) = script.packet(at: elapsed, paused: timer.phase == .paused,
                                              session: recorder.badminton ?? BadmintonDemoScript.match,
                                              ralliesApplied: ralliesApplied, now: .now)
        ralliesApplied = applied
        if let data = try? WatchWire.encode(packet) { recorder.receiveWatchPacket(data) }
        return true
    }
}

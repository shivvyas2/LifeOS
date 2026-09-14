import ActivityKit
import AppSurfaces
import Integrations
import Foundation

@MainActor
final class WorkoutLiveActivityController {
    private var current: Activity<WorkoutActivityAttributes>?
    private var lastState: LiveSessionReadout?
    private var lastPublishedAt: Date?
    private var updates: Task<Void, Never>?

    func sync(_ readout: LiveSessionReadout, timer: ActivitySessionState, icon: String) {
        guard timer.phase != .finished else { end(); return }
        if current == nil {
            current = Activity<WorkoutActivityAttributes>.activities.first { $0.attributes.sessionID == timer.id }
        }
        let now = Date.now
        guard current == nil || LiveActivityThrottle.shouldPublish(previous: lastState, next: readout, lastPublishedAt: lastPublishedAt, now: now) else { return }
        lastState = readout; lastPublishedAt = now
        let content = ActivityContent(state: readout, staleDate: now.addingTimeInterval(8 * 3600))
        if let current {
            let preceding = updates
            updates = Task { await preceding?.value; await current.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            current = try? Activity.request(attributes: WorkoutActivityAttributes(sessionID: timer.id,
                name: timer.activity, icon: icon), content: content, pushType: nil)
        }
    }
    func end() {
        guard let current else { return }
        let preceding = updates
        updates = Task { await preceding?.value; await current.end(nil, dismissalPolicy: .immediate) }
        self.current = nil; lastState = nil; lastPublishedAt = nil
    }
    static func endAll() {
        let existing = Activity<WorkoutActivityAttributes>.activities
        Task { for activity in existing { await activity.end(nil, dismissalPolicy: .immediate) } }
    }
}

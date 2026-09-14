import ActivityKit
import AppSurfaces
import Integrations
import Foundation

@MainActor
final class WorkoutLiveActivityController {
    private var current: Activity<WorkoutActivityAttributes>?
    private var lastState: WorkoutActivityAttributes.ContentState?
    private var updates: Task<Void, Never>?

    func sync(_ timer: ActivitySessionState, icon: String) {
        guard timer.phase != .finished else { end(); return }
        let state = WorkoutActivityAttributes.ContentState(elapsed: timer.accumulated, runningSince: timer.runningSince)
        guard state != lastState || current == nil else { return }
        lastState = state
        if current == nil {
            current = Activity<WorkoutActivityAttributes>.activities.first { $0.attributes.sessionID == timer.id }
        }
        let content = ActivityContent(state: state, staleDate: .now.addingTimeInterval(8 * 3600))
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
        self.current = nil; lastState = nil
    }
    static func endAll() {
        let existing = Activity<WorkoutActivityAttributes>.activities
        Task { for activity in existing { await activity.end(nil, dismissalPolicy: .immediate) } }
    }
}

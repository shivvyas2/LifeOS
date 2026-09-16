import Foundation
import HealthKit
import WatchConnectivity
import ActivityKit
import AppSurfaces

/// Owns the workout session mirrored from the watch. One per app: HealthKit
/// hands the session to whichever handler is installed at launch, so the
/// bridge is installed by the app delegate and the recorder subscribes.
@MainActor
final class WatchSessionBridge: NSObject, HKWorkoutSessionDelegate {
    static let shared = WatchSessionBridge()
    private static let healthStore = HKHealthStore()

    private(set) var session: HKWorkoutSession?
    /// The id of a Live Activity requested before any recorder was listening,
    /// so the timer built later adopts it instead of asking for a second one.
    private(set) var placeholderSessionID: UUID?
    /// True between sending a last command and the session actually going.
    /// Without it `hasSession` stays true through that window and the next
    /// start refuses the hand-off against a session already on its way out.
    private var dropping = false
    private var placeholderPending = false
    var onSession: ((HKWorkoutSession) -> Void)?
    var onPacket: ((Data) -> Void)?
    var onStateChange: ((HKWorkoutSessionState, Date) -> Void)?
    var hasSession: Bool { session != nil && !dropping }

    /// Call once at launch, before any session can arrive.
    static func installMirroringHandler() {
        healthStore.workoutSessionMirroringStartHandler = { session in
            Task { @MainActor in
                let bridge = WatchSessionBridge.shared
                // HealthKit launches the phone app in the background for a
                // workout started on the wrist, with no scene and so no
                // recorder. The Live Activity has to be requested inside that
                // launch (spec 9), so ask for it here and let the recorder
                // adopt its id when a screen finally attaches.
                let unattended = bridge.onSession == nil
                bridge.adopt(session)
                if unattended { bridge.requestPlaceholderActivity(for: session) }
            }
        }
    }

    /// Whether a watch could take the session right now.
    static var watchAvailable: Bool {
        guard WCSession.isSupported() else { return false }
        let wc = WCSession.default
        // Not `isReachable`: on iOS that is true only while the watch app is
        // already in the foreground, which is never the case for a person
        // tapping Begin on the phone. `startWatchApp` exists to launch it, and
        // the hand-off timeout covers a session that never arrives.
        return wc.activationState == .activated && wc.isPaired && wc.isWatchAppInstalled
    }

    /// Ask the watch to open Almanac with this workout.
    static func startWatchApp(_ configuration: HKWorkoutConfiguration) async throws {
        try await healthStore.startWatchApp(toHandle: configuration)
    }

    func adopt(_ session: HKWorkoutSession) {
        self.session?.delegate = nil
        dropping = false
        self.session = session
        session.delegate = self
        onSession?(session)
    }

    func send(_ command: PhoneCommand, maxHeartRate: Int? = nil) {
        guard let session, let data = try? WatchWire.encode(PhoneCommandEnvelope(command: command, sentAt: .now, maxHeartRate: maxHeartRate)) else { return }
        session.sendToRemoteWorkoutSession(data: data) { _, _ in }
    }

    /// Sends a last command and drops the session only once it has left, in
    /// the send's completion handler: releasing the session in the same
    /// run-loop turn can cancel the send before the watch ever hears it.
    func end(after command: PhoneCommand) {
        guard let session, let data = try? WatchWire.encode(PhoneCommandEnvelope(command: command, sentAt: .now)) else {
            end(); return
        }
        dropping = true
        session.sendToRemoteWorkoutSession(data: data) { _, _ in
            Task { @MainActor in self.end() }
        }
    }

    func end() {
        session?.delegate = nil
        session = nil
        dropping = false
    }

    /// Called once the recorder's timer has taken the placeholder's id.
    func clearPlaceholder() { placeholderSessionID = nil }

    /// A session nobody adopted has ended: the card the handler put up is the
    /// only trace of it left, so take it down.
    private func endPlaceholderActivity() {
        guard let id = placeholderSessionID else { return }
        placeholderSessionID = nil
        let strays = Activity<WorkoutActivityAttributes>.activities.filter { $0.attributes.sessionID == id }
        guard !strays.isEmpty else { return }
        Task { for activity in strays { await activity.end(nil, dismissalPolicy: .immediate) } }
    }

    private func requestPlaceholderActivity(for session: HKWorkoutSession) {
        // One placeholder at a time: a second session arriving before the
        // recorder adopts the first must not leave two cards on screen.
        guard placeholderSessionID == nil, !placeholderPending,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        placeholderPending = true
        defer { placeholderPending = false }
        let id = UUID()
        let type = session.workoutConfiguration.activityType
        let content = ActivityContent(state: LiveSessionReadout(elapsed: 0, runningSince: .now, push: .onTrack),
                                      staleDate: Date.now.addingTimeInterval(8 * 3600))
        let attributes = WorkoutActivityAttributes(sessionID: id, name: Self.name(for: type), icon: Self.icon(for: type))
        guard (try? Activity.request(attributes: attributes, content: content, pushType: nil)) != nil else { return }
        placeholderSessionID = id
    }

    /// The same names and icons the activity catalog uses. Duplicated rather
    /// than imported: the bridge runs before any recorder exists.
    static func name(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .walking: "Walk"
        case .running: "Run"
        case .cycling: "Cycle"
        case .traditionalStrengthTraining: "Strength"
        case .yoga: "Yoga"
        default: "Other"
        }
    }
    static func icon(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .walking: "figure.walk"
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .traditionalStrengthTraining: "dumbbell"
        case .yoga: "figure.yoga"
        default: "figure.mixed.cardio"
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            self.onStateChange?(toState, date)
            if toState == .ended { self.endPlaceholderActivity(); self.end() }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in if self.session === workoutSession { self.end() } }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            for item in data { self.onPacket?(item) }
        }
    }
}

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
    var onControlFailure: ((String) -> Void)?
    var onStateChange: ((HKWorkoutSessionState, Date) -> Void)?
    /// The mirrored session stopped reaching the phone: the watch walked out
    /// of range, or the session failed. The workout carries on on the wrist;
    /// this only means the phone can no longer see or steer it.
    var onDisconnect: (() -> Void)?
    /// A focus session listens for heart rate only. A mind-and-body session
    /// is always a focus session: it never reaches `onSession` or the other
    /// workout callbacks, so no recorder adopts it and nothing is saved to Health.
    var onFocusPacket: ((Data) -> Void)?
    nonisolated static func isFocus(_ session: HKWorkoutSession) -> Bool { session.workoutConfiguration.activityType == .mindAndBody }
    var isFocusSession: Bool { session.map(Self.isFocus) ?? false }
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
                if unattended, !isFocus(session) { bridge.requestPlaceholderActivity(for: session) }
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
        if Self.isFocus(session) {
            // No focus session is listening (the app was relaunched): end it
            // on the wrist rather than leave it running.
            if onFocusPacket == nil { end(after: .discard) }
            return
        }
        onSession?(session)
    }

    func send(_ command: PhoneCommand, maxHeartRate: Int? = nil, badminton: BadmintonSession? = nil,
              athlete: ActivityAthleteProfile? = nil, completion: ((Bool) -> Void)? = nil) {
        guard let session, let data = try? WatchWire.encode(PhoneCommandEnvelope(command: command, sentAt: .now,
                                                                                  maxHeartRate: maxHeartRate, badminton: badminton,
                                                                                  athlete: athlete)) else {
            onControlFailure?("Apple Watch is unavailable. Use the controls on your Watch.")
            completion?(false); return
        }
        if command == .discard { dropping = true }
        session.sendToRemoteWorkoutSession(data: data) { success, _ in
            Task { @MainActor in
                guard self.session === session else { completion?(false); return }
                if !success { self.dropping = false; self.onControlFailure?("The command did not reach Apple Watch. Your workout is still controlled on the Watch.") }
                completion?(success)
            }
        }
    }

    /// Sends a last command and drops the session only once it has left, in
    /// the send's completion handler: releasing the session in the same
    /// run-loop turn can cancel the send before the watch ever hears it.
    func end(after command: PhoneCommand) {
        dropping = true
        send(command) { success in
            if success { self.end() } else { self.dropping = false }
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

    /// The catalog's name and symbol for the type the wrist started, so the
    /// placeholder Live Activity matches the card the recorder shows later.
    static func name(for type: HKWorkoutActivityType) -> String {
        (ActivityCatalog.type(healthRawValue: type.rawValue) ?? ActivityCatalog.other).name
    }
    static func icon(for type: HKWorkoutActivityType) -> String {
        (ActivityCatalog.type(healthRawValue: type.rawValue) ?? ActivityCatalog.other).symbol
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            guard !self.dropping else { return }
            if !self.isFocusSession { self.onStateChange?(toState, date) }
            if toState == .ended { self.endPlaceholderActivity(); self.end() }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            // Dropped silently before: the recorder kept a running timer for
            // a session that no longer existed, with every control failing.
            let focus = self.isFocusSession
            self.end()
            if !focus { self.onDisconnect?() }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        Task { @MainActor in
            guard self.session === workoutSession, !self.dropping else { return }
            let focus = self.isFocusSession
            self.end()
            if !focus { self.onDisconnect?() }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            for item in data {
                if self.isFocusSession { self.onFocusPacket?(item) } else { self.onPacket?(item) }
            }
        }
    }
}

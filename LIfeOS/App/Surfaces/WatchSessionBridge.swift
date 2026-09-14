import Foundation
import HealthKit
import WatchConnectivity
import AppSurfaces

/// Owns the workout session mirrored from the watch. One per app: HealthKit
/// hands the session to whichever handler is installed at launch, so the
/// bridge is installed by the app delegate and the recorder subscribes.
@MainActor
final class WatchSessionBridge: NSObject, HKWorkoutSessionDelegate {
    static let shared = WatchSessionBridge()
    private static let healthStore = HKHealthStore()

    private(set) var session: HKWorkoutSession?
    var onSession: ((HKWorkoutSession) -> Void)?
    var onPacket: ((Data) -> Void)?
    var onStateChange: ((HKWorkoutSessionState, Date) -> Void)?
    var hasSession: Bool { session != nil }

    /// Call once at launch, before any session can arrive.
    static func installMirroringHandler() {
        healthStore.workoutSessionMirroringStartHandler = { session in
            Task { @MainActor in WatchSessionBridge.shared.adopt(session) }
        }
    }

    /// Whether a watch could take the session right now.
    static var watchAvailable: Bool {
        guard WCSession.isSupported() else { return false }
        let wc = WCSession.default
        return wc.activationState == .activated && wc.isPaired && wc.isWatchAppInstalled && wc.isReachable
    }

    /// Ask the watch to open Almanac with this workout.
    static func startWatchApp(_ configuration: HKWorkoutConfiguration) async throws {
        try await healthStore.startWatchApp(toHandle: configuration)
    }

    func adopt(_ session: HKWorkoutSession) {
        self.session?.delegate = nil
        self.session = session
        session.delegate = self
        onSession?(session)
    }

    func send(_ command: PhoneCommand, maxHeartRate: Int? = nil) {
        guard let session, let data = try? WatchWire.encode(PhoneCommandEnvelope(command: command, sentAt: .now, maxHeartRate: maxHeartRate)) else { return }
        session.sendToRemoteWorkoutSession(data: data) { _, _ in }
    }

    func end() {
        session?.delegate = nil
        session = nil
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            self.onStateChange?(toState, date)
            if toState == .ended { self.end() }
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

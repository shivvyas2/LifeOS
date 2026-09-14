import SwiftUI
import SwiftData
import WidgetKit
import WatchConnectivity
import AppSurfaces
import Persistence

@MainActor @Observable
final class SurfaceCoordinator: NSObject, WCSessionDelegate {
    static let shared = SurfaceCoordinator()
    var pendingRoute: SurfaceRoute?
    private(set) var snapshot: SurfaceSnapshot?
    private var ownerID: String?
    private var context: ModelContext?
    private var watchSession: WCSession?
    var sharingEnabled: Bool {
        get { UserDefaults.currentAccount.object(forKey: "surface.sharing") as? Bool ?? true }
        set {
            UserDefaults.currentAccount.set(newValue, forKey: "surface.sharing")
            if newValue { publish() } else { write(SurfaceSnapshot()) }
        }
    }
    func adopt(ownerID: String?, context: ModelContext?) {
        self.ownerID = ownerID; self.context = context
        if SurfaceSnapshot.read()?.ownerID != ownerID || ownerID == nil || !sharingEnabled { write(SurfaceSnapshot()) }
        if WCSession.isSupported(), watchSession == nil {
            watchSession = WCSession.default
            watchSession?.delegate = self
            watchSession?.activate()
        }
        publish()
    }
    func clear() {
        ownerID = nil; context = nil; pendingRoute = nil
        write(SurfaceSnapshot())
    }
    func publish() {
        guard let ownerID, let context, sharingEnabled else { return }
        let store = MetricsStore(context: context)
        let now = Date.now
        let row = try? store.metrics(from: now, to: now).first
        let goals = try? context.fetch(FetchDescriptor<UserGoals>()).first
        let next = SurfaceSnapshot(ownerID: ownerID, measuredAt: row?.updatedAt,
            steps: row?.steps, stepGoal: goals?.stepsGoal ?? 8000,
            sleepMinutes: row?.sleepMinutes, exerciseMinutes: row?.exerciseMinutes)
        // Coalesce saves unrelated to health. Still renew the Watch lease hourly.
        if let previous = snapshot, previous.ownerID == next.ownerID,
           previous.steps == next.steps, previous.sleepMinutes == next.sleepMinutes,
           previous.exerciseMinutes == next.exerciseMinutes, previous.stepGoal == next.stepGoal,
           previous.measuredAt == next.measuredAt,
           next.generatedAt.timeIntervalSince(previous.generatedAt) < 3600 { return }
        write(next)
    }
    private func write(_ next: SurfaceSnapshot) {
        snapshot = next
        next.write()
        WidgetCenter.shared.reloadAllTimelines()
        sendToWatch()
    }
    private func sendToWatch() {
        guard let watchSession, watchSession.activationState == .activated,
              watchSession.isPaired, watchSession.isWatchAppInstalled,
              let snapshot, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? watchSession.updateApplicationContext(["snapshot": data])
        if watchSession.isReachable { watchSession.sendMessageData(data, replyHandler: nil, errorHandler: nil) }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.sendToWatch() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data,
                            replyHandler: @escaping (Data) -> Void) {
        // An explicit Watch refresh asks for the current projection, never tokens.
        let reply = SurfaceSnapshot.read() ?? SurfaceSnapshot()
        replyHandler((try? JSONEncoder().encode(reply)) ?? Data())
        Task { @MainActor in self.publish() }
    }
}

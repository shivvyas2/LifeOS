import SwiftUI
import SwiftData
import WidgetKit
import WatchConnectivity
import AppSurfaces
import Persistence
import Integrations

@MainActor @Observable
final class SurfaceCoordinator: NSObject, WCSessionDelegate {
    static let shared = SurfaceCoordinator()
    var pendingRoute: SurfaceRoute?
    private(set) var snapshot: SurfaceSnapshot?
    private(set) var agenda: AgendaSnapshot?
    private var ownerID: String?
    var workoutOwnerID: String? { ownerID }
    private var workoutBinding = WatchAccountBinding(ownerID: nil)
    private let inboxKey = "watch.workout.inbox.v1"
    private var workoutInbox: [WatchWorkoutSummary] = UserDefaults.standard.data(forKey: "watch.workout.inbox.v1").flatMap { try? JSONDecoder().decode([WatchWorkoutSummary].self, from: $0) } ?? []
    private var context: ModelContext?
    private var watchSession: WCSession?
    var sharingEnabled: Bool {
        get { UserDefaults.currentAccount.object(forKey: "surface.sharing") as? Bool ?? true }
        set {
            UserDefaults.currentAccount.set(newValue, forKey: "surface.sharing")
            if newValue { publish() } else { writeTombstones() }
        }
    }
    /// Told when a watch workout has been imported, so a phone timer still
    /// running for that same workout can close instead of counting forever.
    var onWatchWorkoutImported: ((WatchWorkoutSummary) -> Void)?

    func adopt(ownerID: String?, context: ModelContext?) {
        self.ownerID = ownerID; self.context = context
        workoutBinding = WatchAccountBinding(ownerID: ownerID, athlete: ActivityAthleteProfile.load(from: .currentAccount))
        if SurfaceSnapshot.read()?.ownerID != ownerID || ownerID == nil || !sharingEnabled { writeTombstones() }
        if WCSession.isSupported(), watchSession == nil {
            watchSession = WCSession.default
            watchSession?.delegate = self
            watchSession?.activate()
        }
        publish(); sendToWatch(); importWatchWorkouts()
    }
    func publishAthleteProfile() {
        guard let ownerID else { return }
        workoutBinding = WatchAccountBinding(ownerID: ownerID, athlete: ActivityAthleteProfile.load(from: .currentAccount))
        sendToWatch()
    }
    func clear() {
        ownerID = nil; context = nil; pendingRoute = nil
        workoutBinding = WatchAccountBinding(ownerID: nil)
        workoutInbox = []; persistWorkoutInbox()
        writeTombstones()
    }
    func publish() {
        importWatchWorkouts()
        guard let ownerID, let context, sharingEnabled else { return }
        publishAgenda(ownerID: ownerID, context: context)
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
    /// Two weeks of events from the start of this calendar week, for the
    /// agenda widget. Coalesced on content so unrelated saves do not rewrite
    /// the file; the week start is part of the key so midnight on Sunday
    /// still publishes.
    private func publishAgenda(ownerID: String, context: ModelContext) {
        let window = AgendaSnapshot.window(around: .now)
        let rows = (try? CalendarStore(context: context).events(from: window.start, to: window.end)) ?? []
        let next = AgendaSnapshot(ownerID: ownerID, events: rows.map {
            AgendaSnapshot.Event(id: $0.id, title: $0.title, calendarTitle: $0.calendarTitle,
                                 startDate: $0.startDate, endDate: $0.endDate, isAllDay: $0.isAllDay)
        })
        if let previous = agenda, previous.ownerID == next.ownerID, previous.events == next.events,
           previous.weekStart == next.weekStart,
           next.generatedAt.timeIntervalSince(previous.generatedAt) < 3600 { return }
        writeAgenda(next)
    }
    private func writeAgenda(_ next: AgendaSnapshot) {
        agenda = next
        next.write()
        WidgetCenter.shared.reloadTimelines(ofKind: AgendaSnapshot.widgetKind)
    }
    /// Sign-out, account switch, and sharing off replace every shared envelope.
    private func writeTombstones() {
        write(SurfaceSnapshot())
        writeAgenda(AgendaSnapshot())
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
        var context: [String: Any] = ["snapshot": data]
        if let account = try? JSONEncoder().encode(workoutBinding) { context["workoutAccount"] = account }
        try? watchSession.updateApplicationContext(context)
        if watchSession.isReachable { watchSession.sendMessage(context, replyHandler: nil, errorHandler: nil) }
        if watchSession.isReachable { watchSession.sendMessageData(data, replyHandler: nil, errorHandler: nil) }
    }
    private func persistWorkoutInbox() {
        if let data = try? JSONEncoder().encode(workoutInbox) { UserDefaults.standard.set(data, forKey: inboxKey) }
    }
    /// Both mirrored and offline finishes use the same stable record ID.
    private func importWatchWorkouts() {
        guard !workoutInbox.isEmpty, let ownerID, let context else { return }
        for received in workoutInbox {
            // A badminton review that fails its checks is dropped on its own;
            // the workout it came with is still imported and receipted.
            guard let summary = received.salvaged(for: ownerID) else {
                workoutInbox.removeAll { $0.id == received.id }; continue
            }
            do {
                guard try WatchWorkoutImporter.save(summary, ownerID: ownerID, context: context) else { continue }
                workoutInbox.removeAll { $0.id == summary.id }
                onWatchWorkoutImported?(summary)
                if let watchSession, watchSession.activationState == .activated {
                    watchSession.transferUserInfo(["workoutReceipt": summary.id.uuidString, "ownerID": ownerID])
                }
            } catch { break } // Keep the durable inbox for the next account adoption/refresh.
        }
        persistWorkoutInbox()
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let data = userInfo["workoutSummary"] as? Data, data.count <= 2_000_000,
              let summary = try? JSONDecoder().decode(WatchWorkoutSummary.self, from: data) else { return }
        Task { @MainActor in
            guard self.ownerID == nil || summary.ownerID == self.ownerID else { return }
            self.workoutInbox.removeAll { $0.id == summary.id }
            self.workoutInbox.append(summary); self.persistWorkoutInbox(); self.importWatchWorkouts()
        }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.sendToWatch(); self.importWatchWorkouts() }
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

import SwiftUI
import WidgetKit
import WatchConnectivity
import AppSurfaces

@main
struct AlmanacWatchApp: App {
    @State private var bridge = WatchBridge()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            WatchDashboard(bridge: bridge)
                .task { bridge.start() }
                .onOpenURL { _ in bridge.refresh() }
                .onChange(of: scenePhase) { _, phase in if phase == .active { bridge.refresh() } }
        }
    }
}

@MainActor @Observable
final class WatchBridge: NSObject, WCSessionDelegate {
    var snapshot: SurfaceSnapshot? = .read()
    var status = "Synced from iPhone"
    private var session: WCSession?
    func start() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--design-preview") {
            snapshot = SurfaceSnapshot(ownerID: "watch-preview", measuredAt: .now, steps: 6240, sleepMinutes: 452, exerciseMinutes: 24)
            status = "Design preview"
            return
        }
        #endif
        guard session == nil, WCSession.isSupported() else { return }
        session = WCSession.default; session?.delegate = self; session?.activate()
    }
    func refresh() {
        guard let session, session.activationState == .activated, session.isReachable else {
            status = "Open Almanac on your iPhone to sync."
            return
        }
        status = "Updating…"
        session.sendMessageData(Data(), replyHandler: { [weak self] data in
            Task { @MainActor in self?.receive(data) }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in self?.status = "iPhone unavailable. Try again nearby." }
        })
    }
    private func receive(_ data: Data) {
        guard let next = try? JSONDecoder().decode(SurfaceSnapshot.self, from: data) else {
            status = "Open Almanac on your iPhone to sync."; return
        }
        if next.supersedes(snapshot) {
            snapshot = next; next.write(); WidgetCenter.shared.reloadAllTimelines()
        }
        status = "Synced from iPhone"
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let data = session.receivedApplicationContext["snapshot"] as? Data
        Task { @MainActor in
            if let data { self.receive(data) }
            self.refresh()
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["snapshot"] as? Data else { return }
        Task { @MainActor in self.receive(data) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in self.receive(messageData) }
    }
}

struct WatchDashboard: View {
    @Bindable var bridge: WatchBridge
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("A little progress.").font(.title3.bold())
                        if let data = bridge.snapshot, data.isAvailable(at: timeline.date) {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Steps", systemImage: "figure.walk").font(.caption)
                                Text(data.steps.map { $0.formatted() } ?? "—").font(.system(size: 36, weight: .bold, design: .rounded)).minimumScaleFactor(0.7)
                                ProgressView(value: data.stepProgress).tint(Color(white: 0.12))
                                Text("of \(data.stepGoal.formatted()) today").font(.caption2)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                                .foregroundStyle(Color(white: 0.1))
                                .background(Color(red: 1, green: 0.8, blue: 0.66), in: RoundedRectangle(cornerRadius: 20))
                                .privacySensitive()
                            reading("Sleep", value: data.sleepText, icon: "moon.fill", tint: Color(red: 0.84, green: 0.81, blue: 0.97))
                            reading("Movement", value: "\(data.exerciseMinutes.map(String.init) ?? "—") min", icon: "flame.fill", tint: Color(red: 0.82, green: 0.90, blue: 0.7))
                            if let date = data.measuredAt {
                                Text("Updated \(date, style: .time)").font(.caption2).foregroundStyle(.secondary)
                            }
                        } else {
                            Image(systemName: "sun.max.fill").font(.largeTitle).foregroundStyle(.orange).padding(.vertical, 8)
                            Text("Your day, at a glance.").font(.headline)
                            Text("Sign in to Almanac on your iPhone and sync your health data. Enable sharing in Settings → Widgets & Watch.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Button(action: bridge.refresh) { Label("Refresh", systemImage: "arrow.clockwise") }.tint(.orange)
                        Text(bridge.status).font(.caption2).foregroundStyle(.secondary)
                    }.padding(.horizontal, 4)
                }
            }
            .navigationTitle("Almanac")
        }
    }
    private func reading(_ title: String, value: String, icon: String, tint: Color) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(tint)
            Text(title).font(.caption)
            Spacer(minLength: 2)
            Text(value).font(.system(.body, weight: .semibold)).minimumScaleFactor(0.7)
        }.padding(12).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16)).privacySensitive()
    }
}

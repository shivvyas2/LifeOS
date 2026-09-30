import SwiftUI
import WidgetKit
import WatchConnectivity
import HealthKit
import UIKit
import AppSurfaces

/// The catalog's symbol, or the generic figure when this OS lacks it, so a
/// name that exists on the phone but not here never draws as nothing.
func activitySymbol(_ name: String) -> Image {
    UIImage(systemName: name) == nil ? Image(systemName: "figure.mixed.cardio") : Image(systemName: name)
}

@main
struct AlmanacWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @State private var bridge = WatchBridge()
    @State private var workout = WatchWorkoutController()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if workout.state != .idle {
                    WatchWorkoutScreen(workout: workout)
                } else {
                    WatchDashboard(bridge: bridge, workout: workout, onStartWorkout: { type in workout.start(type: type) })
                }
            }
            .task {
                bridge.onAccountChanged = { workout.accountChanged(to: $0) }
                workout.accountChanged(to: bridge.binding?.ownerID)
                if let profile = bridge.binding?.athlete, profile.isValid { workout.athlete = profile }
                bridge.onAthleteChanged = { profile in
                    guard let profile, profile.isValid, workout.athlete.map({ profile.updatedAt > $0.updatedAt }) ?? true else { return }
                    workout.athlete = profile
                }
                workout.onFinished = { bridge.enqueue($0) }
                bridge.start()
                #if DEBUG
                if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--workout-preview=") }) {
                    workout.loadPreview(String(argument.dropFirst("--workout-preview=".count)))
                }
                #endif
                // Either order must reach `start`: the handler catches a
                // configuration that arrives later, the pending one catches
                // a configuration that arrived before this ran.
                WatchAppDelegate.onConfiguration = { configuration in workout.startFromPhone(configuration) }
                if let pending = WatchAppDelegate.pendingConfiguration {
                    WatchAppDelegate.pendingConfiguration = nil
                    workout.startFromPhone(pending)
                }
                // Same before/after ordering for a relaunch over a session
                // that is still active in HealthKit.
                WatchAppDelegate.onRecovery = { Task { @MainActor in await workout.recover() } }
                if WatchAppDelegate.pendingRecovery {
                    WatchAppDelegate.pendingRecovery = false
                    await workout.recover()
                }
            }
            .sheet(isPresented: $workout.needsAthleteSetup) { WatchAthleteSetup(workout: workout) }
            .onOpenURL { _ in bridge.refresh() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { bridge.refresh() } }
        }
    }
}

@MainActor @Observable
final class WatchBridge: NSObject, WCSessionDelegate {
    var snapshot: SurfaceSnapshot? = .read()
    var status = "Ready to record on Watch"
    var binding: WatchAccountBinding? = UserDefaults.standard.data(forKey: "watch.account").flatMap { try? JSONDecoder().decode(WatchAccountBinding.self, from: $0) }
    var onAccountChanged: ((String?) -> Void)?
    var onAthleteChanged: ((ActivityAthleteProfile?) -> Void)?
    var pending: [WatchWorkoutSummary] = UserDefaults.standard.data(forKey: "watch.outbox").flatMap { try? JSONDecoder().decode([WatchWorkoutSummary].self, from: $0) } ?? []
    func enqueue(_ summary: WatchWorkoutSummary) {
        guard summary.ownerID == binding?.ownerID else { return }
        pending.removeAll { $0.id == summary.id }; pending.append(summary)
        persistQueue(); flush()
    }
    private func persistQueue() {
        if let data = try? JSONEncoder().encode(pending) { UserDefaults.standard.set(data, forKey: "watch.outbox") }
    }
    private func flush() {
        guard let session, session.activationState == .activated else { return }
        for summary in pending where summary.ownerID == binding?.ownerID {
            guard !session.outstandingUserInfoTransfers.contains(where: { ($0.userInfo["workoutID"] as? String) == summary.id.uuidString }),
                  let data = try? JSONEncoder().encode(summary) else { continue }
            session.transferUserInfo(["workoutSummary": data, "workoutID": summary.id.uuidString])
        }
    }
    private func receiveBinding(_ data: Data) {
        guard let next = try? JSONDecoder().decode(WatchAccountBinding.self, from: data), next.supersedes(binding) else { return }
        let changed = binding?.ownerID != next.ownerID
        binding = next; UserDefaults.standard.set(data, forKey: "watch.account")
        if changed {
            pending.removeAll { $0.ownerID != next.ownerID }; persistQueue()
            for transfer in session?.outstandingUserInfoTransfers ?? [] { transfer.cancel() }
            onAccountChanged?(next.ownerID)
        }
        onAthleteChanged?(next.athlete)
        flush()
    }
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
            status = "Phone away · workouts still record here"
            return
        }
        flush()
        status = "Updating…"
        session.sendMessageData(Data(), replyHandler: { [weak self] data in
            Task { @MainActor in self?.receive(data) }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in self?.status = "Phone away · syncs when connected" }
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
        let account = session.receivedApplicationContext["workoutAccount"] as? Data
        Task { @MainActor in
            if let account { self.receiveBinding(account) }
            if let data { self.receive(data) }
            self.flush(); self.refresh()
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext["snapshot"] as? Data
        let account = applicationContext["workoutAccount"] as? Data
        Task { @MainActor in
            if let account { self.receiveBinding(account) }
            if let data { self.receive(data) }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let data = message["snapshot"] as? Data
        let account = message["workoutAccount"] as? Data
        Task { @MainActor in
            if let account { self.receiveBinding(account) }
            if let data { self.receive(data) }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let id = userInfo["workoutReceipt"] as? String, let owner = userInfo["ownerID"] as? String else { return }
        Task { @MainActor in
            self.pending.removeAll { $0.id.uuidString == id && $0.ownerID == owner }
            self.persistQueue()
        }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.flush() }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in self.receive(messageData) }
    }
}

struct WatchDashboard: View {
    @Bindable var bridge: WatchBridge
    let workout: WatchWorkoutController
    var onStartWorkout: (HKWorkoutActivityType) -> Void
    @State private var isChoosingWorkout = false
    private let featured = ["Badminton", "Run", "Strength", "Yoga"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Make your move.").font(.system(.title3, design: .rounded, weight: .bold))
                Text("Start here. Take it anywhere.").font(.caption2).foregroundStyle(.secondary)
                if let error = workout.lastError { Text(error).font(.caption2).foregroundStyle(.orange) }
                if let result = workout.result { Label(result, systemImage: "checkmark.circle.fill").font(.caption2).foregroundStyle(.mint) }
                ForEach(featured.compactMap { ActivityCatalog.type(named: $0) }) { type in
                    Button { start(type) } label: {
                        HStack(spacing: 10) {
                            activitySymbol(type.symbol).font(.system(size: 28)).foregroundStyle(WatchPalette.color(for: type)).frame(width: 32)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(type.name).font(.headline)
                                Text(subtitle(type)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "play.fill").font(.caption2).foregroundStyle(.orange)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background { WatchTileBackground(color: WatchPalette.theme(for: type).tint, companion: WatchPalette.theme(for: type).glow) }
                    }.buttonStyle(.plain).accessibilityLabel("Start \(type.name) workout")
                }
                Button { isChoosingWorkout = true } label: { Label("All activities", systemImage: "square.grid.2x2") }
                    .buttonStyle(.glass).tint(.orange)
                if let data = bridge.snapshot, data.isAvailable() {
                    Text("Your day").font(.headline).padding(.top, 6)
                    reading("Steps", value: data.steps.map { $0.formatted() } ?? "—", icon: "figure.walk", tint: .cyan)
                    reading("Sleep", value: data.sleepText, icon: "moon.fill", tint: .purple)
                    reading("Movement", value: "\(data.exerciseMinutes.map(String.init) ?? "—") min", icon: "flame.fill", tint: .orange)
                }
                if !bridge.pending.isEmpty {
                    Text("\(bridge.pending.count) workout(s) waiting to sync").font(.caption2).foregroundStyle(.orange)
                }
                if bridge.binding?.ownerID == nil {
                    Text("Workouts save to Apple Health. Open Almanac on iPhone to link your account for app syncing.").font(.caption2).foregroundStyle(.secondary)
                }
                Button("Your movement", systemImage: "figure.stand") { workout.needsAthleteSetup = true }.buttonStyle(.glass)
                Button(action: bridge.refresh) { Label("Sync iPhone", systemImage: "arrow.triangle.2.circlepath") }.buttonStyle(.glass)
                Text(bridge.status).font(.caption2).foregroundStyle(.secondary)
            }.padding(.horizontal, 2)
        }
        .containerBackground(for: .navigation) { WatchActivityBackdrop(theme: WatchPalette.theme(for: ActivityCatalog.other)) }
        .navigationTitle("Almanac")
        .sheet(isPresented: $isChoosingWorkout) {
            NavigationStack {
                List {
                    ForEach(ActivityCatalog.grouped(), id: \.group) { section in
                        Section(section.group.rawValue) {
                            ForEach(section.types) { type in
                                Button { isChoosingWorkout = false; start(type) } label: {
                                    Label { Text(type.name) } icon: { activitySymbol(type.symbol).foregroundStyle(WatchPalette.color(for: type)) }
                                }
                            }
                        }
                    }
                }.navigationTitle("Activities")
            }
        }
    }
    private func start(_ type: ActivityType) { onStartWorkout(HKWorkoutActivityType(rawValue: type.healthRawValue) ?? .other) }
    private func subtitle(_ type: ActivityType) -> String {
        switch WatchWorkoutLayout.forActivity(type) {
        case .court: return "Court time · heart rate"
        case .distance: return "Distance · pace · heart rate"
        case .strength: return "Reps · sets · heart rate"
        case .mindful: return "Time · heart rate"
        case .general: return "Time · energy · heart rate"
        }
    }
    private func reading(_ title: String, value: String, icon: String, tint: Color) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(tint)
            Text(title).font(.caption)
            Spacer(minLength: 2)
            Text(value).font(.system(.body, weight: .semibold)).minimumScaleFactor(0.7)
        }.padding(12).background { WatchTileBackground(color: tint) }.privacySensitive()
    }
}

/// Also works without the phone. Measurements are optional; motion is opt-in.
private struct WatchAthleteSetup: View {
    let workout: WatchWorkoutController
    @State private var height = 170
    @State private var weight = 70
    @State private var includeMeasurements = false
    @State private var hand: ActivityAthleteProfile.Side = .right
    @State private var wrist: ActivityAthleteProfile.Side = .left
    @State private var enabled = false
    var body: some View {
        NavigationStack {
            Form {
                Text("One setup for every activity").font(.headline)
                Toggle("Add measurements", isOn: $includeMeasurements)
                if includeMeasurements {
                    Picker("Height · cm", selection: $height) { ForEach(80...250, id: \.self) { Text("\($0)").tag($0) } }
                    Picker("Weight · kg", selection: $weight) { ForEach(20...350, id: \.self) { Text("\($0)").tag($0) } }
                }
                Picker("Playing hand", selection: $hand) { ForEach(ActivityAthleteProfile.Side.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                Picker("Watch wrist", selection: $wrist) { ForEach(ActivityAthleteProfile.Side.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                Toggle("Swing analysis", isOn: $enabled)
                Text("Badminton experiment. Wear Watch on your racket wrist; hold still for one second at start. Counts include practice swings. No contact, posture or court tracking.").font(.caption2)
                if enabled && hand != wrist { Text("Move Watch to your playing wrist and update this setting to enable swings.").font(.caption2).foregroundStyle(.orange) }
                Text("Optional measurements personalize your profile, not motion accuracy.").font(.caption2)
                Button("Save & continue") {
                    workout.completeAthleteSetup(.init(heightCM: includeMeasurements ? Double(height) : nil,
                        weightKG: includeMeasurements ? Double(weight) : nil, playingHand: hand, watchWrist: wrist, motionEnabled: enabled))
                }.tint(.orange)
            }.navigationTitle("Your movement")
            .onAppear {
                guard let profile = workout.athlete else { return }
                height = Int(profile.heightCM ?? 170); weight = Int(profile.weightKG ?? 70)
                includeMeasurements = profile.heightCM != nil || profile.weightKG != nil
                hand = profile.playingHand; wrist = profile.watchWrist; enabled = profile.motionEnabled
            }
        }
    }
}

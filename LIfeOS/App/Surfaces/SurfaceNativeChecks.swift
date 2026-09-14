#if DEBUG
import Foundation
import SwiftData
import Persistence
import AppSurfaces

@MainActor
enum SurfaceNativeChecks {
    static func run() -> [String] {
        var checks: [String] = []
        func check(_ passes: Bool, _ title: String) { checks.append("\(passes ? "PASS" : "FAIL") \(title)") }
        let a = "surface-check-a-\(UUID())", b = "surface-check-b-\(UUID())"
        let push = PushService.shared
        defer {
            push.attach(ownerID: nil)
            SurfaceCoordinator.shared.clear()
            for owner in [a, b] {
                let suite = UserScope(id: owner).defaultsSuiteName
                UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            }
        }
        push.attach(ownerID: a)
        let first = InboxEntry(ownerID: a, text: "Sample check-in", trigger: "rest", day: "2026-09-14")
        check(push.receive(first), "Current-account notification accepted")
        _ = push.receive(first)
        check(push.entries.count == 1, "Repeat delivery deduplicated")
        push.markRead(first.id)
        push.attach(ownerID: b)
        check(push.entries.isEmpty && push.pending == nil, "Switch clears visible inbox and pending route")
        check(!push.receive(first, open: true) && push.pending == nil, "Delayed notification from previous account rejected")
        push.attach(ownerID: a)
        check(push.entries.count == 1 && push.unreadCount == 0, "Account inbox and read status restored")
        push.clearRead()
        push.attach(ownerID: a)
        check(!push.receive(first) && push.entries.isEmpty, "Cleared check-in cannot be restored by duplicate delivery")
        do {
            let container = try ModelContainer(for: DailyMetrics.self, UserGoals.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let now = Date.now
            let store = MetricsStore(context: container.mainContext)
            try store.upsert(date: now) { $0.steps = 6400; $0.sleepMinutes = 450 }
            try store.upsert(date: now.addingTimeInterval(-86400)) { $0.steps = 99999 }
            let coordinator = SurfaceCoordinator.shared
            coordinator.adopt(ownerID: a, context: container.mainContext)
            check(SurfaceSnapshot.read()?.steps == 6400, "Widget exports today's data, not a historical day")
            coordinator.clear()
            check(SurfaceSnapshot.read()?.ownerID == nil && SurfaceSnapshot.read()?.steps == nil, "Sign-out replaces shared health cache with an empty snapshot")
            let empty = try ModelContainer(for: DailyMetrics.self, UserGoals.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            coordinator.adopt(ownerID: b, context: empty.mainContext)
            check(SurfaceSnapshot.read()?.ownerID == b && SurfaceSnapshot.read()?.steps == nil, "Next account starts with missing readings, never previous values")
        } catch { check(false, "Native snapshot checks: \(error.localizedDescription)") }
        return checks
    }
}
#endif

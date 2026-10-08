import UserNotifications
import Soundscape

/// The bell at each block's end, scheduled ahead so it rings with the
/// phone locked. A sleep fade ends quietly, with no notification.
@MainActor
struct FocusNotifications {
    private static let prefix = "focus."

    func schedule(_ ends: [PhaseEnd], plan: TimerPlan) async {
        await cancel()
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        var restMinutes = 5, longRestMinutes = 15
        if case .pomodoro(_, let rest, let longRest, _, _) = plan {
            restMinutes = Int(rest / 60); longRestMinutes = Int(longRest / 60)
        }
        for (index, end) in ends.enumerated() where end.ending != .fading {
            let content = UNMutableNotificationContent()
            switch end.next {
            case .rest: content.title = "Break time"; content.body = "\(restMinutes) minutes. Stand up, look away."
            case .longRest(let block): content.title = "Long break"; content.body = "\(block) blocks done. Take \(longRestMinutes) minutes."
            case .work(let block): content.title = "Back to focus"; content.body = "Block \(block) is starting."
            case .finished: content.title = "Session complete"; content.body = "Nice work."
            case .open, .fading: continue
            }
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.at.timeIntervalSinceNow), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "\(Self.prefix)\(index)", content: content, trigger: trigger))
        }
    }

    func cancel() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}

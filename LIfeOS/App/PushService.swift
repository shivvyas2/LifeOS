import Foundation
import OSLog
import UIKit
import UserNotifications
import Integrations
import Persistence
import AppSurfaces

private let pushLog = Logger(subsystem: "com.shivvyas.lifeos", category: "push")

/// Registration for proactive nudges, and the inbox a tapped one lands in.
///
/// One object rather than two because the two halves share the piece of state
/// that matters: the device token. It arrives asynchronously from the system
/// long after the sign-in that asked for it, and it is needed again at sign
/// out to delete the row.
///
/// Nothing here decides whether to say anything. That judgement is the
/// server's, in `_shared/nudge.ts`, where it is a pure function with tests. The
/// device's whole job is to be reachable and to open on what arrived.
@MainActor @Observable
final class PushService {
    static let shared = PushService()

    /// The nudge a tapped notification carried, waiting for the UI to open on
    /// it. Cleared by whoever opens it, so a second tap on the same
    /// notification is a second open rather than a no-op.
    var pending: NudgePayload?
    private(set) var entries: [InboxEntry] = []
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private var ownerID: String?
    private var inboxDefaults: UserDefaults?
    private var dismissedIDs: Set<String> = []
    var unreadCount: Int { entries.filter { !$0.isRead }.count }

    #if DEBUG
    /// Previews need a day's nudges without a push: seeds the inbox in memory.
    func previewSeed(entries: [InboxEntry]) { self.entries = entries }
    #endif

    func attach(ownerID: String?) {
        if self.ownerID != ownerID { pending = nil }
        self.ownerID = ownerID
        inboxDefaults = ownerID.flatMap { UserDefaults(suiteName: UserScope(id: $0).defaultsSuiteName) }
        dismissedIDs = Set(inboxDefaults?.stringArray(forKey: "notificationInbox.dismissed") ?? [])
        entries = inboxDefaults?.data(forKey: "notificationInbox").flatMap {
            try? JSONDecoder().decode([InboxEntry].self, from: $0)
        }?.filter { $0.ownerID == ownerID } ?? []
        updateBadge()
    }
    func receive(_ entry: InboxEntry, open: Bool = false) -> Bool {
        guard let ownerID, ownerID == entry.ownerID, !dismissedIDs.contains(entry.id) else { return false }
        entries = InboxEntry.inserting(entry, into: entries, ownerID: ownerID)
        if open {
            markRead(entry.id)
            pending = NudgePayload(text: entry.text, trigger: entry.trigger, day: entry.day)
        }
        persistInbox()
        return true
    }
    func markRead(_ id: String) {
        if let index = entries.firstIndex(where: { $0.id == id }) { entries[index].isRead = true }
        persistInbox()
    }
    func markAllRead() {
        for index in entries.indices { entries[index].isRead = true }
        persistInbox()
    }
    func clearRead() {
        let readIDs = Set(entries.filter(\.isRead).map(\.id))
        dismissedIDs.formUnion(readIDs)
        dismissedIDs = Set(dismissedIDs.sorted().suffix(200))
        inboxDefaults?.set(Array(dismissedIDs), forKey: "notificationInbox.dismissed")
        entries.removeAll { $0.isRead }
        let owner = ownerID
        Task {
            let center = UNUserNotificationCenter.current()
            let delivered = await center.deliveredNotifications()
            let ids = delivered.filter { notification in
                guard let entry = Self.entry(from: notification) else { return false }
                return entry.ownerID == owner && readIDs.contains(entry.id)
            }.map { $0.request.identifier }
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
        persistInbox()
    }
    private func persistInbox() {
        inboxDefaults?.set(try? JSONEncoder().encode(entries), forKey: "notificationInbox")
        updateBadge()
    }
    private func updateBadge() {
        let count = unreadCount
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(count) }
    }
    func refreshInbox() async {
        let center = UNUserNotificationCenter.current()
        authorization = await center.notificationSettings().authorizationStatus
        // Registered whatever the answer. A silent push needs no permission,
        // and it is how a new card purchase reaches the Money tab without the
        // app being opened (see plaid-webhook). Alerts still need the person's
        // yes: iOS will not show a nudge banner to someone who said no.
        UIApplication.shared.registerForRemoteNotifications()
        let delivered = await center.deliveredNotifications()
        for notification in delivered {
            if let entry = Self.entry(from: notification) { _ = receive(entry) }
        }
    }
    nonisolated static func entry(from notification: UNNotification) -> InboxEntry? {
        let info = notification.request.content.userInfo
        guard let ownerID = info["user_id"] as? String,
              let nudge = NudgePayload(userInfo: info) else { return nil }
        return InboxEntry(ownerID: ownerID, text: nudge.text, trigger: nudge.trigger,
                          day: nudge.day, receivedAt: notification.date)
    }

    /// The last token APNs handed us. Kept in defaults as well as in memory
    /// because sign out has to delete the row, and the process may well have
    /// been relaunched since the token arrived.
    private static let tokenKey = "push.deviceToken"

    private var deviceToken: String? {
        get { UserDefaults.standard.string(forKey: Self.tokenKey) }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: Self.tokenKey) }
            else { UserDefaults.standard.removeObject(forKey: Self.tokenKey) }
        }
    }

    private var client: PushTokenClient? {
        guard let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey else { return nil }
        return PushTokenClient(baseURL: url, anonKey: key)
    }

    /// Asks once, then registers with APNs.
    ///
    /// Deliberately not called at launch. A permission prompt on first run,
    /// before the app has shown anyone anything worth being interrupted about,
    /// is the fastest way to a permanent no.
    func requestAuthorization() async {
        defer { Task { await self.refreshInbox() } }
        let centre = UNUserNotificationCenter.current()
        let settings = await centre.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await centre.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            guard granted else {
                pushLog.info("notifications declined")
                return
            }
        case .denied:
            // No banners, but the deferred refresh still registers the token
            // for silent sync pushes.
            return
        default:
            break
        }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Stores the token APNs just issued against the account that is open.
    ///
    /// Keyed to the ACTIVE account. Several accounts can share one device, and
    /// a token left registered under the account that signed out would push one
    /// person's sleep onto a phone showing somebody else's name.
    func adopt(deviceToken data: Data) async {
        let token = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        await syncRegistration()
    }

    /// Pushes the current token and timezone up for whoever is signed in now.
    ///
    /// Safe to call repeatedly: the row is keyed on the token, so this is one
    /// upsert. Called on every foreground as well as after sign in, which is
    /// what keeps the timezone correct for someone who has flown somewhere.
    func syncRegistration() async {
        guard let token = deviceToken, let client else { return }
        guard let session = KeychainAuthSessionStore().load() else { return }
        do {
            try await client.register(
                PushRegistration(token: token),
                userID: session.userID,
                accessToken: session.accessToken
            )
        } catch {
            // Not fatal and not retried here: the next foreground calls this
            // again, and a device that never registers simply never gets a
            // nudge.
            pushLog.error("push registration failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Deletes this device's row. Called on sign out and on account switch,
    /// before the session is thrown away: the delete needs the access token of
    /// the account whose row it is.
    func deregister(accessToken: String) async {
        guard let token = deviceToken, let client else { return }
        do {
            try await client.deregister(token: token, accessToken: accessToken)
        } catch {
            pushLog.error("push deregistration failed: \(String(describing: error), privacy: .public)")
        }
    }
}

/// The system's end of the same thing.
///
/// A UIKit delegate rather than SwiftUI's `onOpenURL`-style hooks, because
/// APNs registration has no SwiftUI equivalent: the token arrives through
/// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` and
/// nowhere else.
final class PushDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        WatchSessionBridge.installMirroringHandler()
        // Every launch, as Apple recommends: the token can change, and a
        // silent sync push needs no permission, so there is nothing to wait
        // for. The token only goes up to the server once someone is signed in.
        application.registerForRemoteNotifications()
        return true
    }

    /// Orientation is decided per screen; see `OrientationLock`. This is the
    /// one place UIKit asks, so it is answered here rather than by a second
    /// delegate.
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { OrientationLock.mask }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in await PushService.shared.adopt(deviceToken: deviceToken) }
    }

    /// A silent push. Today there is one kind: Plaid has something new for a
    /// connected bank, so sync now rather than at the next open. iOS gives
    /// this about thirty seconds, which one sync fits in.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        guard userInfo["kind"] as? String == "plaid-sync" else { return .noData }
        let synced = await MoneyLiveSync.shared.run()
        pushLog.info("plaid sync push handled synced=\(synced, privacy: .public)")
        return synced ? .newData : .failed
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Routine in the simulator, which has no APNs connection.
        pushLog.info("apns registration failed: \(error.localizedDescription, privacy: .public)")
    }

    /// A nudge that arrives while the app is open is still shown. The point of
    /// the channel is that LIFO speaks first; suppressing it because someone
    /// happens to be looking at the app would drop the message entirely, since
    /// nothing else surfaces it.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        guard let entry = PushService.entry(from: notification) else { return [] }
        let accepted = await MainActor.run { PushService.shared.receive(entry) }
        return accepted ? [.banner, .sound, .list, .badge] : []
    }

    /// The tap-through. Puts the nudge in the inbox; the UI opens on it.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let entry = PushService.entry(from: response.notification) else { return }
        await MainActor.run { _ = PushService.shared.receive(entry, open: true) }
    }
}

/// The bridge from a silent push to the Plaid sync.
///
/// The push arrives at the app delegate, which knows nothing about the view
/// models. RootView installs the handler once its integrations are attached
/// to a store. A push that lands before then, on a launch straight into the
/// background, is remembered and run as soon as the handler appears.
@MainActor
final class MoneyLiveSync {
    static let shared = MoneyLiveSync()

    private var handler: (() async -> Bool)?
    private var pending = false

    func install(_ handler: @escaping () async -> Bool) {
        self.handler = handler
        if pending {
            pending = false
            Task { _ = await handler() }
        }
    }

    func run() async -> Bool {
        guard let handler else {
            pending = true
            return false
        }
        return await handler()
    }
}

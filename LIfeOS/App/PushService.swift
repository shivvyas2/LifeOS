import Foundation
import OSLog
import UIKit
import UserNotifications
import Integrations
import Persistence

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
            // Registering anyway would silently succeed and produce a token
            // that can never deliver anything.
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
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in await PushService.shared.adopt(deviceToken: deviceToken) }
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
        [.banner, .sound]
    }

    /// The tap-through. Puts the nudge in the inbox; the UI opens on it.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let nudge = NudgePayload(userInfo: userInfo) else { return }
        await MainActor.run { PushService.shared.pending = nudge }
    }
}

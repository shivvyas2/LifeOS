import SwiftUI
import SwiftData
import OSLog
import Persistence
import Integrations
import AppSurfaces
import UserNotifications

private let accountLog = Logger(subsystem: "com.shivvyas.lifeos", category: "accounts")

/// Which account is open, and the store that belongs to it.
///
/// The app used to build one container in `init` and keep it for the process.
/// That is exactly what made two people on one device impossible: a container
/// is a file, and a file is one account's data. Switching accounts means
/// closing one and opening another, so this owns both and the scene rebuilds
/// around it.
@MainActor
@Observable
final class AccountSession {
    private(set) var scope: UserScope?
    private(set) var container: ModelContainer?

    private let accounts = AccountStore()
    private var hasAdoptedScope = false
    var beforeAccountChange: (() -> Void)?

    init() {
        adoptExistingSessionIfNeeded()
        if let current = accounts.currentScope, accounts.session(for: current.id)?.userID != current.id {
            accounts.remove(current.id)
        }
        adopt(accounts.currentScope)
    }

    /// Brings a device that was already signed in before accounts existed into
    /// the roster.
    ///
    /// Without this, upgrading would look like being signed out: the session
    /// sits in the old single keychain slot, the roster is empty, and the app
    /// has no account to open a store for. The same launch adopts the
    /// pre-account store, so the person keeps both their session and
    /// everything they had written.
    private func adoptExistingSessionIfNeeded() {
        guard accounts.accounts.isEmpty else { return }
        guard let session = accounts.legacySession() else { return }

        let account = Account(
            userID: session.userID,
            label: session.email ?? session.phone ?? "Account"
        )
        do {
            try accounts.add(account, session: session)
            // The move is only finished once the source is gone. Left in
            // place, the legacy slot outlives every sign out — nothing else
            // knows to clear a session with no user id on it — and the next
            // launch adopts it again and signs the person back in. That is
            // what made logging out impossible, and the app died on the way:
            // the restored session put the tab hierarchy on screen in a scene
            // that has no store open, and the first note fetch threw.
            accounts.clearLegacySession()
            if try LifeOSContainer.adoptLegacyStore(into: account.scope) {
                accountLog.info("adopted the pre-account store for the existing session")
            }
        } catch {
            accountLog.error("could not adopt the existing session: \(String(describing: error), privacy: .public)")
        }
    }

    var signedInAccounts: [Account] { accounts.accounts }
    var currentAccount: Account? { accounts.currentAccount }

    /// Records a newly signed-in account and opens its store.
    func signIn(_ account: Account, session: AuthSession) {
        do {
            try accounts.add(account, session: session)
            accounts.clearLegacySession()
        } catch {
            accountLog.error("sign-in bookkeeping failed: \(String(describing: error), privacy: .public)")
            return
        }
        if scope != account.scope || container == nil { adopt(account.scope) }
    }

    /// Switches to an account already signed in on this device.
    @discardableResult
    func `switch`(to userID: String) -> Bool {
        guard accounts.setCurrent(userID) else { return false }
        PlaidLinkPresenter.resetForAccountChange()
        adopt(accounts.currentScope)
        return true
    }

    /// Signs the current account out, leaving the others and their stores
    /// alone. Returns to onboarding so the next person starts signed out.
    func signOut() {
        PushService.shared.pending = nil
        UIApplication.shared.unregisterForRemoteNotifications()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        if let scope {
            // Saved provider links stay with their owner. In-flight browser
            // credentials and device calendar/Health opt-ins do not survive logout.
            KeychainWhoopTokenStore(account: scope.id).clearPending()
            KeychainFitbitAuthStore(account: scope.id).clearPending()
            let defaults = UserDefaults(suiteName: scope.defaultsSuiteName)!
            defaults.removeObject(forKey: AccountDeviceAccess.calendarKey)
            defaults.removeObject(forKey: "healthAuthorisationRequested")
            PlaidLinkPresenter.resetForAccountChange()
            accounts.remove(scope.id)
        }
        // Belt and braces for a device that adopted the legacy session under
        // the build that left it behind: `remove` clears it too, but only when
        // there was a scope to remove, and a shell with none must not be able
        // to resurrect one either.
        accounts.clearLegacySession()
        adopt(nil)
    }

    /// Defaults scoped to the open account, for the cursors and connection
    /// tokens that are per account rather than per device.
    var defaults: UserDefaults {
        scope.flatMap { UserDefaults(suiteName: $0.defaultsSuiteName) } ?? .currentAccount
    }

    private func adopt(_ next: UserScope?) {
        let signedOutRoute = scope == nil ? SurfaceCoordinator.shared.pendingRoute : nil
        if hasAdoptedScope && scope != next {
            SurfaceCoordinator.shared.clear()
            WorkoutLiveActivityController.endAll()
            WatchSessionBridge.shared.end(after: .discard)
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            beforeAccountChange?()
            beforeAccountChange = nil
        }
        if let signedOutRoute { SurfaceCoordinator.shared.pendingRoute = signedOutRoute }
        hasAdoptedScope = true
        scope = next
        PushService.shared.attach(ownerID: next?.id)
        guard let next else {
            container = nil
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            SurfaceCoordinator.shared.adopt(ownerID: nil, context: nil)
            WorkoutLiveActivityController.endAll()
            WatchSessionBridge.shared.end(after: .discard)
            return
        }
        do {
            container = try LifeOSContainer.make(for: next)
            SurfaceCoordinator.shared.adopt(ownerID: next.id, context: container?.mainContext)
        } catch {
            // A store that cannot open is not something the person can fix,
            // and carrying on with the previous account's container would show
            // them somebody else's data. Nothing open is the safe failure.
            accountLog.error("could not open the store for an account: \(String(describing: error), privacy: .public)")
            container = nil
            SurfaceCoordinator.shared.clear()
        }
    }
}

extension EnvironmentValues {
    /// Injected once by the scene. Settings is four views below the root and
    /// threading the session through every one of them would put an argument
    /// about accounts into screens that have nothing to do with accounts.
    @Entry var accountSession: AccountSession?
}

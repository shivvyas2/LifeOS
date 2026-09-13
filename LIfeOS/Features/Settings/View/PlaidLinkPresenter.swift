import UIKit
import LinkKit
import Integrations
import Persistence

/// What came back from the bank login.
enum PlaidLinkResult {
    case connected(publicToken: String, institutionID: String?, institutionName: String?)
    /// The user backed out. Not an error and not worth an alert.
    case cancelled
    case failed(String)
}

/// Presents Plaid's Link flow.
///
/// The only file in the app that imports LinkKit. Keeping the SDK behind this
/// one seam means the connection view model is testable against `PlaidAPI`
/// alone, and swapping presentation later touches nothing else.
@MainActor
enum PlaidLinkPresenter {
    /// The live Link session.
    ///
    /// Held here rather than left to whatever the presented view controller
    /// happens to retain, because a bank using OAuth sends the user out to
    /// Safari. A handler released while they are away has nothing to hand the
    /// redirect back to, and the connection dies silently at the last step.
    private static var handler: (any Handler)?

    /// The token the live session was built with.
    ///
    /// In `UserDefaults` rather than memory because the whole point of keeping
    /// it is the case where the process did not survive: `resumeAfterTermination`
    /// needs the same token the terminated session used.
    private static let tokenKey = "plaid.link.pendingToken"
    private static var generation = UUID()
    private static var ownerDefaults: UserDefaults?

    static func resetForAccountChange() {
        generation = UUID()
        clear()
        onResumedConnect = nil
        UserDefaults.standard.removeObject(forKey: tokenKey)
    }

    /// Where the result of a resumed session goes.
    ///
    /// `connect`'s completion closure died with the process, so
    /// `PlaidConnectionViewModel` re-registers this when it attaches.
    static var onResumedConnect: ((PlaidLinkResult) -> Void)?

    static func present(linkToken: String, completion: @escaping (PlaidLinkResult) -> Void) {
        guard KeychainAuthSessionStore().load() != nil else {
            completion(.failed("Sign in before connecting a bank"))
            return
        }
        generation = UUID()
        ownerDefaults = .currentAccount
        ownerDefaults?.set(linkToken, forKey: tokenKey)

        switch create(linkToken: linkToken, completion: completion) {
        case .failure(let error):
            clear()
            completion(.failed(error.localizedDescription))
        case .success(let handler):
            guard let controller = topViewController() else {
                clear()
                completion(.failed("No window to present from"))
                return
            }
            self.handler = handler
            handler.open(presentUsing: .viewController(controller))
        }
    }

    /// Takes the redirect at the end of a bank's OAuth login.
    ///
    /// Returns false for any URL that is not that redirect, so the caller can
    /// go on offering it to the other integrations.
    @discardableResult
    static func resume(from url: URL) -> Bool {
        guard AppConfig.isPlaidRedirect(url) else { return false }

        // The ordinary path: iOS only suspended the app while the user was at
        // their bank, the handler is still here, and LinkKit takes the redirect
        // itself. Presenting anything here would put Link on screen twice.
        guard handler == nil else { return true }

        // iOS terminated the app instead. A fresh handler on the original token
        // is the only way back into a flow the user has already completed.
        ownerDefaults = .currentAccount
        guard KeychainAuthSessionStore().load() != nil,
              let token = ownerDefaults?.string(forKey: tokenKey),
              let sink = onResumedConnect else {
            clear()
            return true
        }

        guard case .success(let handler) = create(linkToken: token, completion: sink) else {
            clear()
            sink(.failed("Could not pick the bank connection back up"))
            return true
        }

        self.handler = handler
        handler.resumeAfterTermination(from: url)
        return true
    }

    private static func create(
        linkToken: String,
        completion: @escaping (PlaidLinkResult) -> Void
    ) -> Result<any Handler, Plaid.CreateError> {
        let attempt = generation
        let owner = UserDefaults.standard.string(forKey: "accounts.current")
        var configuration = LinkTokenConfiguration(token: linkToken) { success in
            guard generation == attempt, owner != nil,
                  owner == UserDefaults.standard.string(forKey: "accounts.current") else { return }
            clear()
            completion(.connected(
                publicToken: success.publicToken,
                institutionID: success.metadata.institution.id,
                institutionName: success.metadata.institution.name
            ))
        }
        configuration.onExit = { exit in
            guard generation == attempt, owner != nil,
                  owner == UserDefaults.standard.string(forKey: "accounts.current") else { return }
            clear()
            // A user closing the sheet is the common path here, so an exit with
            // no error must not be dressed up as a failure.
            if let error = exit.error {
                completion(.failed(error.localizedDescription))
            } else {
                completion(.cancelled)
            }
        }
        return Plaid.create(configuration)
    }

    /// Drops the session. Called on every terminal outcome, because a token
    /// left behind would be replayed into the next OAuth redirect that arrives.
    private static func clear() {
        handler = nil
        ownerDefaults?.removeObject(forKey: tokenKey)
        ownerDefaults = nil
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var controller = scene?.keyWindow?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}

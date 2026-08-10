import Foundation
import SwiftData
import UIKit
import OSLog
import Integrations
import Persistence

/// Whoop failures used to collapse into the string "Sync failed", which made
/// the one thing that could not be verified without a live token — the wire
/// format — undiagnosable. Errors are now logged in full and surfaced.
private let whoopLog = Logger(subsystem: "shivvyas.LIfeOS", category: "whoop")

/// Owns the Whoop connection: the OAuth round trip, token storage, and sync.
@MainActor @Observable
final class WhoopConnectionViewModel {
    enum State: Equatable {
        case unconfigured           // no client id or no function endpoint yet
        case disconnected
        case connecting
        case connected(lastSyncedDays: Int?)
        case failed(String)
    }

    private(set) var state: State = .disconnected

    private let tokens: any WhoopTokenStoring
    private var context: ModelContext?

    init(tokens: any WhoopTokenStoring = KeychainWhoopTokenStore()) {
        self.tokens = tokens
    }

    func attach(_ context: ModelContext) {
        self.context = context
        refreshState()
    }

    func refreshState() {
        guard AppConfig.isWhoopConfigured else { state = .unconfigured; return }
        if tokens.load() != nil, case .connected = state {} else {
            state = tokens.load() != nil ? .connected(lastSyncedDays: nil) : .disconnected
        }
    }

    var statusDetail: String {
        switch state {
        case .unconfigured: "Not configured"
        case .disconnected: "Not connected"
        case .connecting:   "Connecting…"
        case .connected(let days): days.map { "Synced \($0) days" } ?? "Connected"
        case .failed(let message): message
        }
    }

    // MARK: - OAuth

    /// Opens sign-in in Safari rather than an in-app web session.
    ///
    /// Whoop's login sits behind a Cloudflare bot challenge that will not clear
    /// inside `ASWebAuthenticationSession` — it hangs on a blank page, on
    /// device as well as in the simulator. The same URL completes immediately
    /// in Safari, so the app hands off and is returned to by the lifeos://
    /// redirect. The cost is leaving the app briefly; the benefit is a flow
    /// that works at all.
    func connect() {
        guard let clientID = AppConfig.whoopClientID,
              let redirect = AppConfig.whoopRedirectURI else {
            state = .unconfigured
            return
        }

        let session = WhoopOAuth.session(clientID: clientID, redirectURI: redirect)
        do {
            // Persisted, not held in memory: Safari backgrounds the app and iOS
            // may terminate it before the redirect returns.
            try tokens.savePending(WhoopPendingAuth(verifier: session.verifier, state: session.state))
        } catch {
            whoopLog.error("could not persist pending auth: \(String(describing: error), privacy: .public)")
            state = .failed("Couldn't start sign-in")
            return
        }

        state = .connecting
        whoopLog.info("opening Whoop authorization in Safari")
        UIApplication.shared.open(session.url)
    }

    /// Entry point for the lifeos:// redirect.
    func handleCallback(_ url: URL) {
        guard url.scheme == AppConfig.appURLScheme else { return }
        Task { await finish(callbackURL: url) }
    }

    private func finish(callbackURL: URL) async {
        guard let pending = tokens.loadPending(),
              let endpoint = AppConfig.whoopTokenEndpoint,
              let redirect = AppConfig.whoopRedirectURI else {
            state = .failed("Missing configuration")
            return
        }
        // A redirect arriving long after the attempt was abandoned is not ours
        // to trust.
        guard pending.isFresh() else {
            tokens.clearPending()
            state = .failed("Sign-in timed out — try again")
            return
        }

        do {
            // Rejects a redirect whose state does not match ours.
            let code = try WhoopOAuth.code(from: callbackURL, expectedState: pending.state)
            let exchange = WhoopTokenExchange(endpoint: endpoint)
            let newTokens = try await exchange.exchange(
                code: code, verifier: pending.verifier, redirectURI: redirect
            )
            try tokens.save(newTokens)
            tokens.clearPending()
            state = .connected(lastSyncedDays: nil)
            await sync()
        } catch WhoopAuthError.denied {
            tokens.clearPending()
            state = .disconnected
        } catch {
            whoopLog.error("token exchange failed: \(String(describing: error), privacy: .public)")
            state = .failed("Sign-in failed: \(error.localizedDescription)")
        }
    }

    static func describe(_ error: WhoopAPIError) -> String {
        switch error {
        case .transport:            "Network error"
        case .unauthorized:         "Whoop rejected the token"
        case .rateLimited:          "Rate limited by Whoop"
        case .status(let code):     "Whoop returned \(code)"
        case .decoding(let detail): "Unexpected data format — \(detail.prefix(120))"
        }
    }

    func disconnect() {
        tokens.clear()
        tokens.clearPending()
        state = .disconnected
    }

    // MARK: - Sync

    func sync() async {
        guard let context, let endpoint = AppConfig.whoopTokenEndpoint else { return }
        guard tokens.load() != nil else { state = .disconnected; return }

        let sync = WhoopSync(
            exchange: WhoopTokenExchange(endpoint: endpoint),
            tokens: tokens,
            ingestion: WhoopIngestion(store: MetricsStore(context: context))
        )

        do {
            let days = try await sync.sync()
            state = .connected(lastSyncedDays: days)
        } catch WhoopSyncError.reauthenticationRequired {
            whoopLog.error("sync: token rejected, reauthentication required")
            state = .failed("Whoop sign-in expired")
        } catch let error as WhoopAPIError {
            // Surfaced rather than flattened: decoding vs transport vs status
            // are three different problems with three different fixes.
            whoopLog.error("sync failed: \(String(describing: error), privacy: .public)")
            state = .failed(Self.describe(error))
        } catch {
            whoopLog.error("sync failed: \(String(describing: error), privacy: .public)")
            state = .failed("Sync failed: \(error.localizedDescription)")
        }
    }
}

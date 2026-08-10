import Foundation
import SwiftData
import AuthenticationServices
import OSLog
import Integrations
import Persistence

/// Whoop failures used to collapse into the string "Sync failed", which made
/// the one thing that could not be verified without a live token — the wire
/// format — undiagnosable. Errors are now logged in full and surfaced.
private let whoopLog = Logger(subsystem: "shivvyas.LIfeOS", category: "whoop")

/// Owns the Whoop connection: the OAuth round trip, token storage, and sync.
@MainActor @Observable
final class WhoopConnectionViewModel: NSObject {
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
    private var pendingSession: WhoopOAuth.Session?
    private var webSession: ASWebAuthenticationSession?

    init(tokens: any WhoopTokenStoring = KeychainWhoopTokenStore()) {
        self.tokens = tokens
        super.init()
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

    func connect() {
        // The callback scheme is the app's own, not the redirect's: the redirect
        // is an https bridge and only its final hop returns to lifeos://.
        guard let clientID = AppConfig.whoopClientID,
              let redirect = AppConfig.whoopRedirectURI,
              let callbackScheme = AppConfig.appURLScheme else {
            state = .unconfigured
            return
        }

        let session = WhoopOAuth.session(clientID: clientID, redirectURI: redirect)
        pendingSession = session
        state = .connecting

        let web = ASWebAuthenticationSession(
            url: session.url,
            callbackURLScheme: callbackScheme
        ) { [weak self] callbackURL, error in
            guard let self else { return }
            Task { @MainActor in
                if let error {
                    // A user-initiated cancel is not a failure worth shouting about.
                    let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                    self.state = cancelled ? .disconnected : .failed("Sign-in failed")
                    return
                }
                guard let callbackURL else { self.state = .disconnected; return }
                await self.finish(callbackURL: callbackURL)
            }
        }
        web.presentationContextProvider = self
        web.prefersEphemeralWebBrowserSession = false
        webSession = web
        web.start()
    }

    private func finish(callbackURL: URL) async {
        guard let pending = pendingSession,
              let endpoint = AppConfig.whoopTokenEndpoint,
              let redirect = AppConfig.whoopRedirectURI else {
            state = .failed("Missing configuration")
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
            pendingSession = nil
            state = .connected(lastSyncedDays: nil)
            await sync()
        } catch WhoopAuthError.denied {
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

extension WhoopConnectionViewModel: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            return scene?.keyWindow ?? ASPresentationAnchor()
        }
    }
}

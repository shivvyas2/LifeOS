import Foundation
import SwiftData
import UIKit
import OSLog
import Integrations
import Persistence

/// Whoop failures used to collapse into the string "Sync failed", which made
/// the wire format, the one thing that could not be verified without a live
/// token, undiagnosable. Errors are now logged in full and surfaced.
private let whoopLog = Logger(subsystem: "com.shivvyas.lifeos", category: "whoop")

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

    /// Set when the user chooses to sign in on another device; the URL is
    /// shown for transfer to a desktop browser.
    private(set) var manualURL: URL?
    var manualCode = ""

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

    /// Connected in the sense the settings summary means: a live link, not a
    /// half-finished sign-in. `.connecting` is deliberately false, so the dot
    /// does not claim success while Safari is still open.
    var isConnected: Bool {
        if case .connected = state { return true }
        return false
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
    /// inside `ASWebAuthenticationSession`. It hangs on a blank page, on
    /// device as well as in the simulator. The same URL completes immediately
    /// in Safari, so the app hands off and is returned to by the
    /// custom-scheme redirect. The cost is leaving the app briefly; the benefit is a flow
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

    /// Sign-in on a desktop browser, for when Safari on this device cannot
    /// complete Whoop's login. A Cloudflare challenge behind a VPN, Private
    /// Relay or a content blocker will hang indefinitely with no error.
    func beginManual() {
        guard let clientID = AppConfig.whoopClientID,
              let redirect = AppConfig.whoopRedirectURI else {
            state = .unconfigured
            return
        }
        let session = WhoopOAuth.session(clientID: clientID, redirectURI: redirect, manual: true)
        do {
            try tokens.savePending(WhoopPendingAuth(verifier: session.verifier, state: session.state))
            manualURL = session.url
            manualCode = ""
            state = .connecting
        } catch {
            whoopLog.error("could not persist pending auth: \(String(describing: error), privacy: .public)")
            state = .failed("Couldn't start sign-in")
        }
    }

    /// Abandons a sign-in the user is done waiting on.
    ///
    /// Whoop's page is behind a Cloudflare check that stalls indefinitely
    /// behind a VPN, Private Relay or a content blocker, with no error and no
    /// callback. Without this the only way out of the spinner is to force-quit
    /// the app, because leaving for Safari is not something the app is told
    /// about either way.
    func cancelConnect() {
        guard case .connecting = state else { return }
        tokens.clearPending()
        manualURL = nil
        manualCode = ""
        state = .disconnected
    }

    func cancelManual() {
        manualURL = nil
        manualCode = ""
        tokens.clearPending()
        state = tokens.load() != nil ? .connected(lastSyncedDays: nil) : .disconnected
    }

    /// Exchanges a code transcribed from the other device. The PKCE verifier
    /// never left this phone, so a code alone is not enough to impersonate it.
    func submitManualCode() async {
        let code = manualCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty,
              // The manual flow has exactly one attempt in flight: the newest.
              let pending = tokens.pendingAuths().first,
              let endpoint = AppConfig.whoopTokenEndpoint,
              let redirect = AppConfig.whoopRedirectURI else { return }

        do {
            let newTokens = try await WhoopTokenExchange(endpoint: endpoint)
                .exchange(code: code, verifier: pending.verifier, redirectURI: redirect)
            try tokens.save(newTokens)
            lastCompletedSync = nil
            tokens.clearPending()
            manualURL = nil
            manualCode = ""
            state = .connected(lastSyncedDays: nil)
            await sync()
        } catch let error as WhoopAPIError {
            whoopLog.error("manual exchange failed: \(String(describing: error), privacy: .public)")
            // Named rather than flattened: a 400 from Whoop (expired or reused
            // code) and a 500 from the function (missing secret) need opposite
            // fixes, and "didn't work" cannot tell them apart.
            state = .failed(Self.describeExchange(error))
        } catch {
            whoopLog.error("manual exchange failed: \(String(describing: error), privacy: .public)")
            state = .failed("Couldn't connect: \(error.localizedDescription)")
        }
    }

    /// Entry point for the custom-scheme redirect, on whichever scheme the
    /// bridge is currently sending.
    func handleCallback(_ url: URL) {
        // Logged on arrival so "the redirect never came back" is distinguishable
        // from "it came back and the exchange failed". Without this the two look
        // identical: silence either way.
        whoopLog.info("callback received: \(url.host ?? "?", privacy: .public)")
        guard AppConfig.handles(url.scheme) else {
            whoopLog.error("callback ignored, unexpected scheme: \(url.scheme ?? "nil", privacy: .public)")
            return
        }
        Task { await finish(callbackURL: url) }
    }

    private func finish(callbackURL: URL) async {
        guard let endpoint = AppConfig.whoopTokenEndpoint,
              let redirect = AppConfig.whoopRedirectURI else {
            state = .failed("Missing configuration")
            return
        }

        // Match the redirect to the attempt that started it. Tapping Connect
        // more than once starts several valid authorizations, and the one that
        // returns is not necessarily the newest.
        let attempts = tokens.pendingAuths()
        guard let returned = WhoopOAuth.state(in: callbackURL),
              let pending = attempts.first(where: { $0.state == returned }) else {
            whoopLog.error("no pending attempt matches the returned state (\(attempts.count, privacy: .public) in flight)")
            state = .failed(attempts.isEmpty
                            ? "Sign-in expired. Tap Connect again"
                            : "Couldn't match that sign-in. Tap Connect again")
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
            lastCompletedSync = nil
            tokens.clearPending()
            whoopLog.info("whoop connected, starting first sync")
            state = .connected(lastSyncedDays: nil)
            await sync()
        } catch WhoopAuthError.denied {
            tokens.clearPending()
            state = .disconnected
        } catch let error as WhoopAPIError {
            whoopLog.error("token exchange failed: \(String(describing: error), privacy: .public)")
            state = .failed(Self.describeExchange(error))
        } catch {
            whoopLog.error("token exchange failed: \(String(describing: error), privacy: .public)")
            state = .failed("Sign-in failed: \(error.localizedDescription)")
        }
    }

    /// Whoop authorization codes are single-use and expire in about a minute,
    /// which is easy to exceed when transcribing from another device.
    static func describeExchange(_ error: WhoopAPIError) -> String {
        switch error {
        case .status(400): "Code expired or already used. Get a fresh one"
        case .status(401), .unauthorized: "Whoop rejected the credentials"
        case .status(500): "Server not configured"
        case .status(let code): "Exchange failed (\(code))"
        case .transport: "No connection"
        case .rateLimited: "Rate limited by Whoop"
        case .decoding(let detail): "Unexpected response: \(detail.prefix(80))"
        }
    }

    static func describe(_ error: WhoopAPIError) -> String {
        switch error {
        case .transport:            "Network error"
        case .unauthorized:         "Whoop rejected the token"
        case .rateLimited:          "Rate limited by Whoop"
        case .status(let code):     "Whoop returned \(code)"
        case .decoding(let detail): "Unexpected data format: \(detail.prefix(120))"
        }
    }

    func disconnect() {
        tokens.clear()
        tokens.clearPending()
        lastCompletedSync = nil
        state = .disconnected
    }

    // MARK: - Sync

    /// Recorded on every completed sync so `syncIfStale` can decide cheaply.
    /// UserDefaults rather than Keychain: this is a convenience timestamp, not
    /// a credential, and losing it costs one extra sync.
    private var lastCompletedSync: Date? {
        get { UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastSyncKey) }
    }
    private static let lastSyncKey = "whoopLastCompletedSyncAt"

    /// Set before the first await and cleared when the sync ends, so the
    /// launch task and the foreground transition, which fire together on a
    /// cold start, coalesce into one sync instead of racing Whoop's rate
    /// limit with duplicate requests.
    private var isSyncing = false

    /// Clears a sign-in that was started and then abandoned.
    ///
    /// Connecting hands off to Safari, and Whoop only calls back when someone
    /// finishes. Walk away, swipe the browser shut, or fail a Cloudflare
    /// challenge, and nothing tells the app: the card is left on `.connecting`
    /// and spins for the rest of the install, which is the "always loading"
    /// this fixes. It cannot be resolved at the point of departure, because
    /// leaving for Safari looks identical whether or not the user comes back.
    ///
    /// The wait is the whole subtlety. The redirect usually lands a moment
    /// AFTER the app becomes active, so resolving immediately would cancel
    /// sign-ins that were about to succeed. Two seconds is long enough for the
    /// callback to win the race, and short enough that a real abandonment does
    /// not read as a hang.
    func resolveStalledConnect() async {
        guard case .connecting = state else { return }
        // The manual desktop flow is still on screen with a code to paste, so
        // it is not abandoned: it is waiting on the user, deliberately.
        guard manualURL == nil else { return }

        try? await Task.sleep(for: .seconds(2))

        guard case .connecting = state, manualURL == nil, tokens.load() == nil else { return }
        whoopLog.info("sign-in was left unfinished; returning the card to disconnected")
        tokens.clearPending()
        state = .disconnected
    }

    /// Automatic sync, on launch and on every return to the foreground.
    /// Silent by design: the screens already show correct, if stale, local
    /// data, so a transient failure changes nothing the user needs to know
    /// about. Only a dead credential surfaces, because only that one needs
    /// the user to act. The guards never mutate state, so an OAuth attempt
    /// in flight (`.connecting`) is left untouched.
    func syncIfStale() async {
        guard context != nil, AppConfig.whoopTokenEndpoint != nil else { return }
        guard tokens.load() != nil, !isSyncing else { return }
        guard SyncStalenessPolicy.shouldSync(lastSync: lastCompletedSync) else { return }

        isSyncing = true
        defer { isSyncing = false }
        do {
            state = .connected(lastSyncedDays: try await performSync())
        } catch WhoopSyncError.reauthenticationRequired {
            whoopLog.error("auto-sync: refresh token rejected, reauthentication required")
            state = .failed("Whoop sign-in expired")
        } catch WhoopSyncError.accessDenied {
            whoopLog.error("auto-sync: whoop refused a live token, scopes are probably stale")
            state = .failed("Whoop needs new permissions. Disconnect, then connect again")
        } catch {
            whoopLog.info("auto-sync deferred: \(String(describing: error), privacy: .public)")
        }
    }

    /// Manual sync: "Sync now" and the first sync after connecting. Every
    /// failure is surfaced, because the user asked and deserves an answer.
    func sync() async {
        guard context != nil, AppConfig.whoopTokenEndpoint != nil else { return }
        guard tokens.load() != nil else { state = .disconnected; return }
        guard !isSyncing else { return }

        isSyncing = true
        defer { isSyncing = false }
        do {
            state = .connected(lastSyncedDays: try await performSync())
        } catch WhoopSyncError.reauthenticationRequired {
            whoopLog.error("sync: refresh token rejected, reauthentication required")
            state = .failed("Whoop sign-in expired")
        } catch WhoopSyncError.accessDenied {
            // Distinct from an expired sign-in, and the distinction matters:
            // the token is fine, it simply lacks a scope. Saying "expired" sent
            // the user around the reconnect loop with no idea why it kept
            // failing. Disconnecting first is what forces Whoop to re-ask for
            // the full scope list.
            whoopLog.error("sync: whoop refused a live token, scopes are probably stale")
            state = .failed("Whoop needs new permissions. Disconnect, then connect again")
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

    private func performSync() async throws -> Int {
        guard let context, let endpoint = AppConfig.whoopTokenEndpoint else {
            throw WhoopSyncError.notConnected
        }

        let sync = WhoopSync(
            exchange: WhoopTokenExchange(endpoint: endpoint),
            tokens: tokens,
            derivation: WhoopDerivation(
                store: MetricsStore(context: context),
                archive: WhoopArchive(context: context)
            ),
            archive: WhoopArchive(context: context)
        )

        let days = try await sync.sync()
        lastCompletedSync = .now
        return days
    }
}

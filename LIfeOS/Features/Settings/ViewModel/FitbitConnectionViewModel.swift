import Foundation
import AuthenticationServices
import UIKit
import OSLog
import Integrations
import Persistence
import SwiftData

private let fitbitLog = Logger(subsystem: "com.shivvyas.lifeos", category: "fitbit")

/// Owns the Fitbit connection: the OAuth round trip, and nothing else.
///
/// Deliberately thinner than `WhoopConnectionViewModel`, and the missing half
/// is the point. There are no tokens here to load, refresh or clear, because
/// Fitbit rotates its refresh token on every use: exactly one writer may hold
/// it, and that writer is a row in the database. This type hands a code to the
/// server and asks it what the state is.
@MainActor @Observable
final class FitbitConnectionViewModel: NSObject {
    enum State: Equatable {
        case unconfigured           // no client id or no function endpoint yet
        case disconnected
        case connecting
        case connected(lastSyncedDays: Int?)
        /// The refresh token was refused. Nothing the server holds can be used
        /// again, so only the user signing in again fixes it.
        case needsReauth
        case failed(String)
    }

    private(set) var state: State = .disconnected

    private let pending: any FitbitAuthStoring
    private let sessions: any AuthSessionStoring
    private var webSession: ASWebAuthenticationSession?

    /// Remembers the last known connection state per account, so the card does
    /// not flash "Not connected" on every launch while the server is asked.
    /// The server remains the authority; this is only what to show meanwhile.
    private let defaults: UserDefaults
    private let connectedKey = "fitbit.connected"
    private var context: ModelContext?
    private var active = true
    private(set) var isSyncing = false
    private var lastAttemptAt: Date?

    func attach(_ context: ModelContext) { self.context = context }

    func deactivate() {
        active = false
        webSession?.cancel()
        webSession = nil
        pending.clearPending()
        context = nil
    }

    init(
        pending: any FitbitAuthStoring = KeychainFitbitAuthStore(),
        sessions: any AuthSessionStoring = KeychainAuthSessionStore(),
        defaults: UserDefaults = .currentAccount
    ) {
        self.pending = pending
        self.sessions = sessions
        self.defaults = defaults
        super.init()
        refreshState()
    }

    func refreshState() {
        guard AppConfig.isFitbitConfigured else { state = .unconfigured; return }
        if case .connecting = state { return }
        state = defaults.bool(forKey: connectedKey)
            ? .connected(lastSyncedDays: nil)
            : .disconnected
    }

    /// Connected in the sense the settings summary means: a live link, not a
    /// half-finished sign-in. `.connecting` is deliberately false, so the dot
    /// does not claim success while the web session is still open.
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
        case .needsReauth:  "Sign in again to reconnect"
        case .failed(let message): message
        }
    }

    // MARK: - OAuth

    /// Signs in inside the app rather than handing off to Safari.
    ///
    /// Whoop hands off because its login sits behind a Cloudflare bot challenge
    /// that will not clear inside `ASWebAuthenticationSession`. Fitbit has no
    /// such challenge, and it permits a custom scheme redirect, so the whole
    /// round trip stays in the app and there is no bridge function in the
    /// middle. If Fitbit ever adds one, the fallback is `UIApplication.open`,
    /// exactly as `WhoopConnectionViewModel.connect()` does it.
    func connect() {
        guard active, sessions.load() != nil else { return }
        guard let clientID = AppConfig.fitbitClientID,
              let redirect = AppConfig.fitbitRedirectURI,
              let scheme = AppConfig.appURLScheme else {
            state = .unconfigured
            return
        }

        let session = FitbitOAuth.session(clientID: clientID, redirectURI: redirect)
        do {
            // Persisted, not held in memory: the web session backgrounds the
            // app and iOS may terminate it before the redirect returns.
            try pending.savePending(FitbitPendingAuth(verifier: session.verifier, state: session.state))
        } catch {
            fitbitLog.error("could not persist the pending auth: \(error)")
            state = .failed("Could not start sign-in")
            return
        }

        state = .connecting

        let web = ASWebAuthenticationSession(
            url: session.url, callbackURLScheme: scheme
        ) { [weak self] callback, error in
            guard let self else { return }
            Task { @MainActor in
                if let callback {
                    await self.handle(callback)
                } else {
                    // A cancelled sign-in is not a failure to report. The user
                    // closed the sheet, and the card should read as it did
                    // before they opened it.
                    if let error, (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                        fitbitLog.error("fitbit sign-in failed: \(error)")
                        self.state = .failed("Sign-in did not complete")
                    } else {
                        self.state = .disconnected
                        self.refreshState()
                    }
                }
            }
        }
        web.presentationContextProvider = self
        web.prefersEphemeralWebBrowserSession = false
        webSession = web
        web.start()
    }

    /// Matches the redirect to the attempt that issued it, then exchanges.
    func handle(_ url: URL) async {
        guard active, sessions.load() != nil else { return }
        guard let state = FitbitOAuth.state(in: url) else {
            self.state = .failed("Sign-in did not complete")
            return
        }
        guard let attempt = pending.pendingAuths().first(where: { $0.state == state }) else {
            // A redirect we did not issue, or one that arrived long after the
            // attempt expired. Either way there is no verifier to exchange with.
            fitbitLog.error("no pending fitbit auth matches the returned state")
            self.state = .failed("Sign-in expired, please try again")
            return
        }

        do {
            let code = try FitbitOAuth.code(from: url, expectedState: attempt.state)
            try await exchange(code: code, verifier: attempt.verifier)
            guard active, sessions.load() != nil else { return }
            pending.clearPending()
            defaults.set(true, forKey: connectedKey)
            self.state = .connected(lastSyncedDays: nil)
            await syncIfDue(force: true)
        } catch FitbitAuthError.denied {
            // The user said no. That is an answer, not an error.
            self.state = .disconnected
        } catch {
            fitbitLog.error("fitbit exchange failed: \(error)")
            self.state = .failed("Could not finish connecting")
        }
    }

    private func exchange(code: String, verifier: String) async throws {
        guard let endpoint = AppConfig.fitbitTokenEndpoint,
              let token = sessions.load()?.accessToken else {
            throw FitbitConnectionError.notConfigured
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "code": code,
            "verifier": verifier,
            "redirect_uri": AppConfig.fitbitRedirectURI ?? "",
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            fitbitLog.error("fitbit token function refused: \(body.prefix(200))")
            throw FitbitConnectionError.exchangeFailed
        }
    }

    func syncIfDue(force: Bool = false) async {
        guard active, !isSyncing, let context,
              let endpoint = AppConfig.fitbitSyncEndpoint,
              let token = sessions.load()?.accessToken,
              force || SyncStalenessPolicy.shouldSync(lastSync: lastAttemptAt) else { return }
        if case .connecting = state { return }
        isSyncing = true
        lastAttemptAt = .now
        defer { isSyncing = false }
        let sync = FitbitSync(endpoint: endpoint,
            derivation: FitbitDerivation(store: MetricsStore(context: context)),
            archive: WhoopArchive(context: context))
        do {
            let days = try await sync.sync(token: token)
            guard active else { return }
            defaults.set(true, forKey: connectedKey)
            state = .connected(lastSyncedDays: days)
        } catch FitbitSyncError.notConnected {
            defaults.set(false, forKey: connectedKey)
            refreshState()
        } catch FitbitSyncError.reauthenticationRequired {
            state = .needsReauth
        } catch FitbitSyncError.partial {
            defaults.set(true, forKey: connectedKey)
            state = .connected(lastSyncedDays: nil)
        } catch {
            // Preserve the last known link during an outage or refresh lock.
            refreshState()
        }
    }

    func disconnect() {
        guard active, let endpoint = AppConfig.fitbitSyncEndpoint,
              let token = sessions.load()?.accessToken else { return }
        webSession?.cancel()
        Task {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw FitbitConnectionError.exchangeFailed
                }
                guard active else { return }
                defaults.set(false, forKey: connectedKey)
                pending.clearPending()
                state = .disconnected
            } catch {
                state = .failed("Could not disconnect. Try again.")
            }
        }
    }

}

enum FitbitConnectionError: Error {
    case notConfigured
    case exchangeFailed
}

extension FitbitConnectionViewModel: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}

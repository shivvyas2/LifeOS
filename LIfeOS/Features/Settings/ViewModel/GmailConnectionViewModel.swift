import Foundation
import AuthenticationServices
import SwiftUI
import UIKit
import OSLog
import Integrations
import Persistence

nonisolated private let gmailLog = Logger(subsystem: "com.shivvyas.lifeos", category: "gmail")

/// What Today's Inbox module draws.
enum InboxState: Equatable {
    case notConnected
    case loading
    case reconnect
    case unavailable
    case ready(MailDigest, fetchedAt: Date)
}

/// Connects Gmail for Today's Inbox and reads the important mail.
///
/// Google's iOS client has no secret, so the whole exchange runs on the
/// phone: the token, the mail and the sorting never reach the server.
@MainActor @Observable
final class GmailConnectionViewModel: NSObject {
    enum State: Equatable {
        case unconfigured
        case disconnected
        case connecting
        case connected(email: String)
        case failed(String)
    }

    private(set) var state: State = .disconnected
    /// Google refused the refresh token. The connection is kept, so
    /// Disconnect stays reachable, and the card reads Reconnect.
    private(set) var needsReconnect = false
    /// Bumped on connect and disconnect, so Today knows to ask again.
    private(set) var changeCount = 0

    private let tokens: any GoogleTokenStoring
    private let defaults: UserDefaults
    private let sorter: MailSorter
    private var webSession: ASWebAuthenticationSession?
    private var active = true
    private var lastDigest: (MailDigest, Date)?
    private var refreshing: Task<String?, Never>?

    nonisolated static let needsReconnectKey = "gmail.needsReconnect"
    static let freshFor: TimeInterval = 600

    init(tokens: any GoogleTokenStoring = KeychainGoogleTokenStore(),
         defaults: UserDefaults = .currentAccount,
         sorter: MailSorter = MailSorter()) {
        self.tokens = tokens
        self.defaults = defaults
        self.sorter = sorter
        super.init()
        refreshState()
    }

    func refreshState() {
        guard AppConfig.isGoogleConfigured else { state = .unconfigured; return }
        if case .connecting = state { return }
        state = tokens.load().map { .connected(email: $0.email) } ?? .disconnected
        needsReconnect = defaults.bool(forKey: Self.needsReconnectKey)
    }

    func deactivate() {
        active = false
        webSession?.cancel()
        webSession = nil
        tokens.clearPending()
        lastDigest = nil
    }

    var isConnected: Bool { if case .connected = state { true } else { false } }

    var statusDetail: String {
        switch state {
        case .unconfigured: "Not configured"
        case .disconnected: "Not connected"
        case .connecting: "Connecting…"
        case .connected(let email): needsReconnect ? "Gmail needs reconnecting" : "Connected as \(email)"
        case .failed(let message): message
        }
    }

    // MARK: Sign-in

    func connect() {
        guard active, let clientID = AppConfig.googleClientID else { state = .unconfigured; return }
        let session = GoogleOAuth.session(clientID: clientID)
        do {
            // Persisted: the web sheet can background the app long enough for
            // iOS to end it before Google redirects back.
            try tokens.savePending(GooglePendingAuth(verifier: session.verifier, state: session.state))
        } catch {
            gmailLog.error("could not persist the pending auth: \(error)")
            state = .failed("Could not start sign-in")
            return
        }
        state = .connecting
        let scheme = GoogleOAuth.reversed(clientID: clientID)
        let web = ASWebAuthenticationSession(url: session.url, callbackURLScheme: scheme) { [weak self] callback, error in
            guard let self else { return }
            Task { @MainActor in
                if let callback {
                    await self.handle(callback)
                } else if let error, (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                    gmailLog.error("gmail sign-in failed: \(error)")
                    self.state = .failed("Sign-in did not complete")
                } else {
                    self.state = .disconnected
                    self.refreshState()
                }
            }
        }
        web.presentationContextProvider = self
        web.prefersEphemeralWebBrowserSession = false
        webSession = web
        web.start()
    }

    func handle(_ url: URL) async {
        guard active, let clientID = AppConfig.googleClientID else { return }
        guard let attempt = tokens.pending() else {
            state = .failed("Sign-in expired, please try again")
            return
        }
        do {
            let code = try GoogleOAuth.code(from: url, expectedState: attempt.state)
            let body = GoogleOAuth.tokenRequestBody(code: code, verifier: attempt.verifier, clientID: clientID,
                                                    redirectURI: GoogleOAuth.redirectURI(clientID: clientID))
            let (data, status) = try await post(GoogleOAuth.tokenURL, body: body)
            guard (200..<300).contains(status),
                  let response = try? JSONDecoder().decode(GoogleTokenResponse.self, from: data),
                  let refresh = response.refreshToken else {
                gmailLog.error("google token exchange refused: \(status)")
                throw GmailConnectionError.exchangeFailed
            }
            let email = response.idToken.flatMap(GoogleOAuth.email(fromIDToken:)) ?? "Gmail"
            guard active else { return }
            // Another Google account's verdicts are not this one's.
            if tokens.load()?.email != email { MailVerdictCache(defaults: defaults).clear() }
            try tokens.save(GoogleConnection(accessToken: response.accessToken, refreshToken: refresh,
                                             expiresAt: .now.addingTimeInterval(TimeInterval(response.expiresIn)),
                                             email: email))
            tokens.clearPending()
            defaults.set(false, forKey: Self.needsReconnectKey)
            needsReconnect = false
            lastDigest = nil
            state = .connected(email: email)
            changeCount += 1
        } catch GoogleAuthError.denied {
            tokens.clearPending()
            state = .disconnected
        } catch {
            gmailLog.error("gmail connect failed: \(error)")
            state = .failed("Could not finish connecting")
        }
    }

    /// Forgets the grant here whatever happens to the revoke, so an offline
    /// Disconnect still disconnects this phone.
    func disconnect() {
        webSession?.cancel()
        if let connection = tokens.load() {
            var components = URLComponents(url: GoogleOAuth.revokeURL, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "token", value: connection.refreshToken)]
            if let url = components.url {
                Task.detached {
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                    if (try? await URLSession.shared.data(for: request)) == nil {
                        gmailLog.error("google revoke did not go through")
                    }
                }
            }
        }
        tokens.clear()
        MailVerdictCache(defaults: defaults).clear()
        defaults.removeObject(forKey: Self.needsReconnectKey)
        defaults.removeObject(forKey: TodayLayoutStore.inboxOfferKey)
        needsReconnect = false
        lastDigest = nil
        state = .disconnected
        changeCount += 1
    }

    // MARK: Tokens

    /// A usable access token, refreshed first when it is about to expire.
    /// Nil when Google refused the refresh (reconnect) or could not answer.
    func validToken() async -> String? {
        guard let connection = tokens.load() else { return nil }
        guard connection.needsRefresh() else { return connection.accessToken }
        if let refreshing { return await refreshing.value }
        let task = Task { await refresh(connection) }
        refreshing = task
        defer { refreshing = nil }
        return await task.value
    }

    private func refresh(_ connection: GoogleConnection) async -> String? {
        guard let clientID = AppConfig.googleClientID else { return nil }
        let body = GoogleOAuth.refreshRequestBody(refreshToken: connection.refreshToken, clientID: clientID)
        guard let (data, status) = try? await post(GoogleOAuth.tokenURL, body: body) else { return nil }
        if (200..<300).contains(status), let response = try? JSONDecoder().decode(GoogleTokenResponse.self, from: data) {
            var next = connection
            next.accessToken = response.accessToken
            next.expiresAt = .now.addingTimeInterval(TimeInterval(response.expiresIn))
            if let rotated = response.refreshToken { next.refreshToken = rotated }
            try? tokens.save(next)
            return next.accessToken
        }
        if GoogleOAuth.refreshOutcome(status: status, body: data) == .reconnect { markReconnect() }
        return nil
    }

    private func markReconnect() {
        defaults.set(true, forKey: Self.needsReconnectKey)
        needsReconnect = true
    }

    // MARK: The mail

    /// The digest Today shows: fetched when the last one is more than ten
    /// minutes old, or always when `force`.
    func inbox(force: Bool = false) async -> InboxState {
        guard isConnected else { return .notConnected }
        if needsReconnect { return .reconnect }
        if !force, let (digest, at) = lastDigest, Date.now.timeIntervalSince(at) < Self.freshFor {
            return .ready(digest, fetchedAt: at)
        }
        guard let token = await validToken() else { return needsReconnect ? .reconnect : .unavailable }
        do {
            let (list, status) = try await get(GmailAPI.listURL(), token: token)
            if status == 401 { markReconnect(); return .reconnect }
            guard status == 200 else { return lastDigest.map { .ready($0.0, fetchedAt: $0.1) } ?? .unavailable }
            let items = await messages(GmailAPI.messageIDs(from: list), token: token)
            let verdicts = await sorter.verdicts(for: items, cache: MailVerdictCache(defaults: defaults))
            let digest = MailDigest.make(items: items, verdicts: verdicts)
            let now = Date.now
            lastDigest = (digest, now)
            return .ready(digest, fetchedAt: now)
        } catch {
            gmailLog.error("gmail fetch failed: \(error)")
            return lastDigest.map { .ready($0.0, fetchedAt: $0.1) } ?? .unavailable
        }
    }

    /// Each message's metadata, six at a time.
    private func messages(_ ids: [String], token: String) async -> [MailItem] {
        var items: [MailItem] = []
        for chunk in stride(from: 0, to: ids.count, by: 6).map({ Array(ids[$0..<min($0 + 6, ids.count)]) }) {
            await withTaskGroup(of: MailItem?.self) { group in
                for id in chunk {
                    group.addTask {
                        guard let (data, status) = try? await Self.fetch(GmailAPI.messageURL(id: id), token: token),
                              status == 200 else { return nil }
                        return GmailAPI.item(from: data)
                    }
                }
                for await item in group { if let item { items.append(item) } }
            }
        }
        return items
    }

    private func get(_ url: URL, token: String) async throws -> (Data, Int) {
        try await Self.fetch(url, token: token)
    }

    nonisolated private static func fetch(_ url: URL, token: String) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func post(_ url: URL, body: Data) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

enum GmailConnectionError: Error { case exchangeFailed }

extension GmailConnectionViewModel: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}

extension EnvironmentValues {
    /// Owned by `IntegrationContainer`; nil where no connection is offered.
    @Entry var gmail: GmailConnectionViewModel? = nil
}

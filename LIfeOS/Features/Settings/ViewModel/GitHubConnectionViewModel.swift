import Foundation
import AuthenticationServices
import SwiftUI
import UIKit
import OSLog
import Integrations
import Persistence

nonisolated private let githubLog = Logger(subsystem: "com.shivvyas.lifeos", category: "github")

/// Connects GitHub for the day's project card.
///
/// The sign-in runs in `ASWebAuthenticationSession` like Fitbit's. The
/// `github-token` function swaps the code for a token with the secret the app
/// cannot hold and keeps nothing; the token lives only in this phone's
/// Keychain, under the open account.
@MainActor @Observable
final class GitHubConnectionViewModel: NSObject {
    enum State: Equatable {
        case unconfigured
        case disconnected
        case connecting
        case connected(login: String)
        case failed(String)
    }

    private(set) var state: State = .disconnected
    private(set) var repos: [GitHubRepoRef] = []

    private let tokens: any GitHubTokenStoring
    private let sessions: any AuthSessionStoring
    private let defaults: UserDefaults
    private let transport: any GitHubTransport
    private var webSession: ASWebAuthenticationSession?
    private var active = true

    nonisolated static let pinKey = "github.pinnedRepo"
    nonisolated static let pinMissingKey = "github.pinnedRepoMissing"

    init(tokens: any GitHubTokenStoring = KeychainGitHubTokenStore(),
         sessions: any AuthSessionStoring = KeychainAuthSessionStore(),
         defaults: UserDefaults = .currentAccount,
         transport: any GitHubTransport = URLSessionGitHubTransport()) {
        self.tokens = tokens
        self.sessions = sessions
        self.defaults = defaults
        self.transport = transport
        super.init()
        refreshState()
    }

    func refreshState() {
        guard AppConfig.isGitHubConfigured else { state = .unconfigured; return }
        if case .connecting = state { return }
        state = tokens.load().map { .connected(login: $0.login) } ?? .disconnected
    }

    func deactivate() {
        active = false
        webSession?.cancel()
        webSession = nil
        tokens.clearPending()
    }

    var statusDetail: String {
        switch state {
        case .unconfigured: "Not configured"
        case .disconnected: "Not connected"
        case .connecting: "Connecting…"
        case .connected(let login): "Connected as @\(login)"
        case .failed(let message): message
        }
    }

    // MARK: The pin

    var pinnedRepo: String? {
        get { access(keyPath: \.pinnedRepo); return defaults.string(forKey: Self.pinKey) }
        set {
            withMutation(keyPath: \.pinnedRepo) {
                if let newValue { defaults.set(newValue, forKey: Self.pinKey) }
                else { defaults.removeObject(forKey: Self.pinKey) }
                defaults.removeObject(forKey: Self.pinMissingKey)
                GitHubDayCache(defaults: defaults).clear()
            }
        }
    }

    var pinMissing: Bool {
        access(keyPath: \.pinMissing)
        return defaults.bool(forKey: Self.pinMissingKey)
    }

    // MARK: The day screen's source

    /// Nil unless connected, which is what hides the section.
    var dayProvider: (any GitHubDayProviding)? {
        guard case .connected = state, let connection = tokens.load() else { return nil }
        return GitHubDayProvider(connection: connection, pinnedRepo: pinnedRepo, defaults: defaults,
                                 transport: transport)
    }

    // MARK: Sign-in

    func connect() {
        guard active, sessions.load() != nil else { return }
        guard let clientID = AppConfig.githubClientID else { state = .unconfigured; return }
        let session = GitHubOAuth.session(clientID: clientID)
        do {
            // Persisted: the web sheet can background the app long enough for
            // iOS to end it before GitHub redirects back.
            try tokens.savePending(GitHubPendingAuth(verifier: session.verifier, state: session.state))
        } catch {
            githubLog.error("could not persist the pending auth: \(error)")
            state = .failed("Could not start sign-in")
            return
        }
        state = .connecting
        let web = ASWebAuthenticationSession(url: session.url, callbackURLScheme: "almanac") { [weak self] callback, error in
            guard let self else { return }
            Task { @MainActor in
                if let callback {
                    await self.handle(callback)
                } else if let error, (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                    githubLog.error("github sign-in failed: \(error)")
                    self.state = .failed("Sign-in did not complete")
                } else {
                    // Closing the sheet is not a failure to report.
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
        guard active, sessions.load() != nil else { return }
        guard let attempt = tokens.pending() else {
            state = .failed("Sign-in expired, please try again")
            return
        }
        do {
            let code = try GitHubOAuth.code(from: url, expectedState: attempt.state)
            let token = try await exchange(code: code, verifier: attempt.verifier)
            let user: GitHubUser = try await get(GitHubAPI.url("/user"), token: token)
            guard active else { return }
            try tokens.save(GitHubConnection(token: token, login: user.login))
            tokens.clearPending()
            state = .connected(login: user.login)
        } catch GitHubAuthError.denied {
            tokens.clearPending()
            state = .disconnected
        } catch {
            githubLog.error("github connect failed: \(error)")
            state = .failed("Could not finish connecting")
        }
    }

    private func exchange(code: String, verifier: String) async throws -> String {
        guard let endpoint = AppConfig.githubTokenEndpoint, let session = sessions.load()?.accessToken else {
            throw GitHubConnectionError.notConfigured
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "code": code, "verifier": verifier, "redirect_uri": GitHubOAuth.redirectURI,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = body["access_token"] as? String else {
            githubLog.error("github token function refused: \(String(data: data, encoding: .utf8)?.prefix(200) ?? "")")
            throw GitHubConnectionError.exchangeFailed
        }
        return token
    }

    /// Forgets the token here whatever happens to the revoke, so an offline
    /// Disconnect still disconnects this phone.
    func disconnect() {
        guard let connection = tokens.load() else { state = .disconnected; return }
        webSession?.cancel()
        if let endpoint = AppConfig.githubTokenEndpoint, let session = sessions.load()?.accessToken {
            Task.detached {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "DELETE"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
                request.httpBody = try? JSONSerialization.data(withJSONObject: ["access_token": connection.token])
                if (try? await URLSession.shared.data(for: request)) == nil {
                    githubLog.error("github revoke did not reach the function")
                }
            }
        }
        tokens.clear()
        GitHubDayCache(defaults: defaults).clear()
        pinnedRepo = nil
        repos = []
        state = .disconnected
    }

    // MARK: Repos for the pin

    func loadRepos() async {
        guard let connection = tokens.load() else { return }
        do {
            repos = try await get(GitHubAPI.url("/user/repos", query: [
                ("sort", "pushed"), ("per_page", "50"), ("affiliation", "owner,collaborator,organization_member"),
            ]), token: connection.token)
        } catch GitHubConnectionError.unauthorized {
            state = .failed("GitHub needs reconnecting")
        } catch {
            githubLog.error("github repos failed: \(error)")
        }
    }

    private func get<Value: Decodable>(_ url: URL, token: String) async throws -> Value {
        let (data, status) = try await transport.get(url, token: token)
        guard status != 401 else { throw GitHubConnectionError.unauthorized }
        guard (200..<300).contains(status) else { throw GitHubConnectionError.exchangeFailed }
        return try GitHubWire.decoder.decode(Value.self, from: data)
    }
}

enum GitHubConnectionError: Error {
    case notConfigured, exchangeFailed, unauthorized
}

extension GitHubConnectionViewModel: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}

/// The day screen's GitHub source: the cache first, then the loader; a failed
/// refresh falls back to the cached card with its time.
///
/// `@unchecked Sendable` for `UserDefaults`, which Apple documents as
/// thread-safe.
struct GitHubDayProvider: GitHubDayProviding, @unchecked Sendable {
    let connection: GitHubConnection
    let pinnedRepo: String?
    let defaults: UserDefaults
    var transport: any GitHubTransport = URLSessionGitHubTransport()

    func project(for day: Date, isToday: Bool, force: Bool) async -> ProjectCardState? {
        let calendar = Calendar.current
        let cache = GitHubDayCache(defaults: defaults)
        let cached = cache.entry(for: day, calendar: calendar)
        if !force, let cached, cache.isFresh(cached, for: day, now: .now, calendar: calendar) {
            return cached.card.map { .card($0, asOf: nil) }
        }
        let loader = GitHubDayLoader(transport: transport, connection: connection, pinnedRepo: pinnedRepo, calendar: calendar)
        do {
            let result = try await loader.load(day: day, isToday: isToday)
            // Read by the Settings row, which says the pin was not found.
            defaults.set(result.pinMissing, forKey: GitHubConnectionViewModel.pinMissingKey)
            if case .reconnect = result.state { return .reconnect }
            if case .card(let card, _)? = result.state { cache.store(card, for: day, calendar: calendar) }
            else { cache.store(nil, for: day, calendar: calendar) }
            return result.state
        } catch {
            return cached?.card.map { .card($0, asOf: cached?.fetchedAt) }
        }
    }
}

extension EnvironmentValues {
    /// Owned by `IntegrationContainer`; nil where no connection is offered.
    @Entry var github: GitHubConnectionViewModel? = nil
}

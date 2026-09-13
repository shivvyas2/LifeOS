import Foundation
import SwiftData
import Persistence

/// Exchanges codes and refreshes tokens by calling the Edge Function.
/// The client secret lives there; this type only ever handles tokens.
public struct WhoopTokenExchange: Sendable {
    private let endpoint: URL
    private let session: URLSession
    private let sessions: any AuthSessionStoring

    public init(endpoint: URL, session: URLSession = .shared, sessions: any AuthSessionStoring = KeychainAuthSessionStore()) {
        self.endpoint = endpoint
        self.session = session
        self.sessions = sessions
    }

    public func exchange(code: String, verifier: String, redirectURI: String) async throws -> WhoopTokens {
        try await post(["code": code, "verifier": verifier, "redirect_uri": redirectURI])
    }

    public func refresh(refreshToken: String) async throws -> WhoopTokens {
        try await post(["refresh_token": refreshToken])
    }

    public func restore() async throws -> WhoopTokens {
        try await post(["action": "restore"])
    }

    public func disconnect() async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "DELETE"
        if let token = sessions.load()?.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WhoopAPIError.transport
        }
    }

    private func post(_ body: [String: String]) async throws -> WhoopTokens {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = sessions.load()?.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            // The function reports its own 502 for any upstream failure and puts
            // Whoop's real status in the body. Without unwrapping that, every
            // cause looks identical and an expired code is indistinguishable
            // from a missing server secret.
            let upstream = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0?["status"] as? Int }
            if upstream == nil, (response as? HTTPURLResponse)?.statusCode == 401 {
                throw WhoopTokenExchangeError.notSignedIn
            }
            throw WhoopAPIError.status(upstream ?? (response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double?
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return WhoopTokens(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token,
            expiresAt: .now.addingTimeInterval(decoded.expires_in ?? 3_600)
        )
    }
}

/// Pulls recent Whoop data and writes it into the daily spine.
@MainActor
public struct WhoopSync {
    private let client: WhoopClient
    private let exchange: WhoopTokenExchange
    private let tokens: WhoopTokenStoring
    private let derivation: WhoopDerivation
    private let archive: WhoopArchive

    public init(
        client: WhoopClient = .init(),
        exchange: WhoopTokenExchange,
        tokens: WhoopTokenStoring,
        derivation: WhoopDerivation,
        archive: WhoopArchive
    ) {
        self.client = client
        self.exchange = exchange
        self.tokens = tokens
        self.derivation = derivation
        self.archive = archive
    }

    public var isConnected: Bool { tokens.load() != nil }

    public func disconnect() { tokens.clear() }

    /// Runs a sync over the trailing `days`. Returns the number of days written.
    @discardableResult
    public func sync(days: Int = 14, now: Date = .now) async throws -> Int {
        guard var current = tokens.load() else { throw WhoopSyncError.notConnected }

        // Refresh proactively rather than waiting for a 401: one round trip
        // instead of a failed request followed by a retry.
        if current.isExpired(now: now), let refresh = current.refreshToken {
            do {
                current = try await exchange.refresh(refreshToken: refresh)
                try tokens.save(current)
            } catch let error as WhoopAPIError where error.isUnauthorized {
                // This is the one rejection that ends the connection: the
                // refresh token itself was refused, so nothing the app holds
                // can be used again. Clearing puts the UI back into a "Connect"
                // state rather than leaving it stuck claiming connection.
                tokens.clear()
                throw WhoopSyncError.reauthenticationRequired
            }
        }

        let since = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now

        do {
            let recovery = try await client.recoveriesRaw(accessToken: current.accessToken, since: since, until: now)
            let sleep = try await client.sleepsRaw(accessToken: current.accessToken, since: since, until: now)
            let cycle = try await client.cyclesRaw(accessToken: current.accessToken, since: since, until: now)
            let workout = try await client.workoutsRaw(accessToken: current.accessToken, since: since, until: now)
            let body = try await client.bodyMeasurement(accessToken: current.accessToken)

            // Archive first: a re-derive reads from the archive, and a payload that was
            // never stored cannot be re-derived from.
            for (kind, pages) in [("recovery", recovery.rawPages), ("sleep", sleep.rawPages),
                                  ("cycle", cycle.rawPages), ("workout", workout.rawPages)] {
                let split = try pages.flatMap { try WhoopRawSplit.records(inPage: $0) }
                try archive.store(split.map { (kind: kind, externalID: $0.externalID, payload: $0.payload) })
            }
            // There is exactly one body measurement per user, so a stable external
            // id is correct and every sync upserts the current reading in place.
            try archive.store(kind: "body", externalID: "self", payload: body.rawPayload)

            try derivation.derive(recoveries: recovery.samples, sleeps: sleep.samples,
                                  cycles: cycle.samples, workouts: workout.samples,
                                  body: (sample: body.sample, date: now))
            return Set(recovery.samples.map(\.date) + cycle.samples.map(\.date)).count
        } catch WhoopAPIError.unauthorized {
            // A live token the API refuses is a permission problem, not a dead
            // credential: most often the authorization predates a scope the app
            // has since started needing. This used to clear the tokens, which
            // deleted a credential the user had granted seconds earlier and
            // made the connect-then-sync loop unbreakable, because reconnecting
            // produced the same rejection every time. The connection is left
            // intact deliberately.
            throw WhoopSyncError.accessDenied
        }
    }
}

extension WhoopAPIError {
    /// OAuth token endpoints use either 400 `invalid_grant` or 401 for a refused
    /// refresh credential. Collection endpoints report `.unauthorized`.
    var isUnauthorized: Bool {
        switch self {
        case .unauthorized, .status(400), .status(401): true
        default: false
        }
    }
}

public enum WhoopSyncError: Error, Equatable {
    case notConnected
    case reauthenticationRequired
    /// Whoop refused a live token for a collection. The credential is still
    /// good; it just lacks permission, so reconnecting to grant the newer
    /// scopes is the fix, not treating the connection as lost.
    case accessDenied
}

public enum WhoopTokenExchangeError: Error { case notSignedIn }

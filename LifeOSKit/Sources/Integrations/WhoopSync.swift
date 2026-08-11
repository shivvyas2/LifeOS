import Foundation
import SwiftData
import Persistence

/// Exchanges codes and refreshes tokens by calling the Edge Function.
/// The client secret lives there; this type only ever handles tokens.
public struct WhoopTokenExchange: Sendable {
    private let endpoint: URL
    private let session: URLSession

    public init(endpoint: URL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    public func exchange(code: String, verifier: String, redirectURI: String) async throws -> WhoopTokens {
        try await post(["code": code, "verifier": verifier, "redirect_uri": redirectURI])
    }

    public func refresh(refreshToken: String) async throws -> WhoopTokens {
        try await post(["refresh_token": refreshToken])
    }

    private func post(_ body: [String: String]) async throws -> WhoopTokens {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            // The function reports its own 502 for any upstream failure and puts
            // Whoop's real status in the body. Without unwrapping that, every
            // cause looks identical and an expired code is indistinguishable
            // from a missing server secret.
            let upstream = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0?["status"] as? Int }
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
    private let ingestion: WhoopIngestion

    public init(
        client: WhoopClient = .init(),
        exchange: WhoopTokenExchange,
        tokens: WhoopTokenStoring,
        ingestion: WhoopIngestion
    ) {
        self.client = client
        self.exchange = exchange
        self.tokens = tokens
        self.ingestion = ingestion
    }

    public var isConnected: Bool { tokens.load() != nil }

    public func disconnect() { tokens.clear() }

    /// Runs a sync over the trailing `days`. Returns the number of days written.
    @discardableResult
    public func sync(days: Int = 14, now: Date = .now) async throws -> Int {
        guard var current = tokens.load() else { throw WhoopSyncError.notConnected }

        // Refresh proactively rather than waiting for a 401 — one round trip
        // instead of a failed request followed by a retry.
        if current.isExpired(now: now), let refresh = current.refreshToken {
            current = try await exchange.refresh(refreshToken: refresh)
            try tokens.save(current)
        }

        let since = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now

        do {
            let recoveries = try await client.recoveries(accessToken: current.accessToken, since: since, until: now)
            let sleeps = try await client.sleeps(accessToken: current.accessToken, since: since, until: now)
            let cycles = try await client.cycles(accessToken: current.accessToken, since: since, until: now)

            try ingestion.ingest(recoveries: recoveries, sleeps: sleeps, cycles: cycles)
            return Set(recoveries.map(\.date) + cycles.map(\.date)).count
        } catch WhoopAPIError.unauthorized {
            // The stored token is dead. Clearing it puts the UI back into a
            // "Connect" state rather than leaving it stuck claiming connection.
            tokens.clear()
            throw WhoopSyncError.reauthenticationRequired
        }
    }
}

public enum WhoopSyncError: Error, Equatable {
    case notConnected
    case reauthenticationRequired
}

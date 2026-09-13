import Foundation
import SwiftData
import Persistence

/// Pulls Fitbit data through the Edge Function and writes it into the spine.
///
/// Thinner than `WhoopSync` by exactly one responsibility: there is no token
/// handling here at all. Fitbit rotates its refresh token on every use, so the
/// credential lives in a database row that is its only writer, and this type
/// never sees one.
@MainActor
public struct FitbitSync {
    private let endpoint: URL
    private let session: URLSession
    private let derivation: FitbitDerivation
    private let archive: WhoopArchive

    /// `archive` is `WhoopArchive` because it is already a generic raw-record
    /// store keyed by an arbitrary `kind`; only its name is Whoop-specific.
    /// Fitbit's records go in under `fitbit-` kinds. Renaming the type to
    /// `RawArchive` is a mechanical follow-up, kept out of this change so it
    /// does not drag Whoop code along with it.
    public init(
        endpoint: URL,
        session: URLSession = .shared,
        derivation: FitbitDerivation,
        archive: WhoopArchive
    ) {
        self.endpoint = endpoint
        self.session = session
        self.derivation = derivation
        self.archive = archive
    }

    /// Runs a sync over the trailing `days`. Returns the number of days written.
    @discardableResult
    public func sync(days: Int = 30, token: String) async throws -> Int {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["days": days])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FitbitSyncError.upstreamFailure
        }
        guard http.statusCode != 404 else { throw FitbitSyncError.notConnected }
        guard (200..<300).contains(http.statusCode) else { throw FitbitSyncError.upstreamFailure }

        let envelope = try JSONDecoder().decode(SyncResponse.self, from: data)

        if envelope.retry == true { throw FitbitSyncError.retryLater }

        // A dead credential is not a retry. Nothing the server holds can be
        // used again, so the app stops and asks the user to sign in rather
        // than spinning against a token nothing can revive.
        if envelope.needs_reauth { throw FitbitSyncError.reauthenticationRequired }

        // Archive first, for the reason `WhoopSync` gives: a re-derive reads
        // from the archive, and a payload that was never stored cannot be
        // re-derived from.
        try archiveRaw(data)

        let written = FitbitDerivation.days(from: envelope.payloads).count
        try derivation.derive(envelope.payloads)

        // After the write, not before. One declined scope must not discard the
        // six collections that arrived intact.
        if !envelope.failures.isEmpty {
            throw FitbitSyncError.partial(failed: envelope.failures.keys.sorted())
        }
        return written
    }

    /// Stores each collection's raw JSON under its own kind, keyed by the day
    /// window so a re-sync of the same window replaces rather than duplicates.
    private func archiveRaw(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payloads = root["payloads"] as? [String: Any]
        else { return }

        let records = try payloads.map { key, value in
            (kind: "fitbit-\(key)",
             externalID: key,
             payload: try JSONSerialization.data(withJSONObject: value))
        }
        try archive.store(records)
    }

    private struct SyncResponse: Decodable {
        let payloads: FitbitPayloads
        let failures: [String: String]
        let needs_reauth: Bool
        let retry: Bool?
    }
}

public enum FitbitSyncError: Error, Equatable {
    case notConnected
    case retryLater
    case reauthenticationRequired
    /// Some collections landed and some did not. The days that arrived are
    /// already written; this names what is missing.
    case partial(failed: [String])
    case upstreamFailure
}

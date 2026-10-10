import Foundation
import Integrations

public protocol FocusRemote: Sendable {
    func insertIgnoringDuplicates(table: String, body: Data, accessToken: String) async throws
    func focusRows(since: Date, accessToken: String) async throws -> Data
}

extension SupabaseREST: FocusRemote {
    /// This user's sessions that started at or after `since`, newest first.
    /// Row Level Security limits it to the caller; no user filter is needed.
    public func focusRows(since: Date, accessToken: String) async throws -> Data {
        try await select(table: "focus_sessions",
                         query: [URLQueryItem(name: "select", value: "*"),
                                 URLQueryItem(name: "started_at", value: "gte.\(SupabaseREST.timestamp(since))"),
                                 URLQueryItem(name: "order", value: "started_at.desc"),
                                 URLQueryItem(name: "limit", value: "500")],
                         accessToken: accessToken)
    }
}

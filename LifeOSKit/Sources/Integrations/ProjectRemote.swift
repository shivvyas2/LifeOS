import Foundation

/// What `ProjectSync` needs from the server, so it can be tested against a
/// stand-in. `SupabaseREST` is the real one.
public protocol ProjectRemote: Sendable {
    func upsert(table: String, body: Data, accessToken: String) async throws
    func insertIgnoringDuplicates(table: String, body: Data, accessToken: String) async throws
    func delete(table: String, column: String, equals value: String, accessToken: String) async throws
    func fetch(table: String, since: Date?, accessToken: String, limit: Int) async throws -> Data
    func fetch(table: String, column: String, equals value: String, accessToken: String, limit: Int) async throws -> Data
}

extension SupabaseREST: ProjectRemote {}

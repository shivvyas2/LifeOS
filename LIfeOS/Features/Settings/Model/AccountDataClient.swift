import Foundation
import Integrations
import Persistence

/// The account's controls on the server: clearing chosen data, scheduling and
/// cancelling deletion, and asking which signed-out accounts are now gone.
protocol AccountDataClienting: Sendable {
    func clear(_ categories: Set<DataCategory>) async throws
    func scheduleDeletion() async throws -> Date
    func keep() async throws
    func scheduledDeletion() async throws -> Date?
    func deleted(among ids: [String]) async throws -> [String]
}

enum AccountDataError: Error, Equatable {
    case notConfigured, signedOut, failed(Int)
}

struct AccountDataClient: AccountDataClienting {
    private var endpoint: URL? { AppConfig.supabaseURL?.appendingPathComponent("functions/v1/account-data") }

    func clear(_ categories: Set<DataCategory>) async throws {
        let names = DataCategory.allCases.filter { categories.contains($0) }.map(\.rawValue)
        _ = try await send("POST", body: ["clear": names])
    }

    func scheduleDeletion() async throws -> Date {
        try Self.date(from: try await send("DELETE")) ?? .now.addingTimeInterval(30 * 86_400)
    }

    func keep() async throws { _ = try await send("PATCH", body: ["keep": true]) }

    func scheduledDeletion() async throws -> Date? { try Self.date(from: try await send("GET")) }

    /// Anonymous: the answer is only which of these ids were deleted.
    func deleted(among ids: [String]) async throws -> [String] {
        guard let endpoint, let anon = AppConfig.supabaseAnonKey, !ids.isEmpty else { return [] }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "deleted", value: ids.prefix(20).joined(separator: ","))]
        var request = URLRequest(url: components.url!)
        request.setValue(anon, forHTTPHeaderField: "apikey")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw AccountDataError.failed(status) }
        return ((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["deleted"] as? [String]) ?? []
    }

    private func send(_ method: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        guard let endpoint else { throw AccountDataError.notConfigured }
        guard let token = KeychainAuthSessionStore().load()?.accessToken else { throw AccountDataError.signedOut }
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let anon = AppConfig.supabaseAnonKey { request.setValue(anon, forHTTPHeaderField: "apikey") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw AccountDataError.failed(status) }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func date(from payload: [String: Any]) -> Date? {
        guard let text = payload["deletion_scheduled_for"] as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

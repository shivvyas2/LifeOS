import Foundation

public struct PlaidExchangeResult: Decodable, Sendable {
    public let item_id: String
    public let institution_name: String

    // Explicit because a public struct's memberwise init is internal, and the
    // sync tests build one of these from the test module.
    public init(item_id: String, institution_name: String) {
        self.item_id = item_id
        self.institution_name = institution_name
    }
}

public enum PlaidClientError: Error, Equatable {
    /// No session, or the function refused the one we sent.
    case unauthorized
    /// The bank invalidated the stored login. Needs the user, not a retry.
    case itemLoginRequired
    case institutionAlreadyConnected
    case rateLimited
    case upstream(Int)
    case transport
}

/// The seam the sync runner and the connection view model talk to, so both are
/// testable without a network or a Plaid account.
public protocol PlaidAPI: Sendable {
    func createLinkToken() async throws -> String
    func exchange(publicToken: String, institutionID: String?,
                  institutionName: String?) async throws -> PlaidExchangeResult
    func sync(cursors: [String: String]) async throws -> PlaidSyncResponse
    func disconnect(itemID: String) async throws
}

/// Calls the four Edge Functions. Holds no Plaid credential of any kind: the
/// only token it carries is the user's own Supabase session.
public struct PlaidClient: PlaidAPI {
    private let functionsBase: URL
    private let session: URLSession
    private let accessToken: @Sendable () -> String?

    public init(functionsBase: URL, session: URLSession = .shared,
                accessToken: @escaping @Sendable () -> String?) {
        self.functionsBase = functionsBase
        self.session = session
        self.accessToken = accessToken
    }

    public func createLinkToken() async throws -> String {
        struct Response: Decodable { let link_token: String }
        let response: Response = try await post("plaid-link-token", body: [:])
        return response.link_token
    }

    public func exchange(publicToken: String, institutionID: String?,
                         institutionName: String?) async throws -> PlaidExchangeResult {
        // Built up rather than written as a literal with `as Any`: a nil in an
        // [String: Any] literal is an Optional, not NSNull, and
        // JSONSerialization throws on it.
        var body: [String: Any] = ["public_token": publicToken]
        if let institutionID { body["institution_id"] = institutionID }
        if let institutionName { body["institution_name"] = institutionName }
        return try await post("plaid-exchange", body: body)
    }

    public func sync(cursors: [String: String]) async throws -> PlaidSyncResponse {
        try await post("plaid-sync", body: ["cursors": cursors])
    }

    public func disconnect(itemID: String) async throws {
        struct Response: Decodable { let ok: Bool }
        let _: Response = try await post("plaid-disconnect", body: ["item_id": itemID])
    }

    private func post<T: Decodable>(_ function: String, body: [String: Any]) async throws -> T {
        // Signed out there is no user to scope a credential to, so this fails
        // before the request rather than sending one that cannot succeed.
        guard let token = accessToken(), !token.isEmpty else { throw PlaidClientError.unauthorized }

        var request = URLRequest(url: functionsBase.appendingPathComponent(function))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PlaidClientError.transport
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw Self.error(status: status, body: data)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PlaidClientError.upstream(status)
        }
    }

    /// The functions return their own status with a named kind in the body.
    /// Without unwrapping that name every cause looks identical, and an expired
    /// bank login is indistinguishable from an outage.
    private static func error(status: Int, body: Data) -> PlaidClientError {
        let kind = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])
            .flatMap { $0?["error"] as? String }

        switch kind {
        case "item_login_required": return .itemLoginRequired
        case "institution_already_connected": return .institutionAlreadyConnected
        case "rate_limited": return .rateLimited
        case "unauthorized": return .unauthorized
        default: return status == 401 ? .unauthorized : .upstream(status)
        }
    }
}

import Foundation

/// Supabase Auth over REST.
///
/// No SDK: the three calls needed here — request an OTP, verify it, refresh a
/// session — are small, and a dependency would pull in far more surface than
/// that for no benefit.
///
/// The anon key is sent as the API key. It is public by design; Row Level
/// Security is what protects rows, not the secrecy of this key.
public struct SupabaseAuth: Sendable {
    public enum Channel: String, Sendable, CaseIterable {
        case phone, email

        public var title: String { self == .phone ? "Phone" : "Email" }
    }

    private let baseURL: URL
    private let anonKey: String
    private let session: URLSession

    public init(baseURL: URL, anonKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.session = session
    }

    /// Sends a one-time code. `shouldCreateUser` is true because this is the
    /// signup path — Supabase treats OTP as sign-in-or-create.
    public func sendCode(to destination: String, channel: Channel) async throws {
        let body: [String: Any] = channel == .phone
            ? ["phone": destination, "create_user": true]
            : ["email": destination, "create_user": true]
        _ = try await post("otp", body: body)
    }

    /// Exchanges the code for a session.
    public func verify(code: String, destination: String, channel: Channel) async throws -> AuthSession {
        var body: [String: Any] = ["token": code, "type": channel == .phone ? "sms" : "email"]
        body[channel.rawValue] = destination

        let data = try await post("verify", body: body)
        return try decode(data)
    }

    public func refresh(refreshToken: String) async throws -> AuthSession {
        let data = try await post("token?grant_type=refresh_token",
                                  body: ["refresh_token": refreshToken])
        return try decode(data)
    }

    /// Stores the profile fields collected during onboarding on the user record.
    /// `user_metadata` avoids needing a profiles table before there is anything
    /// else to put in one.
    public func updateProfile(
        accessToken: String, firstName: String, lastName: String, country: String
    ) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/v1/user"))
        request.httpMethod = "PUT"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "data": ["first_name": firstName, "last_name": lastName, "country": country]
        ])

        let (data, response) = try await session.data(for: request)
        try check(response, data)
    }

    private func post(_ path: String, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/v1/\(path)"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try check(response, data)
        return data
    }

    private func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw AuthError.transport }
        guard (200..<300).contains(http.statusCode) else {
            // Supabase returns a readable reason; surfacing it verbatim is what
            // makes "SMS provider not configured" visible instead of a generic
            // failure the user cannot act on.
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0?["msg"] as? String ?? $0?["error_description"] as? String
                            ?? $0?["message"] as? String }
            throw AuthError.server(status: http.statusCode, message: message)
        }
    }

    private func decode(_ data: Data) throws -> AuthSession {
        struct Response: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double?
            let user: User?
            struct User: Decodable { let id: String; let phone: String?; let email: String? }
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return AuthSession(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token,
            expiresAt: .now.addingTimeInterval(decoded.expires_in ?? 3_600),
            userID: decoded.user?.id ?? "",
            phone: decoded.user?.phone,
            email: decoded.user?.email
        )
    }
}

public struct AuthSession: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date
    public let userID: String
    public let phone: String?
    public let email: String?

    public init(accessToken: String, refreshToken: String?, expiresAt: Date,
                userID: String, phone: String?, email: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userID = userID
        self.phone = phone
        self.email = email
    }

    public func isExpired(now: Date = .now) -> Bool {
        expiresAt.addingTimeInterval(-60) <= now
    }
}

public enum AuthError: Error, Equatable {
    case transport
    case server(status: Int, message: String?)

    /// Plain-language reason, so the UI never shows a bare status code.
    public var readable: String {
        switch self {
        case .transport:
            "No connection"
        case .server(let status, let message):
            if let message, !message.isEmpty { message }
            else if status == 429 { "Too many attempts — wait a moment" }
            else if status == 403 { "That code didn't match" }
            else { "Something went wrong (\(status))" }
        }
    }
}

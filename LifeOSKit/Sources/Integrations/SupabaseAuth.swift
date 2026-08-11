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

    /// Which channels the project can actually deliver on.
    ///
    /// Worth one call at startup: SMS requires a provider (Twilio and friends)
    /// that is off by default, and a phone-first signup screen that cannot send
    /// anything is a dead end the user cannot diagnose.
    public func availableChannels() async -> Set<Channel> {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/v1/settings"))
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let external = json["external"] as? [String: Any]
        else { return [.email] }   // email is the safe assumption

        var channels: Set<Channel> = []
        if external["email"] as? Bool == true { channels.insert(.email) }
        if external["phone"] as? Bool == true { channels.insert(.phone) }
        return channels.isEmpty ? [.email] : channels
    }

    /// Sends a one-time code. `shouldCreateUser` is true because this is the
    /// signup path — Supabase treats OTP as sign-in-or-create.
    public func sendCode(to destination: String, channel: Channel) async throws {
        let body: [String: Any] = channel == .phone
            ? ["phone": destination, "create_user": true]
            : ["email": destination, "create_user": true]
        _ = try await post("otp", body: body)
    }

    /// Sends a magic link that returns to `redirectTo`.
    ///
    /// Used for email because the free tier will not let the template be
    /// changed to include a six-digit token — the stock template only ever
    /// sends a link. Swap back to `sendCode` once custom SMTP is configured.
    public func sendMagicLink(to email: String, redirectTo: String) async throws {
        _ = try await post("otp", body: [
            "email": email,
            "create_user": true,
            "email_redirect_to": redirectTo,
        ])
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

public extension AuthSession {
    /// Builds a session from a magic-link redirect.
    ///
    /// Supabase returns the tokens in the URL *fragment* rather than the query,
    /// so `URLComponents.queryItems` finds nothing and the callback looks empty
    /// until the fragment is parsed by hand.
    init?(callback url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var pairs: [String: String] = [:]

        for source in [components?.fragment, components?.query].compactMap({ $0 }) {
            for part in source.split(separator: "&") {
                let bits = part.split(separator: "=", maxSplits: 1)
                guard bits.count == 2 else { continue }
                pairs[String(bits[0])] = String(bits[1])
                    .replacingOccurrences(of: "+", with: " ")
                    .removingPercentEncoding ?? String(bits[1])
            }
        }

        guard let access = pairs["access_token"], !access.isEmpty else { return nil }
        let seconds = pairs["expires_in"].flatMap(Double.init) ?? 3_600
        self.init(
            accessToken: access,
            refreshToken: pairs["refresh_token"],
            expiresAt: .now.addingTimeInterval(seconds),
            userID: "",
            phone: nil,
            email: nil
        )
    }

    /// Supabase reports a failed link the same way — in the fragment.
    static func errorDescription(in url: URL) -> String? {
        guard let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment
        else { return nil }
        for part in fragment.split(separator: "&") {
            let bits = part.split(separator: "=", maxSplits: 1)
            if bits.count == 2, bits[0] == "error_description" {
                return String(bits[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding
            }
        }
        return nil
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

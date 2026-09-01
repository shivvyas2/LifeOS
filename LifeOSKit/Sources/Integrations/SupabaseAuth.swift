import Foundation

/// Supabase Auth over REST.
///
/// No SDK: the three calls needed here (request an OTP, verify it, refresh a
/// session) are small, and a dependency would pull in far more surface than
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
    /// Phone is always offered: SMS goes through the `otp-start` Edge Function
    /// (Twilio Verify), not GoTrue's own provider. Email still comes from
    /// `/auth/v1/settings`.
    public func availableChannels() async -> Set<Channel> {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/v1/settings"))
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let external = json["external"] as? [String: Any]
        else { return [.email, .phone] }

        var channels: Set<Channel> = [.phone]
        if external["email"] as? Bool == true { channels.insert(.email) }
        return channels
    }

    /// Sends a one-time code. Phone goes through Twilio Verify on the server.
    /// Email still uses GoTrue.
    public func sendCode(to destination: String, channel: Channel) async throws {
        if channel == .phone {
            _ = try await postFunction("otp-start", body: ["phone": destination])
            return
        }
        _ = try await post("otp", body: ["email": destination, "create_user": true])
    }

    /// Exchanges the code for a session.
    public func verify(code: String, destination: String, channel: Channel) async throws -> AuthSession {
        if channel == .phone {
            let data = try await postFunction("otp-check", body: ["phone": destination, "code": code])
            return try decode(data)
        }
        let data = try await post("verify", body: ["token": code, "type": "email", "email": destination])
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
        accessToken: String, firstName: String, lastName: String, country: String,
        birthDate: Date? = nil, heightCM: Double? = nil, gender: String? = nil
    ) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/v1/user"))
        request.httpMethod = "PUT"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var fields: [String: Any] = [
            "first_name": firstName, "last_name": lastName, "country": country,
        ]
        // Only what was actually given. Writing nulls for the optional fields
        // would overwrite answers from an earlier pass with blanks, and this
        // endpoint merges rather than replaces.
        if let birthDate {
            // ISO date only, no time: a birthday has no clock, and storing one
            // makes the value shift by a day across time zones.
            fields["birth_date"] = Self.birthDateFormatter.string(from: birthDate)
        }
        if let heightCM { fields["height_cm"] = Int(heightCM.rounded()) }
        if let gender, !gender.isEmpty { fields["gender"] = gender }

        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": fields])

        let (data, response) = try await session.data(for: request)
        try check(response, data)
    }

    /// Fixed to a POSIX calendar so the stored string does not change shape
    /// with the device's locale.
    private static let birthDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func postFunction(_ name: String, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent("functions/v1/\(name)"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try check(response, data)
        return data
    }

    /// An auth URL, with a query string that is still a query string.
    ///
    /// Deliberately not `appendingPathComponent` on the whole path.  That
    /// treats what it is given as a single component and percent-encodes the
    /// `?` into `%3F`, which sent the one call that carries a query to
    /// POST /auth/v1/token%3Fgrant_type=refresh_token.  GoTrue answers 404 to
    /// that, so a stored session could never be renewed: an hour after signing
    /// in the access token expired and every authenticated call began failing
    /// 401, the coach's turn among them.  The other callers pass a bare path
    /// and are unaffected, which is why signing in always looked fine.
    private func authURL(_ path: String) throws -> URL {
        let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var components = URLComponents(
            url: baseURL.appendingPathComponent("auth/v1/\(parts[0])"),
            resolvingAgainstBaseURL: false
        )
        if parts.count > 1 { components?.query = String(parts[1]) }
        guard let url = components?.url else { throw AuthError.transport }
        return url
    }

    private func post(_ path: String, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: try authURL(path))
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
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            throw AuthError.fromHTTP(status: http.statusCode, json: json)
        }
    }

    private func decode(_ data: Data) throws -> AuthSession {
        struct Response: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double?
            let user: User?
            struct User: Decodable {
                let id: String
                let phone: String?
                let email: String?
                let user_metadata: Metadata?
                struct Metadata: Decodable { let first_name: String? }
            }
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let firstName = decoded.user?.user_metadata?.first_name ?? ""
        return AuthSession(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token,
            expiresAt: .now.addingTimeInterval(decoded.expires_in ?? 3_600),
            userID: decoded.user?.id ?? "",
            phone: decoded.user?.phone,
            email: decoded.user?.email,
            hasProfile: !firstName.trimmingCharacters(in: .whitespaces).isEmpty
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
    /// Whether this account has already been through the profile step. With OTP
    /// there is no password, so this is the only thing that tells a returning
    /// user apart from a new one after the code is accepted.
    public let hasProfile: Bool

    public init(accessToken: String, refreshToken: String?, expiresAt: Date,
                userID: String, phone: String?, email: String?, hasProfile: Bool = false) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userID = userID
        self.phone = phone
        self.email = email
        self.hasProfile = hasProfile
    }

    /// Written by hand rather than synthesised: sessions already in the keychain
    /// have no `hasProfile` key, and a synthesised decoder would throw on them
    /// and sign every existing user out on upgrade. Defaulting to false is safe
    /// because the flag is only read immediately after `verify`; a restored
    /// session goes straight to the app on `hasFinishedOnboarding`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        userID = try container.decode(String.self, forKey: .userID)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        hasProfile = try container.decodeIfPresent(Bool.self, forKey: .hasProfile) ?? false
    }

    public func isExpired(now: Date = .now) -> Bool {
        expiresAt.addingTimeInterval(-60) <= now
    }
}

public enum AuthError: Error, Equatable {
    case transport
    case server(status: Int, message: String?)

    /// Maps a failed Auth or Edge Function body onto a sentence the UI can show.
    /// `{ "error": "send_failed" }` has no `message` field, so reading only
    /// GoTrue's keys left the UI with a bare 502.
    static func fromHTTP(status: Int, json: [String: Any]) -> AuthError {
        let code = json["error"] as? String
        switch code {
        case "rate_limited":
            return .server(status: 429, message: "Too many attempts. Wait a moment")
        case "invalid_phone":
            return .server(status: 400, message: "That number doesn't look right")
        case "server_not_configured":
            return .server(status: 500, message: "SMS isn't set up yet")
        case "send_failed":
            return .server(status: 502, message: "Couldn't send the text. Check the number and try again")
        case "sms_region":
            return .server(status: 502, message: "SMS isn't available for that country yet")
        // Twilio 21608. Cannot happen on a paid account, so the reader can do
        // nothing about it and the copy must not send them off to fix a number
        // that is not the problem.
        case "sms_trial_unverified", "sms_unverified":
            return .server(
                status: 502,
                message: "We can't text this number yet. The SMS account is still in trial mode"
            )
        // Twilio 21610. Per number, and the user is the only one who can undo it.
        case "sms_opted_out":
            return .server(
                status: 502,
                message: "That number opted out of our texts. Text START to our number to opt back in"
            )
        // Twilio 30034.
        case "sms_unregistered_campaign":
            return .server(
                status: 502,
                message: "Our SMS sender isn't registered with that carrier yet"
            )
        // Twilio 60410.
        case "sms_blocked":
            return .server(status: 502, message: "The carrier blocked that text")
        case "check_failed", "session_failed":
            return .server(status: status, message: "Couldn't finish sign-in. Try again")
        default:
            break
        }
        let message = json["msg"] as? String ?? json["error_description"] as? String
            ?? json["message"] as? String
        if let message, !message.isEmpty {
            return .server(status: status, message: message)
        }
        if status == 502 {
            // Channel-neutral: an empty- or HTML-bodied 502 with no msg/
            // error_description/message can come from the email path too
            // (email is now the default channel), so this cannot assume SMS.
            return .server(
                status: 502,
                message: "Couldn't send your code. Try again"
            )
        }
        return .server(status: status, message: nil)
    }

    /// Plain-language reason, so the UI never shows a bare status code.
    public var readable: String {
        switch self {
        case .transport:
            "No connection"
        case .server(let status, let message):
            if let message, !message.isEmpty { message }
            else if status == 429 { "Too many attempts. Wait a moment" }
            else if status == 403 { "That code didn't match" }
            else { "Something went wrong (\(status))" }
        }
    }
}

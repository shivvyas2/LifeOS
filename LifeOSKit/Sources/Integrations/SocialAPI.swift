import Foundation

/// A profile row as returned by search or by looking up a set of ids.
///
/// Everything past `displayName` is what the profile page shows about a
/// person: the same fields their own profile shows about them. All optional,
/// because every one of them is a question someone may decline to answer, and
/// a profile that pads itself with placeholders for the fields somebody
/// skipped looks broken rather than private.
///
/// Neither request sets `select`, so PostgREST returns the whole row and
/// these arrive without a second round trip.
public struct SocialProfile: Codable, Sendable, Equatable, Identifiable {
    public let userID: UUID
    public let displayName: String
    public let firstName: String?
    public let country: String?
    public let birthDate: Date?
    public let heightCM: Double?
    /// The object's path inside the avatars bucket, which is public-read, so
    /// a friend list can show faces without signing a URL per row.
    public let avatarPath: String?
    public var id: UUID { userID }

    public init(
        userID: UUID, displayName: String,
        firstName: String? = nil, country: String? = nil,
        birthDate: Date? = nil, heightCM: Double? = nil, avatarPath: String? = nil
    ) {
        self.userID = userID
        self.displayName = displayName
        self.firstName = firstName
        self.country = country
        self.birthDate = birthDate
        self.heightCM = heightCM
        self.avatarPath = avatarPath
    }

    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case firstName = "first_name"
        case country
        case birthDate = "birth_date"
        case heightCM = "height_cm"
        case avatarPath = "avatar_path"
    }
}

public enum FriendshipStatus: String, Codable, Sendable { case pending, accepted }

public struct Friendship: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let requester: UUID
    public let addressee: UUID
    public let status: FriendshipStatus

    public init(id: Int, requester: UUID, addressee: UUID, status: FriendshipStatus) {
        self.id = id
        self.requester = requester
        self.addressee = addressee
        self.status = status
    }
}

public struct SocialMessage: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let sender: UUID
    public let recipient: UUID
    public let body: String
    public let createdAt: Date

    public init(id: Int, sender: UUID, recipient: UUID, body: String, createdAt: Date) {
        self.id = id
        self.sender = sender
        self.recipient = recipient
        self.body = body
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, sender, recipient, body
        case createdAt = "created_at"
    }
}

public enum SocialAPIError: Error, Equatable {
    /// The status the server gave, and the sentence it gave with it.
    ///
    /// The message is carried because without it every refusal is the same
    /// refusal. An expired token, a missing grant and a malformed filter all
    /// arrive as "it did not work", and none of the three can be told apart
    /// from a screenshot of a failed search. PostgREST always says which it
    /// is; the only way to lose that is to drop it here.
    ///
    /// Empty when the body was not PostgREST's error shape, which is what a
    /// proxy's HTML error page looks like.
    case status(Int, message: String)
}

extension SocialAPIError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .status(let code, let message):
            message.isEmpty ? "HTTP \(code)" : "HTTP \(code): \(message)"
        }
    }
}

/// PostgREST over `URLSession`, for the three tables in the friends-and-messages
/// schema: `profiles`, `friendships`, `messages`.
///
/// Same reasoning as `SupabaseAuth` and `SupabaseREST`: this is a handful of
/// small, shaped calls, not a general database client, so there is no SDK
/// dependency here either. Row Level Security is what actually protects the
/// data; this type only shapes requests and decodes responses.
public struct SocialAPI: Sendable {
    private let baseURL: URL
    private let anonKey: String
    private let session: URLSession

    public init(baseURL: URL, anonKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.session = session
    }

    /// Creates or replaces the caller's own profile row.
    public func upsertMyProfile(accessToken: String, userID: UUID, displayName: String) async throws {
        let request = try Self.upsertProfileRequest(
            baseURL: baseURL, anonKey: anonKey, accessToken: accessToken,
            userID: userID, displayName: displayName
        )
        _ = try await perform(request)
    }

    /// Finds profiles whose display name contains `query`, case-insensitively.
    public func search(_ query: String, accessToken: String) async throws -> [SocialProfile] {
        let request = Self.searchRequest(baseURL: baseURL, anonKey: anonKey, accessToken: accessToken, query: query)
        let data = try await perform(request)
        return try Self.decoder.decode([SocialProfile].self, from: data)
    }

    /// All friendship rows RLS lets the caller see: both sides of every
    /// relationship they participate in, pending or accepted.
    public func friendships(accessToken: String) async throws -> [Friendship] {
        let request = Self.friendshipsRequest(baseURL: baseURL, anonKey: anonKey, accessToken: accessToken)
        let data = try await perform(request)
        return try Self.decoder.decode([Friendship].self, from: data)
    }

    /// Looks up display names for a batch of user ids, e.g. to label a friend
    /// list built from `friendships` rows.
    public func profiles(ids: [UUID], accessToken: String) async throws -> [SocialProfile] {
        guard !ids.isEmpty else { return [] }
        let request = Self.profilesRequest(baseURL: baseURL, anonKey: anonKey, accessToken: accessToken, ids: ids)
        let data = try await perform(request)
        return try Self.decoder.decode([SocialProfile].self, from: data)
    }

    /// Sends a friend request from `myUserID` to `userID`.
    ///
    /// The unique constraint on `friendships` only covers the ordered pair
    /// `(requester, addressee)`, so the same two people asking in opposite
    /// directions would otherwise create two rows. That dedupe is deliberately
    /// left to the API layer rather than the schema, so it happens here: fetch
    /// the caller's own friendships first, and if the pair is already linked in
    /// either direction, return without inserting. Idempotent, not an error —
    /// asking someone who already asked you is not a mistake worth surfacing.
    public func request(from myUserID: UUID, to userID: UUID, accessToken: String) async throws {
        let existing = try await friendships(accessToken: accessToken)
        let alreadyLinked = existing.contains { friendship in
            (friendship.requester == myUserID && friendship.addressee == userID)
                || (friendship.requester == userID && friendship.addressee == myUserID)
        }
        guard !alreadyLinked else { return }

        let request = try Self.createFriendshipRequest(
            baseURL: baseURL, anonKey: anonKey, accessToken: accessToken,
            requester: myUserID, addressee: userID
        )
        _ = try await perform(request)
    }

    /// Accepts a pending request. The database now grants `update` on
    /// `friendships` to `status` alone, so this must send exactly that column
    /// and nothing else, or the update is rejected before RLS even runs.
    public func accept(friendshipID: Int, accessToken: String) async throws {
        let request = try Self.acceptFriendshipRequest(
            baseURL: baseURL, anonKey: anonKey, accessToken: accessToken, friendshipID: friendshipID
        )
        _ = try await perform(request)
    }

    /// Ends a friendship, pending or accepted, from either side.
    public func remove(friendshipID: Int, accessToken: String) async throws {
        let request = Self.removeFriendshipRequest(
            baseURL: baseURL, anonKey: anonKey, accessToken: accessToken, friendshipID: friendshipID
        )
        _ = try await perform(request)
    }

    /// A conversation's messages, oldest first. RLS already restricts rows to
    /// the caller's own conversations, so filtering by the other party alone
    /// is enough to select this one thread.
    public func messages(with userID: UUID, accessToken: String) async throws -> [SocialMessage] {
        let request = Self.messagesRequest(baseURL: baseURL, anonKey: anonKey, accessToken: accessToken, userID: userID)
        let data = try await perform(request)
        return try Self.decoder.decode([SocialMessage].self, from: data).reversed()
    }

    /// Every message the caller can see, newest first.
    ///
    /// One request for the whole inbox rather than one per friend. The select
    /// policy on `messages` already restricts rows to conversations the caller
    /// is in, so this returns exactly their own mail and nothing else, and a
    /// person with thirty friends gets one round trip instead of thirty.
    ///
    /// The limit is on messages, not conversations, so a very busy thread can
    /// crowd a quiet one off the end. That is the right failure: the inbox is
    /// ordered by recency, and what falls off is what was least recent.
    public func recentMessages(accessToken: String, limit: Int = 200) async throws -> [SocialMessage] {
        let request = Self.recentMessagesRequest(
            baseURL: baseURL, anonKey: anonKey, accessToken: accessToken, limit: limit
        )
        let data = try await perform(request)
        return try Self.decoder.decode([SocialMessage].self, from: data)
    }

    /// Sends a message. The `sender` column is required and RLS insists it
    /// equal `auth.uid()`, so it has to be in the body; the only place that
    /// identity is available here is the access token itself, whose `sub`
    /// claim is the caller's user id.
    public func send(_ body: String, to userID: UUID, accessToken: String) async throws {
        guard let sender = Self.subject(ofAccessToken: accessToken) else {
            throw SocialAPIError.status(401, message: "The access token carries no subject claim")
        }
        let request = try Self.sendMessageRequest(
            baseURL: baseURL, anonKey: anonKey, accessToken: accessToken,
            sender: sender, recipient: userID, body: body
        )
        _ = try await perform(request)
    }

    // MARK: - Request builders

    /// Pure and free of `self` so tests can assert on the `URLRequest` a call
    /// would produce without a network or a stub `URLProtocol`.
    static func upsertProfileRequest(
        baseURL: URL, anonKey: String, accessToken: String, userID: UUID, displayName: String
    ) throws -> URLRequest {
        var request = authorized(baseURL: baseURL, anonKey: anonKey, accessToken: accessToken, path: "rest/v1/profiles")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "user_id": userID.uuidString,
            "display_name": displayName,
        ])
        return request
    }

    static func searchRequest(baseURL: URL, anonKey: String, accessToken: String, query: String) -> URLRequest {
        let escaped = escapeWildcards(query)
        var components = URLComponents(
            url: baseURL.appendingPathComponent("rest/v1/profiles"), resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "display_name", value: "ilike.*\(escaped)*"),
            URLQueryItem(name: "limit", value: "20"),
        ]
        var request = URLRequest(url: components?.url ?? baseURL)
        applyHeaders(&request, anonKey: anonKey, accessToken: accessToken)
        return request
    }

    static func friendshipsRequest(baseURL: URL, anonKey: String, accessToken: String) -> URLRequest {
        authorized(baseURL: baseURL, anonKey: anonKey, accessToken: accessToken, path: "rest/v1/friendships")
    }

    static func profilesRequest(baseURL: URL, anonKey: String, accessToken: String, ids: [UUID]) -> URLRequest {
        let list = ids.map(\.uuidString).joined(separator: ",")
        var components = URLComponents(
            url: baseURL.appendingPathComponent("rest/v1/profiles"), resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "user_id", value: "in.(\(list))")]
        var request = URLRequest(url: components?.url ?? baseURL)
        applyHeaders(&request, anonKey: anonKey, accessToken: accessToken)
        return request
    }

    static func createFriendshipRequest(
        baseURL: URL, anonKey: String, accessToken: String, requester: UUID, addressee: UUID
    ) throws -> URLRequest {
        var request = authorized(baseURL: baseURL, anonKey: anonKey, accessToken: accessToken, path: "rest/v1/friendships")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "requester": requester.uuidString,
            "addressee": addressee.uuidString,
            "status": FriendshipStatus.pending.rawValue,
        ])
        return request
    }

    static func acceptFriendshipRequest(
        baseURL: URL, anonKey: String, accessToken: String, friendshipID: Int
    ) throws -> URLRequest {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("rest/v1/friendships"), resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "id", value: "eq.\(friendshipID)")]
        var request = URLRequest(url: components?.url ?? baseURL)
        request.httpMethod = "PATCH"
        applyHeaders(&request, anonKey: anonKey, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Only this column: the database grants `update` on `friendships` to
        // `status` alone, so any other key here would make the whole request
        // fail rather than partially apply.
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "status": FriendshipStatus.accepted.rawValue,
        ])
        return request
    }

    static func removeFriendshipRequest(
        baseURL: URL, anonKey: String, accessToken: String, friendshipID: Int
    ) -> URLRequest {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("rest/v1/friendships"), resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "id", value: "eq.\(friendshipID)")]
        var request = URLRequest(url: components?.url ?? baseURL)
        request.httpMethod = "DELETE"
        applyHeaders(&request, anonKey: anonKey, accessToken: accessToken)
        return request
    }

    static func messagesRequest(baseURL: URL, anonKey: String, accessToken: String, userID: UUID) -> URLRequest {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("rest/v1/messages"), resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "or", value: "(sender.eq.\(userID.uuidString),recipient.eq.\(userID.uuidString))"),
            URLQueryItem(name: "order", value: "id.desc"),
            URLQueryItem(name: "limit", value: "200"),
        ]
        var request = URLRequest(url: components?.url ?? baseURL)
        applyHeaders(&request, anonKey: anonKey, accessToken: accessToken)
        return request
    }

    static func recentMessagesRequest(
        baseURL: URL, anonKey: String, accessToken: String, limit: Int
    ) -> URLRequest {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("rest/v1/messages"), resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        var request = URLRequest(url: components?.url ?? baseURL)
        applyHeaders(&request, anonKey: anonKey, accessToken: accessToken)
        return request
    }

    static func sendMessageRequest(
        baseURL: URL, anonKey: String, accessToken: String, sender: UUID, recipient: UUID, body: String
    ) throws -> URLRequest {
        var request = authorized(baseURL: baseURL, anonKey: anonKey, accessToken: accessToken, path: "rest/v1/messages")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "sender": sender.uuidString,
            "recipient": recipient.uuidString,
            "body": body,
        ])
        return request
    }

    private static func authorized(baseURL: URL, anonKey: String, accessToken: String, path: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        applyHeaders(&request, anonKey: anonKey, accessToken: accessToken)
        return request
    }

    private static func applyHeaders(_ request: inout URLRequest, anonKey: String, accessToken: String) {
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    /// Takes wildcard meaning away from `%` and `*` in user-typed search text.
    /// `*` is PostgREST's own stand-in for the SQL `%` wildcard in `ilike`
    /// filters (plain `%` is awkward in a URL), so both need escaping or a
    /// search for a literal "50%" would match everything.
    private static func escapeWildcards(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "*", with: "\\*")
    }

    /// Pulls `sub` out of a JWT's payload without verifying the signature:
    /// verification is the server's job, and by the time this client holds
    /// the token Supabase has already issued it. This only reads the claim
    /// already trusted to authenticate every other call made with it.
    static func subject(ofAccessToken token: String) -> UUID? {
        let segments = token.split(separator: ".")
        guard segments.count > 1 else { return nil }
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String
        else { return nil }
        return UUID(uuidString: sub)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SocialAPIError.status(-1, message: "") }
        guard (200..<300).contains(http.statusCode) else {
            throw SocialAPIError.status(http.statusCode, message: Self.serverMessage(data))
        }
        return data
    }

    /// PostgREST's own explanation, when the body is its error shape.
    ///
    /// Returns empty rather than throwing for anything else: a failure to read
    /// why a request failed must never replace the status code with a decoding
    /// error, which would hide the one fact we already have.
    static func serverMessage(_ data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        // `message` is the sentence; `hint` sometimes carries the useful half.
        let message = json["message"] as? String ?? ""
        let hint = json["hint"] as? String
        guard let hint, !hint.isEmpty else { return message }
        return message.isEmpty ? hint : "\(message) (\(hint))"
    }

    /// PostgREST emits timestamps with fractional seconds; the default
    /// `JSONDecoder` date strategy does not parse those.
    ///
    /// A bare `date` column arrives as "2001-04-12" with no clock at all,
    /// which neither ISO 8601 formatter accepts. `birth_date` is one, and
    /// without this last branch a profile row carrying a birthday failed to
    /// decode entirely, taking the person's name down with it.
    /// Internal rather than private so the decoding tests can exercise the
    /// date branches directly; the profile row is the only place the day
    /// format appears and it is worth a test of its own.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = withFraction.date(from: string) { return date }
            if let date = plain.date(from: string) { return date }
            if let date = SupabaseREST.day(from: string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected an ISO 8601 date, got \(string)"
            )
        }
        return decoder
    }()
}

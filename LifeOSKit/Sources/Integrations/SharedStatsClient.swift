import Foundation

/// The three figures a person chose to show their friends.
///
/// Every figure is optional and `shares` is separate from them, because the
/// two say different things: `shares` is the owner's standing answer, and a
/// nil figure is one that has not been pushed yet. A person who turned
/// sharing on this morning and has not opened the app since is sharing, with
/// nothing to show, which is not the same as having declined.
public struct SharedStats: Codable, Sendable, Equatable, Identifiable {
    public let userID: UUID
    public let shares: Bool
    public let streak: Int?
    public let daysTracked: Int?
    public let workouts: Int?

    public var id: UUID { userID }

    /// True only when there is a figure to draw. The profile screen omits the
    /// panel entirely otherwise: a row of dashes is not a fact.
    public var hasFigures: Bool {
        shares && (streak != nil || daysTracked != nil || workouts != nil)
    }

    public init(
        userID: UUID, shares: Bool,
        streak: Int? = nil, daysTracked: Int? = nil, workouts: Int? = nil
    ) {
        self.userID = userID
        self.shares = shares
        self.streak = streak
        self.daysTracked = daysTracked
        self.workouts = workouts
    }

    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case shares
        case streak
        case daysTracked = "days_tracked"
        case workouts = "workouts"
    }
}

/// Reads and writes `profile_stats`, the one table whose rows are visible to
/// accepted friends rather than to every signed-in user.
///
/// Same shape as `ProfileClient` and `SocialAPI`: a handful of small requests
/// over `URLSession`, no SDK. Row Level Security is what actually decides who
/// sees a row; this only shapes the request.
public struct SharedStatsClient: Sendable {
    private let baseURL: URL
    private let anonKey: String
    private let session: URLSession

    public init(baseURL: URL, anonKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.session = session
    }

    /// Writes the caller's own row.
    ///
    /// Sharing off sends explicit nulls rather than omitting the figures. An
    /// upsert leaves omitted columns standing, so omission would leave the
    /// last numbers on the server after someone asked for them to stop being
    /// shown, which is the one outcome this feature must not have.
    public func push(
        _ stats: SharedStats, accessToken: String
    ) async throws {
        let request = try Self.pushRequest(
            baseURL: baseURL, anonKey: anonKey, accessToken: accessToken, stats: stats
        )
        _ = try await perform(request)
    }

    /// The rows RLS lets the caller see among `ids`, keyed by user.
    ///
    /// A missing key means one of three things the caller cannot tell apart,
    /// and does not need to: no row, sharing off, or not an accepted friend.
    /// All three come out of the screen the same way, as a profile with no
    /// figures on it.
    public func stats(ids: [UUID], accessToken: String) async throws -> [UUID: SharedStats] {
        guard !ids.isEmpty else { return [:] }
        let request = Self.statsRequest(
            baseURL: baseURL, anonKey: anonKey, accessToken: accessToken, ids: ids
        )
        let data = try await perform(request)
        let rows = try JSONDecoder().decode([SharedStats].self, from: data)
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.userID, $0) })
    }

    // MARK: - Requests, built where they can be tested without a network

    static func pushRequest(
        baseURL: URL, anonKey: String, accessToken: String, stats: SharedStats
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/profile_stats"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        var row: [String: Any] = [
            "user_id": stats.userID.uuidString,
            "shares": stats.shares,
            "updated_at": SupabaseREST.timestamp(.now),
        ]
        row["streak"] = stats.shares ? (stats.streak.map { $0 as Any } ?? NSNull()) : NSNull()
        row["days_tracked"] = stats.shares ? (stats.daysTracked.map { $0 as Any } ?? NSNull()) : NSNull()
        row["workouts"] = stats.shares ? (stats.workouts.map { $0 as Any } ?? NSNull()) : NSNull()

        request.httpBody = try JSONSerialization.data(withJSONObject: [row])
        return request
    }

    static func statsRequest(
        baseURL: URL, anonKey: String, accessToken: String, ids: [UUID]
    ) -> URLRequest {
        let list = ids.map(\.uuidString).joined(separator: ",")
        var components = URLComponents(
            url: baseURL.appendingPathComponent("rest/v1/profile_stats"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "user_id", value: "in.(\(list))")]
        var request = URLRequest(url: components?.url ?? baseURL)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SocialAPIError.status(0) }
        guard (200..<300).contains(http.statusCode) else {
            throw SocialAPIError.status(http.statusCode)
        }
        return data
    }
}

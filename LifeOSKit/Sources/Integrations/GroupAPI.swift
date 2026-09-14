import Foundation

public struct SocialActivitySnapshot: Sendable, Equatable {
    public let streak: Int
    public let daysTracked: Int
    public let workouts: Int
    public let wellness: [SocialWellnessDay]
    public init(streak: Int, daysTracked: Int, workouts: Int, wellness: [SocialWellnessDay] = []) {
        self.streak = streak; self.daysTracked = daysTracked; self.workouts = workouts; self.wellness = wellness
    }
}

public struct GroupMember: Codable, Sendable, Equatable, Identifiable {
    public let groupID: UUID
    public let userID: UUID
    public let status: String
    public let sharesActivity: Bool
    public let sharesWellness: Bool?
    public var id: UUID { userID }
    public var isAccepted: Bool { status == "accepted" }
    enum CodingKeys: String, CodingKey {
        case groupID = "group_id", userID = "user_id", status, sharesActivity = "shares_activity", sharesWellness = "shares_wellness"
    }
    public init(groupID: UUID, userID: UUID, status: String, sharesActivity: Bool, sharesWellness: Bool = false) {
        self.groupID = groupID; self.userID = userID; self.status = status; self.sharesActivity = sharesActivity; self.sharesWellness = sharesWellness
    }
}

public struct SocialGroup: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let description: String
    public let ownerID: UUID
    public let members: [GroupMember]
    public var isInvitation: Bool { members.first?.status == "invited" }
    enum CodingKeys: String, CodingKey {
        case id, name, description, ownerID = "owner_id", members = "group_members"
    }
    public init(id: UUID, name: String, description: String, ownerID: UUID, members: [GroupMember]) {
        self.id = id; self.name = name; self.description = description; self.ownerID = ownerID; self.members = members
    }
}

public struct GroupMessage: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let groupID: UUID
    public let sender: UUID
    public let body: String
    public let clientID: UUID
    public let createdAt: Date
    enum CodingKeys: String, CodingKey {
        case id, sender, body, groupID = "group_id", clientID = "client_id", createdAt = "created_at"
    }
    public init(id: Int, groupID: UUID, sender: UUID, body: String, clientID: UUID, createdAt: Date) {
        self.id = id; self.groupID = groupID; self.sender = sender; self.body = body; self.clientID = clientID; self.createdAt = createdAt
    }
}

public enum LeaderboardMetric: String, CaseIterable, Sendable, Identifiable {
    case effort, recharge, rest
    public var id: String { rawValue }
    public var title: String { switch self { case .effort: "Effort"; case .recharge: "Recharge"; case .rest: "Rest" } }
    public var detail: String { switch self {
        case .effort: "Activity-goal progress"
        case .recharge: "Personal recovery estimate"
        case .rest: "Sleep-goal progress"
    } }
    public var explanation: String { switch self {
        case .effort: "Recorded active minutes ÷ your activity goal, capped at 100. Apple Health uses exercise time, WHOOP uses tracked workout time, and Fitbit uses fairly + very active minutes. This is an activity-load proxy; it does not reproduce WHOOP Strain. More is not always better."
        case .recharge: "An app estimate from HRV and resting heart rate relative to your own same-provider 28-day median. Needs at least 7 earlier days with both readings. 50 means near your usual baseline. It is not a recovery percentage or medical assessment."
        case .rest: "Recorded sleep ÷ your sleep goal, capped at 100. Extra sleep beyond the goal earns no extra points. Devices can measure sleep differently."
    } }
}

public struct LeaderboardEntry: Codable, Sendable, Equatable, Identifiable {
    public let userID: UUID
    public let displayName: String
    public let avatarPath: String?
    public let score: Int
    public let position: Int
    public let updatedAt: Date
    public let source: String?
    public let day: String?
    public var sourceName: String { switch source { case "appleHealth": "Apple Health"; case "whoop": "WHOOP"; case "fitbit": "Fitbit"; default: "Source unavailable" } }
    public var id: UUID { userID }
    enum CodingKeys: String, CodingKey {
        case source, day
        case userID = "user_id", displayName = "display_name", avatarPath = "avatar_path", score, position = "rank_position", updatedAt = "updated_at"
    }
    public init(userID: UUID, displayName: String, avatarPath: String? = nil, score: Int, position: Int, updatedAt: Date, source: String? = nil, day: String? = nil) {
        self.userID = userID; self.displayName = displayName; self.avatarPath = avatarPath
        self.score = score; self.position = position; self.updatedAt = updatedAt; self.source = source; self.day = day
    }
}

/// Authenticated transport. Membership, invitations and sharing are enforced by the database.
public struct GroupAPI: Sendable {
    private let baseURL: URL
    private let anonKey: String
    private let session: URLSession
    public init(baseURL: URL, anonKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL; self.anonKey = anonKey; self.session = session
    }

    public func groups(token: String) async throws -> [SocialGroup] {
        guard let user = SocialAPI.subject(ofAccessToken: token) else {
            throw SocialAPIError.status(401, message: "Sign in again to load groups")
        }
        return try await read("social_groups", query: [
            .init(name: "select", value: "*,group_members!inner(group_id,user_id,status,shares_activity,shares_wellness)"),
            .init(name: "group_members.user_id", value: "eq.\(user)"),
            .init(name: "order", value: "created_at.desc")
        ], token: token)
    }

    public func members(group: UUID, token: String) async throws -> [GroupMember] {
        try await read("group_members", query: [.init(name: "group_id", value: "eq.\(group)"),
                                               .init(name: "order", value: "joined_at.asc")], token: token)
    }

    public func messages(group: UUID, before: Int? = nil, token: String) async throws -> [GroupMessage] {
        var query: [URLQueryItem] = [.init(name: "group_id", value: "eq.\(group)"),
                                    .init(name: "order", value: "id.desc"), .init(name: "limit", value: "50")]
        if let before { query.append(.init(name: "id", value: "lt.\(before)")) }
        let rows: [GroupMessage] = try await read("group_messages", query: query, token: token)
        return rows.reversed()
    }

    public func create(id: UUID, name: String, description: String, invitees: [UUID], token: String) async throws -> UUID {
        let data = try await rpc("create_social_group", body: ["p_id": id.uuidString, "p_name": name,
            "p_description": description, "p_invitees": invitees.map(\.uuidString)], token: token)
        return try JSONDecoder().decode(UUID.self, from: data)
    }
    public func invite(group: UUID, user: UUID, token: String) async throws {
        _ = try await rpc("invite_group_member", body: ["p_group": group.uuidString, "p_user": user.uuidString], token: token)
    }
    public func answer(group: UUID, accept: Bool, token: String) async throws {
        _ = try await rpc("answer_group_invite", body: ["p_group": group.uuidString, "p_accept": accept], token: token)
    }
    public func leave(group: UUID, token: String) async throws {
        _ = try await rpc("leave_social_group", body: ["p_group": group.uuidString], token: token)
    }
    public func remove(group: UUID, user: UUID, token: String) async throws {
        _ = try await rpc("remove_group_member", body: ["p_group": group.uuidString, "p_user": user.uuidString], token: token)
    }
    public func send(group: UUID, body: String, clientID: UUID, token: String) async throws -> Int {
        let data = try await rpc("send_group_message", body: ["p_group": group.uuidString, "p_body": body,
                                                            "p_client_id": clientID.uuidString], token: token)
        return try JSONDecoder().decode(Int.self, from: data)
    }
    public func share(group: UUID, enabled: Bool, token: String) async throws {
        _ = try await rpc("set_group_wellness_sharing", body: ["p_group": group.uuidString, "p_shares": enabled], token: token)
    }
    public func publish(_ activity: SocialActivitySnapshot, token: String) async throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let days = try JSONSerialization.jsonObject(with: encoder.encode(activity.wellness))
        _ = try await rpc("publish_group_wellness", body: ["p_days": days], token: token)
    }
    public func leaderboard(group: UUID, metric: LeaderboardMetric, day: String = SocialWellness.dayKey(.now), token: String) async throws -> [LeaderboardEntry] {
        let data = try await rpc("group_wellness_leaderboard", body: ["p_group": group.uuidString, "p_metric": metric.rawValue, "p_day": day], token: token)
        return try SocialAPI.decoder.decode([LeaderboardEntry].self, from: data)
    }

    private func read<T: Decodable>(_ table: String, query: [URLQueryItem], token: String) async throws -> T {
        var url = URLComponents(url: baseURL.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        url.queryItems = query
        let data = try await perform(request(url: url.url!, token: token))
        return try SocialAPI.decoder.decode(T.self, from: data)
    }
    private func rpc(_ function: String, body: [String: Any], token: String) async throws -> Data {
        var req = request(url: baseURL.appendingPathComponent("rest/v1/rpc/\(function)"), token: token)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(req)
    }
    private func request(url: URL, token: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }
    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SocialAPIError.status(-1, message: "No server response") }
        guard (200..<300).contains(http.statusCode) else {
            throw SocialAPIError.status(http.statusCode, message: SocialAPI.serverMessage(data))
        }
        return data
    }
}

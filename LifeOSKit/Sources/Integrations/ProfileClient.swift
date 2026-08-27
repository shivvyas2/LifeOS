import Foundation
import Persistence

/// The profile as the server holds it.
public struct RemoteProfile: Codable, Sendable, Equatable {
    public var firstName: String
    public var lastName: String
    public var country: String
    public var birthDate: Date?
    public var heightCM: Double?
    /// Nil is "prefer not to say", which is a real answer and the default.
    public var gender: String?
    /// The object's path inside the avatars bucket, never a URL: a URL bakes
    /// in the project host and the signing scheme, both of which outlive their
    /// correctness.
    public var avatarPath: String?

    public init(
        firstName: String = "", lastName: String = "", country: String = "",
        birthDate: Date? = nil, heightCM: Double? = nil,
        gender: String? = nil, avatarPath: String? = nil
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.country = country
        self.birthDate = birthDate
        self.heightCM = heightCM
        self.gender = gender
        self.avatarPath = avatarPath
    }

    public var fullName: String {
        [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// What friend search matches on. Never empty, because the column is not
    /// nullable and a profile with no name is still a profile.
    public var displayName: String {
        fullName.isEmpty ? "Someone" : fullName
    }

    public func payload(userID: String) -> [String: Any] {
        var row: [String: Any] = [
            "user_id": userID,
            "display_name": displayName,
            "first_name": firstName,
            "last_name": lastName,
            "country": country,
            "updated_at": SupabaseREST.timestamp(.now),
        ]
        // Explicit nulls rather than omissions: this is an upsert of the whole
        // row, so a field cleared on the device has to clear on the server. An
        // omitted key would leave the old value standing and make deleting a
        // birthday impossible.
        row["birth_date"] = birthDate.map { SupabaseREST.day($0) } ?? NSNull()
        row["height_cm"] = heightCM ?? NSNull()
        row["gender"] = gender ?? NSNull()
        row["avatar_path"] = avatarPath ?? NSNull()
        return row
    }

    public init(json: [String: Any]) {
        self.firstName = json["first_name"] as? String ?? ""
        self.lastName = json["last_name"] as? String ?? ""
        self.country = json["country"] as? String ?? ""
        self.birthDate = (json["birth_date"] as? String).flatMap { SupabaseREST.day(from: $0) }
        self.heightCM = json["height_cm"] as? Double
        self.gender = json["gender"] as? String
        self.avatarPath = json["avatar_path"] as? String
    }
}

/// Reads and writes the profile row, and the avatar beside it.
///
/// The profile used to live in `auth.users.user_metadata` with a copy in
/// UserDefaults. That payload rides inside the JWT on every authenticated
/// request, which is the wrong place for anything that grows, and the copy was
/// not keyed by account, so with two accounts on one device the second saw the
/// first's name. A row in a table has neither problem.
public struct ProfileClient: Sendable {
    private let rest: SupabaseREST
    private let baseURL: URL
    private let anonKey: String
    private let session: URLSession

    public init(baseURL: URL, anonKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.session = session
        self.rest = SupabaseREST(baseURL: baseURL, anonKey: anonKey, session: session)
    }

    public func save(_ profile: RemoteProfile, userID: String, accessToken: String) async throws {
        let body = try SupabaseREST.encode([profile.payload(userID: userID)])
        try await rest.upsert(table: "profiles", body: body, accessToken: accessToken)
    }

    /// The signed-in user's own row, or nil when they have never saved one.
    public func load(userID: String, accessToken: String) async throws -> RemoteProfile? {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("rest/v1/profiles"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SupabaseREST.RESTError.server(
                status: (response as? HTTPURLResponse)?.statusCode ?? 0, message: ""
            )
        }
        return SupabaseREST.decode(data).first.map(RemoteProfile.init(json:))
    }

    // MARK: - Avatar

    /// One folder per account, named for the user id, which is what makes the
    /// storage policy a string comparison rather than a lookup.
    public static func avatarPath(userID: String) -> String { "\(userID)/avatar.jpg" }

    /// Uploads, replacing whatever was there.
    ///
    /// `upsert` rather than a delete and an insert: a person changing their
    /// picture should never be briefly without one, which is what the gap
    /// between two calls would give them.
    public func uploadAvatar(
        _ data: Data, userID: String, accessToken: String
    ) async throws -> String {
        let path = Self.avatarPath(userID: userID)
        var request = URLRequest(
            url: baseURL.appendingPathComponent("storage/v1/object/avatars/\(path)")
        )
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = data
        request.timeoutInterval = 60

        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw SupabaseREST.RESTError.server(status: status, message: "avatar upload failed")
        }
        return path
    }

    public func downloadAvatar(path: String) async throws -> Data {
        // The bucket is public, so this needs no token. A friend list shows
        // faces, and signing a URL per row per refresh is a great deal of work
        // to hide a picture someone put on a profile on purpose.
        var request = URLRequest(
            url: baseURL.appendingPathComponent("storage/v1/object/public/avatars/\(path)")
        )
        request.setValue(anonKey, forHTTPHeaderField: "apikey")

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status), !data.isEmpty else {
            throw SupabaseREST.RESTError.server(status: status, message: "avatar download failed")
        }
        return data
    }

    public func deleteAvatar(userID: String, accessToken: String) async throws {
        var request = URLRequest(
            url: baseURL.appendingPathComponent(
                "storage/v1/object/avatars/\(Self.avatarPath(userID: userID))"
            )
        )
        request.httpMethod = "DELETE"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // 404 means it was already gone, which is the outcome asked for.
        guard (200..<300).contains(status) || status == 404 else {
            throw SupabaseREST.RESTError.server(status: status, message: "avatar delete failed")
        }
    }
}

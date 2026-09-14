import Foundation
import Persistence

/// Reads the curated catalog. Read only: the table grants nothing else.
public struct WorkoutCatalogClient: Sendable {
    private let baseURL: URL, anonKey: String, session: URLSession
    public init(baseURL: URL, anonKey: String, session: URLSession = .shared) { self.baseURL = baseURL; self.anonKey = anonKey; self.session = session }

    public static func request(baseURL: URL, anonKey: String, accessToken: String) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/workout_videos"), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "select", value: "*"), .init(name: "order", value: "updated_at.asc")]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }
    public static func decode(_ data: Data) throws -> [CatalogVideoRow] { try SocialAPI.decoder.decode([CatalogVideoRow].self, from: data) }

    public func videos(accessToken: String) async throws -> [CatalogVideoRow] {
        let (data, response) = try await session.data(for: Self.request(baseURL: baseURL, anonKey: anonKey, accessToken: accessToken))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SocialAPIError.status((response as? HTTPURLResponse)?.statusCode ?? -1, message: SocialAPI.serverMessage(data))
        }
        return try Self.decode(data)
    }
}

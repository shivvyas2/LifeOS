import Foundation
import SwiftData

/// The wire row, snake_case on the server, decoded by the client.
public struct CatalogVideoRow: Codable, Sendable, Equatable {
    public var youtubeID: String, title: String, channel: String, durationS: Int
    public var goal: [String], split: String, muscles: [String], equipment: [String], intensity: Int, verifiedAt: Date
    enum CodingKeys: String, CodingKey {
        case youtubeID = "youtube_id", title, channel, durationS = "duration_s", goal, split, muscles, equipment, intensity, verifiedAt = "verified_at"
    }
    public init(youtubeID: String, title: String, channel: String, durationS: Int, goal: [String], split: String, muscles: [String], equipment: [String], intensity: Int, verifiedAt: Date) {
        self.youtubeID = youtubeID; self.title = title; self.channel = channel; self.durationS = durationS; self.goal = goal
        self.split = split; self.muscles = muscles; self.equipment = equipment; self.intensity = intensity; self.verifiedAt = verifiedAt
    }
}

/// A cached catalog row. The server is the source of truth; a refresh
/// replaces the set, so a video pulled from the catalog disappears here.
@Model
public final class CatalogVideo {
    #Unique<CatalogVideo>([\.youtubeID])
    public var youtubeID: String
    public var title: String
    public var channel: String
    public var durationS: Int
    public var goal: [String]
    public var split: String
    public var muscles: [String]
    public var equipment: [String]
    public var intensity: Int
    public var verifiedAt: Date
    public var cachedAt: Date

    public init(_ row: CatalogVideoRow, cachedAt: Date = .now) {
        youtubeID = row.youtubeID; title = row.title; channel = row.channel; durationS = row.durationS; goal = row.goal
        split = row.split; muscles = row.muscles; equipment = row.equipment; intensity = row.intensity; verifiedAt = row.verifiedAt
        self.cachedAt = cachedAt
    }
    public var thumbnailURL: URL { URL(string: "https://i.ytimg.com/vi/\(youtubeID)/hqdefault.jpg")! }
    public var durationMinutes: Int { Int((Double(durationS) / 60).rounded()) }
}

public enum CatalogStore {
    public static func all(context: ModelContext) throws -> [CatalogVideo] {
        try context.fetch(FetchDescriptor<CatalogVideo>(sortBy: [SortDescriptor(\.title)]))
    }
    /// Replace the cache with `rows`: update matches, insert new, delete absent.
    public static func upsert(_ rows: [CatalogVideoRow], context: ModelContext, now: Date = .now) throws {
        let existing = try all(context: context)
        // `uniquingKeysWith`, not `uniqueKeysWithValues`: the primary key
        // makes a duplicate id impossible from the real table, and a trap on a
        // malformed response is a crash where keeping the last row is not.
        let incoming = Dictionary(rows.map { ($0.youtubeID, $0) }, uniquingKeysWith: { _, last in last })
        for video in existing {
            if let row = incoming[video.youtubeID] {
                video.title = row.title; video.channel = row.channel; video.durationS = row.durationS; video.goal = row.goal
                video.split = row.split; video.muscles = row.muscles; video.equipment = row.equipment; video.intensity = row.intensity
                video.verifiedAt = row.verifiedAt; video.cachedAt = now
            } else { context.delete(video) }
        }
        let present = Set(existing.map(\.youtubeID))
        for row in rows where !present.contains(row.youtubeID) { context.insert(CatalogVideo(row, cachedAt: now)) }
        try context.save()
    }
}

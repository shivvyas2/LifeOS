import Foundation
import AppSurfaces

/// One result per day, in the account's defaults, as the forecast cache does.
/// A day's result is final once it was fetched after that day ended; today's
/// is fresh for five minutes.
public struct GitHubDayCache {
    public struct Entry: Codable, Equatable {
        public let card: ProjectCard?
        public let fetchedAt: Date
    }

    private let defaults: UserDefaults
    private static let key = "github.days"
    private static let kept = 120
    public static let todayFreshness: TimeInterval = 5 * 60

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func entry(for day: Date, calendar: Calendar = .current) -> Entry? {
        all()[WeatherCache.dayKey(day, calendar: calendar)]
    }

    public func store(_ card: ProjectCard?, for day: Date, fetchedAt: Date = .now, calendar: Calendar = .current) {
        var entries = all()
        entries[WeatherCache.dayKey(day, calendar: calendar)] = Entry(card: card, fetchedAt: fetchedAt)
        let kept = entries.sorted { $0.value.fetchedAt > $1.value.fetchedAt }.prefix(Self.kept)
        if let data = try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })) {
            defaults.set(data, forKey: Self.key)
        }
    }

    public func isFresh(_ entry: Entry, for day: Date, now: Date, calendar: Calendar = .current) -> Bool {
        let end = GitHubDay.bounds(for: day, calendar: calendar).end
        if entry.fetchedAt >= end { return true }
        return now.timeIntervalSince(entry.fetchedAt) < Self.todayFreshness && now < end
    }

    public func clear() { defaults.removeObject(forKey: Self.key) }

    private func all() -> [String: Entry] {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return decoded
    }
}

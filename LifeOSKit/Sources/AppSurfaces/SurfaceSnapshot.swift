import Foundation

/// A small, credential-free projection of the current account. One encoded value
/// replaces the entire cache, so a reader never joins fields from two accounts.
public struct SurfaceSnapshot: Codable, Equatable, Sendable {
    public static let appGroup = "group.com.shivvyas.lifeos"
    public static let storageKey = "surface.snapshot.v1"
    public var ownerID: String?
    public var generatedAt: Date
    public var expiresAt: Date
    public var measuredAt: Date?
    public var steps: Int?
    public var stepGoal: Int
    public var sleepMinutes: Int?
    public var exerciseMinutes: Int?

    public init(ownerID: String? = nil, generatedAt: Date = .now, measuredAt: Date? = nil,
                steps: Int? = nil, stepGoal: Int = 8000, sleepMinutes: Int? = nil,
                exerciseMinutes: Int? = nil, calendar: Calendar = .current) {
        self.ownerID = ownerID
        self.generatedAt = generatedAt
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: generatedAt))!
        expiresAt = min(midnight, generatedAt.addingTimeInterval(6 * 3600))
        self.measuredAt = measuredAt
        self.steps = steps.flatMap { $0 >= 0 ? $0 : nil }
        self.stepGoal = max(1, stepGoal)
        self.sleepMinutes = sleepMinutes.flatMap { $0 >= 0 ? $0 : nil }
        self.exerciseMinutes = exerciseMinutes.flatMap { $0 >= 0 ? $0 : nil }
    }

    public func isAvailable(at date: Date = .now) -> Bool {
        ownerID != nil && date >= generatedAt.addingTimeInterval(-60) && date < expiresAt
    }
    public var stepProgress: Double { min(1, max(0, Double(steps ?? 0) / Double(stepGoal))) }
    public var sleepText: String {
        guard let sleepMinutes else { return "—" }
        return "\(sleepMinutes / 60)h \(sleepMinutes % 60)m"
    }
    public static func read(from defaults: UserDefaults? = UserDefaults(suiteName: appGroup)) -> Self? {
        guard let data = defaults?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    public func write(to defaults: UserDefaults? = UserDefaults(suiteName: Self.appGroup)) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults?.set(data, forKey: Self.storageKey)
    }
    /// WatchConnectivity can deliver a queued older context after a newer reply.
    public func supersedes(_ previous: Self?) -> Bool {
        previous.map { generatedAt > $0.generatedAt } ?? true
    }
}

public enum SurfaceRoute: String, CaseIterable, Sendable {
    case today, health, activity, notifications
    public var url: URL { URL(string: "almanac://\(rawValue)")! }
    public init?(url: URL) {
        guard url.scheme == "almanac", url.user == nil, url.password == nil,
              url.port == nil, url.path.isEmpty, url.query == nil, url.fragment == nil,
              let host = url.host, let route = Self(rawValue: host) else { return nil }
        self = route
    }
}

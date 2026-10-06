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

/// Where a tap outside the app lands inside it. The four fixed routes are
/// hosts alone; `day` carries a calendar date as its only query.
public enum SurfaceRoute: Equatable, Sendable {
    case today, health, activity, notifications
    case day(Date)

    public static let fixed: [SurfaceRoute] = [.today, .health, .activity, .notifications]

    public var url: URL {
        switch self {
        case .today: URL(string: "almanac://today")!
        case .health: URL(string: "almanac://health")!
        case .activity: URL(string: "almanac://activity")!
        case .notifications: URL(string: "almanac://notifications")!
        case .day(let date): URL(string: "almanac://day?date=\(Self.dayFormatter().string(from: date))")!
        }
    }

    public init?(url: URL) {
        guard url.scheme == "almanac", url.user == nil, url.password == nil,
              url.port == nil, url.path.isEmpty, url.fragment == nil, let host = url.host else { return nil }
        if host == "day" {
            guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  items.count == 1, items[0].name == "date", let raw = items[0].value,
                  // Exactly `YYYY-MM-DD`: the ISO formatter would otherwise swallow a trailing time.
                  raw.count == 10, raw.allSatisfy({ $0.isNumber || $0 == "-" }),
                  let date = Self.dayFormatter().date(from: raw) else { return nil }
            self = .day(date)
            return
        }
        guard url.query == nil else { return nil }
        switch host {
        case "today": self = .today
        case "health": self = .health
        case "activity": self = .activity
        case "notifications": self = .notifications
        default: return nil
        }
    }

    /// A calendar date in the device's zone, the same shape the inbox's `day` uses.
    private static func dayFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current
        return formatter
    }
}

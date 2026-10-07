import Foundation

/// The day screen's GitHub source: the cache first, then the loader.
///
/// The token and the pin are read on every call, never captured, so a day
/// screen that stays open across a reconnect, a Disconnect or a new pin asks
/// with what is true now. A revoked token is remembered in the account's
/// defaults: until the person reconnects (or pulls to refresh and it works),
/// every day says so, cached or not.
///
/// `@unchecked Sendable` for `UserDefaults`, which Apple documents as
/// thread-safe.
public struct GitHubDaySource: @unchecked Sendable {
    public static let pinKey = "github.pinnedRepo"
    public static let pinMissingKey = "github.pinnedRepoMissing"
    public static let needsReconnectKey = "github.needsReconnect"

    let tokens: any GitHubTokenStoring
    let defaults: UserDefaults
    let transport: any GitHubTransport
    let calendar: Calendar

    public init(tokens: any GitHubTokenStoring, defaults: UserDefaults,
                transport: any GitHubTransport = URLSessionGitHubTransport(), calendar: Calendar = .current) {
        self.tokens = tokens; self.defaults = defaults; self.transport = transport; self.calendar = calendar
    }

    public static func needsReconnect(_ defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: needsReconnectKey)
    }

    public func project(for day: Date, isToday: Bool, force: Bool, now: Date = .now) async -> ProjectCardState? {
        guard let connection = tokens.load() else { return nil }
        if !force, Self.needsReconnect(defaults) { return .reconnect }
        let cache = GitHubDayCache(defaults: defaults)
        let cached = cache.entry(for: day, calendar: calendar)
        if !force, let cached, cache.isFresh(cached, for: day, now: now, calendar: calendar) {
            return cached.card.map { .card($0, asOf: nil) }
        }
        let loader = GitHubDayLoader(transport: transport, connection: connection,
                                     pinnedRepo: defaults.string(forKey: Self.pinKey), calendar: calendar)
        do {
            let result = try await loader.load(day: day, isToday: isToday)
            // A token cleared while the request was out must not refill the cache.
            guard tokens.load() == connection else { return nil }
            if case .reconnect? = result.state {
                defaults.set(true, forKey: Self.needsReconnectKey)
                return .reconnect
            }
            defaults.set(false, forKey: Self.needsReconnectKey)
            defaults.set(result.pinMissing, forKey: Self.pinMissingKey)
            if case .card(let card, _)? = result.state { cache.store(card, for: day, fetchedAt: now, calendar: calendar) }
            else { cache.store(nil, for: day, fetchedAt: now, calendar: calendar) }
            return result.state
        } catch {
            return cached?.card.map { .card($0, asOf: cached?.fetchedAt) }
        }
    }
}

import Foundation

/// The last read of each repo, per GitHub account, so moving between a
/// project's views does not read again. Keyed by login as well as repo: a
/// private repo read with one account is never handed to another account
/// signed in on the same phone. Cleared when GitHub is disconnected.
@MainActor
public final class GitHubStatusCache {
    public static let shared = GitHubStatusCache()

    private var entries: [String: (status: GitHubProjectStatus, at: Date)] = [:]
    private let maxAge: TimeInterval

    public init(maxAge: TimeInterval = 300) { self.maxAge = maxAge }

    private func key(_ login: String, _ repo: String) -> String { login.lowercased() + "|" + repo.lowercased() }

    public func store(_ status: GitHubProjectStatus, login: String, repo: String, at date: Date) {
        entries[key(login, repo)] = (status, date)
    }

    /// A read young enough to use instead of reading again.
    public func fresh(login: String, repo: String, now: Date) -> (status: GitHubProjectStatus, at: Date)? {
        guard let hit = entries[key(login, repo)], now.timeIntervalSince(hit.at) <= maxAge else { return nil }
        return hit
    }

    /// The last read whatever its age, for lines like "last commit 2h ago".
    public func latest(login: String, repo: String) -> GitHubProjectStatus? { entries[key(login, repo)]?.status }

    public func clear() { entries = [:] }
}

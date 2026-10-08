import Foundation
import Observation
import OSLog
import Integrations

private let projectGitHubLog = Logger(subsystem: "com.shivvyas.lifeos", category: "github")

/// One project's repo as last read: status for stages and branches, and the
/// default branch's history page by page. Reads are cached per repo for five
/// minutes so moving between views does not read again.
@MainActor @Observable
final class ProjectGitHubModel {
    enum Problem: Equatable { case notConnected, noAccess, reconnect, rateLimited, unavailable }

    private(set) var status: GitHubProjectStatus?
    private(set) var problem: Problem?
    private(set) var fetchedAt: Date?
    private(set) var history: [GitHubCommitItem] = []
    private(set) var historyDone = false

    let repo: String
    private weak var github: GitHubConnectionViewModel?
    private let transport: any GitHubTransport
    private let isFixture: Bool
    private var historyPage = 0

    private static var cache: [String: (status: GitHubProjectStatus, at: Date)] = [:]
    static func cached(_ repo: String) -> GitHubProjectStatus? { cache[repo.lowercased()]?.status }

    init(repo: String, github: GitHubConnectionViewModel?, transport: any GitHubTransport = URLSessionGitHubTransport()) {
        self.repo = repo; self.github = github; self.transport = transport; self.isFixture = false
    }

    /// Previews and UI tests: a fixed read, no network.
    init(fixture: GitHubProjectStatus, history: [GitHubCommitItem], repo: String = "shivvyas2/LifeOS") {
        self.repo = repo; self.github = nil; self.transport = URLSessionGitHubTransport(); self.isFixture = true
        self.status = fixture; self.history = history; self.historyDone = true; self.fetchedAt = .now
    }

    private var source: GitHubProjectSource? {
        guard let connection = github?.connection else { return nil }
        return GitHubProjectSource(transport: transport, token: connection.token, repo: repo)
    }

    func refresh(force: Bool = false) async {
        guard !isFixture else { return }
        let key = repo.lowercased()
        if !force, let hit = Self.cache[key], Date.now.timeIntervalSince(hit.at) < 300 {
            status = hit.status; fetchedAt = hit.at; problem = nil
            return
        }
        guard let source else { problem = .notConnected; return }
        do {
            let read = try await source.status()
            Self.cache[key] = (read, .now)
            status = read; fetchedAt = .now; problem = nil
        } catch GitHubProjectError.unauthorized {
            github?.markNeedsReconnect(); problem = .reconnect
        } catch GitHubProjectError.notFound {
            problem = .noAccess
        } catch GitHubProjectError.rateLimited {
            problem = .rateLimited
        } catch {
            projectGitHubLog.error("project status failed: \(String(describing: error))")
            problem = .unavailable
        }
    }

    func loadMoreHistory() async {
        guard !isFixture, !historyDone, let source, let branch = status?.defaultBranch else { return }
        historyPage += 1
        do {
            let page = try await source.history(branch: branch, page: historyPage)
            history += page
            historyDone = page.count < 30
        } catch {
            historyPage -= 1
            projectGitHubLog.error("project history failed: \(String(describing: error))")
        }
    }

    func commits(for branch: String) async -> [GitHubCommitItem] {
        guard let source, let base = status?.defaultBranch else { return [] }
        return (try? await source.branchCommits(base: base, head: branch)) ?? []
    }

    func readme() async -> String? { await source?.readme() }
}

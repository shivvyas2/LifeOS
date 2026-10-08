import Foundation
import Persistence

public struct GitHubBranchState: Equatable, Sendable {
    public let name: String
    public let lastCommitAt: Date?
    /// Commits on this branch that the default branch does not have.
    public let ahead: Int
    /// Commits on the default branch that this branch does not have.
    public let behind: Int
    public init(name: String, lastCommitAt: Date?, ahead: Int, behind: Int) {
        self.name = name; self.lastCommitAt = lastCommitAt; self.ahead = ahead; self.behind = behind
    }
}

public struct GitHubPullState: Equatable, Sendable {
    public enum State: String, Sendable { case open, closed, merged }
    public let number: Int
    public let title: String
    public let state: State
    public let url: URL
    public let mergedAt: Date?
    public let headBranch: String
    /// `owner/name` of the repo the head branch lives in; nil when GitHub
    /// no longer knows it (a deleted fork).
    public let headRepo: String?
    public init(number: Int, title: String, state: State, url: URL, mergedAt: Date?, headBranch: String, headRepo: String?) {
        self.number = number; self.title = title; self.state = state; self.url = url
        self.mergedAt = mergedAt; self.headBranch = headBranch; self.headRepo = headRepo
    }
}

public struct GitHubProjectStatus: Equatable, Sendable {
    public let defaultBranch: String
    public let branches: [GitHubBranchState]
    public let pulls: [GitHubPullState]
    public var lastCommitAt: Date? { branches.compactMap(\.lastCommitAt).max() }
    public init(defaultBranch: String, branches: [GitHubBranchState], pulls: [GitHubPullState]) {
        self.defaultBranch = defaultBranch; self.branches = branches; self.pulls = pulls
    }
}

public struct ResolvedStage: Equatable, Sendable {
    public let stage: FeatureStage
    public let detail: String
    public let prNumber: Int?
    public init(stage: FeatureStage, detail: String, prNumber: Int?) {
        self.stage = stage; self.detail = detail; self.prNumber = prNumber
    }
}

public enum BranchLink: Equatable, Sendable { case none, one(String), several([String]) }

/// Turns what GitHub says about a branch into a feature's stage. No network.
public enum FeatureStageResolver {
    public static func resolve(branch: String?, repo: String, status: GitHubProjectStatus, now: Date) -> ResolvedStage {
        guard let branch else { return ResolvedStage(stage: .planned, detail: "Not started", prNumber: nil) }
        // A PR beats the branch, and of the open and merged ones the newest
        // decides. A fork's PR from a branch of the same name is not ours.
        let ours = status.pulls.filter {
            $0.headBranch == branch && $0.state != .closed
                && $0.headRepo?.caseInsensitiveCompare(repo) == .orderedSame
        }
        if let latest = ours.max(by: { $0.number < $1.number }) {
            switch latest.state {
            case .open:
                return ResolvedStage(stage: .review, detail: "PR #\(latest.number) open", prNumber: latest.number)
            case .merged:
                let when = latest.mergedAt.map { GitHubRelative.short($0, now: now) } ?? "recently"
                return ResolvedStage(stage: .done, detail: "Merged \(when) · PR #\(latest.number)", prNumber: latest.number)
            case .closed:
                break
            }
        }
        guard let state = status.branches.first(where: { $0.name == branch }) else {
            return ResolvedStage(stage: .planned, detail: "Not started", prNumber: nil)
        }
        guard state.ahead > 0 else {
            return ResolvedStage(stage: .planned, detail: "Branch made, no commits yet", prNumber: nil)
        }
        let count = state.ahead == 1 ? "1 commit" : "\(state.ahead) commits"
        let when = state.lastCommitAt.map { " · " + GitHubRelative.short($0, now: now) } ?? ""
        return ResolvedStage(stage: .building, detail: count + when, prNumber: nil)
    }

    /// Lower-case ASCII words joined by `-`, at most 40 characters.
    public static func slug(_ title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        var out = ""
        var pendingDash = false
        for scalar in folded.unicodeScalars {
            if ("a"..."z").contains(Character(scalar)) || ("0"..."9").contains(Character(scalar)) {
                if pendingDash && !out.isEmpty { out.append("-") }
                out.unicodeScalars.append(scalar)
                pendingDash = false
            } else {
                pendingDash = true
            }
        }
        var cut = String(out.prefix(40))
        while cut.hasSuffix("-") { cut.removeLast() }
        return cut.isEmpty ? "feature" : cut
    }

    public static func suggestedBranch(_ title: String) -> String { "feat/" + slug(title) }

    /// A branch named for the feature: exactly the slug, or any prefix
    /// followed by `/slug`. Several matches link none; the page lists them.
    public static func link(title: String, branches: [String]) -> BranchLink {
        let slug = slug(title)
        let matches = branches.filter { $0 == slug || $0.hasSuffix("/" + slug) }.sorted()
        switch matches.count {
        case 0: return .none
        case 1: return .one(matches[0])
        default: return .several(matches)
        }
    }
}

public enum GitHubRelative {
    public static func short(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3_600: return "\(Int(seconds / 60))m ago"
        case ..<86_400: return "\(Int(seconds / 3_600))h ago"
        default: return "\(Int(seconds / 86_400))d ago"
        }
    }
}

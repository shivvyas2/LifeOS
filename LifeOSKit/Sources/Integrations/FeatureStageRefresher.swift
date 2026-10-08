import Foundation
import Persistence

/// Applies one read of the repo to a project's features: links the ones
/// with exactly one branch named for them, then writes each stage.
@MainActor
public enum FeatureStageRefresher {
    @discardableResult
    public static func apply(_ status: GitHubProjectStatus, repo: String, projectID: UUID,
                             store: ProjectsStore, now: Date) throws -> Bool {
        var changed = false
        let names = status.branches.map(\.name).filter { $0 != status.defaultBranch }
        for feature in try store.features(projectID: projectID) {
            var branch = feature.branch
            if branch == nil, feature.autoLink, case .one(let match) = FeatureStageRefresher.link(feature, names) {
                try store.updateFeature(id: feature.id, branch: .some(match))
                branch = match
                changed = true
            }
            let resolved = FeatureStageResolver.resolve(branch: branch, repo: repo, status: status, now: now)
            // A merged PR older than the read's window is missing, not
            // unmerged: a done feature never moves back for want of data.
            if feature.stage == .done, let number = feature.prNumber, resolved.stage != .done,
               !status.pulls.contains(where: { $0.number == number }) {
                continue
            }
            if try store.applyStage(featureID: feature.id, stage: resolved.stage, detail: resolved.detail,
                                    prNumber: resolved.prNumber, checkedAt: now) {
                changed = true
            }
        }
        return changed
    }

    /// The branches a feature could link to when more than one is named for it.
    public static func candidates(for feature: FeatureSnapshot, in status: GitHubProjectStatus) -> [String] {
        switch link(feature, status.branches.map(\.name)) {
        case .several(let names): names
        case .one(let name): [name]
        case .none: []
        }
    }

    private static func link(_ feature: FeatureSnapshot, _ branches: [String]) -> BranchLink {
        FeatureStageResolver.link(title: feature.title, branches: branches)
    }
}

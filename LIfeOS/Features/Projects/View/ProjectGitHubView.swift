import SwiftUI
import DesignSystem
import Persistence
import Integrations

/// The repo as it stands: history, branches and pull requests, in the
/// app's editorial style (numbered sections over hairlines) so it reads like
/// the rest of the app rather than like the tab's blocks.
struct ProjectGitHubView: View {
    @Bindable var github: ProjectGitHubModel
    let features: [FeatureSnapshot]
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            if let problem = github.problem { ProjectGitHubProblem(problem: problem) }

            VStack(alignment: .leading, spacing: 0) {
                EditorialSectionHeader(index: 1, title: "Commits") {
                    Text(github.status?.defaultBranch ?? "").font(LifeOSType.caption.monospaced())
                        .foregroundStyle(Editorial.quietInk(scheme))
                }
                if github.history.isEmpty && github.historyDone {
                    Text("No commits yet.").font(LifeOSType.secondary).padding(.vertical, Space.x2)
                }
                ForEach(github.history, id: \.sha) { commit in
                    Button { openURL(commit.htmlUrl) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(commit.subject).font(LifeOSType.rowTitle).lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text("\(commit.authorName) · \(GitHubRelative.short(commit.date, now: .now)) · \(commit.shortSHA)")
                                .font(LifeOSType.caption.monospaced()).foregroundStyle(Editorial.quietInk(scheme))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Space.x2)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .onAppear { if commit.sha == github.history.last?.sha { Task { await github.loadMoreHistory() } } }
                    Hairline()
                }
            }
            .task { if github.history.isEmpty { await github.loadMoreHistory() } }

            VStack(alignment: .leading, spacing: 0) {
                EditorialSectionHeader(index: 2, title: "Branches")
                ForEach(github.status?.branches ?? [], id: \.name) { branch in
                    let stale = branch.lastCommitAt.map { Date.now.timeIntervalSince($0) > 30 * 86_400 } ?? true
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(branch.name).font(LifeOSType.rowTitle.monospaced())
                            Spacer()
                            if let feature = features.first(where: { $0.branch == branch.name }) {
                                EditorialTag(feature.title)
                            }
                        }
                        Text("\(branch.ahead) ahead · \(branch.behind) behind"
                             + (branch.lastCommitAt.map { " · " + GitHubRelative.short($0, now: .now) } ?? ""))
                            .font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
                    }
                    .padding(.vertical, Space.x2)
                    .opacity(stale ? 0.45 : 1)
                    Hairline()
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                EditorialSectionHeader(index: 3, title: "Pull requests")
                let pulls = github.status?.pulls ?? []
                let shown = pulls.filter { $0.state == .open } + pulls.filter { $0.state == .merged }.prefix(5)
                if shown.isEmpty {
                    Text("No pull requests yet.").font(LifeOSType.secondary).padding(.vertical, Space.x2)
                }
                ForEach(shown, id: \.number) { pull in
                    Button { openURL(pull.url) } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text("#\(pull.number) \(pull.title)").font(LifeOSType.rowTitle).lineLimit(1)
                            Spacer()
                            EditorialTag(pull.state == .open ? "Open" : "Merged")
                        }
                        .padding(.vertical, Space.x2)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    Hairline()
                }
            }
        }
    }
}

/// One line saying why the repo could not be read, and what to do.
struct ProjectGitHubProblem: View {
    let problem: ProjectGitHubModel.Problem
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(message).font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
    }
    private var message: String {
        switch problem {
        case .notConnected: "Connect GitHub in Settings to update stages from your repo."
        case .noAccess: "This GitHub account cannot see the repo."
        case .reconnect: "GitHub needs you to sign in again, in Settings."
        case .rateLimited: "GitHub asked to slow down. Showing the last read."
        case .unavailable: "GitHub could not be reached. Showing the last read."
        }
    }
}

/// A feature's commits ahead of the default branch, and its PR.
struct FeatureCommits: View {
    let github: ProjectGitHubModel?
    let feature: FeatureSnapshot?
    @State private var commits: [GitHubCommitItem] = []
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let github, let feature, let branch = feature.branch {
            VStack(alignment: .leading, spacing: Space.x1) {
                EditorialSectionHeader(index: 2, title: "Commits")
                if let number = feature.prNumber,
                   let pull = github.status?.pulls.first(where: { $0.number == number }) {
                    Button { openURL(pull.url) } label: {
                        HStack {
                            Text("PR #\(number) · \(pull.title)").font(LifeOSType.rowTitle)
                            Spacer()
                            Image(systemName: "arrow.up.right").foregroundStyle(Editorial.quietInk(scheme))
                        }
                    }
                    .buttonStyle(.plain)
                }
                ForEach(commits, id: \.sha) { commit in
                    HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
                        Text(commit.shortSHA).font(LifeOSType.caption.monospaced())
                            .foregroundStyle(Editorial.quietInk(scheme))
                        Text(commit.subject).font(LifeOSType.body).lineLimit(1)
                    }
                }
                if commits.isEmpty {
                    Text("Nothing on \(branch) ahead of \(github.status?.defaultBranch ?? "main").")
                        .font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
                }
            }
            .task(id: branch) { commits = await github.commits(for: branch) }
        }
    }
}

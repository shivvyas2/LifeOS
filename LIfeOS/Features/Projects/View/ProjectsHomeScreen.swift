import SwiftUI
import DesignSystem
import Persistence
import Integrations

/// Projects, opened from Life: contributions, your projects, and today's
/// tasks across them, on the same paper and hairlines as every other screen.
struct ProjectsHomeScreen: View {
    @Bindable var model: ProjectsViewModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout
    @Environment(\.github) private var github
    @State private var creating = false
    @State private var showArchived = false
    @State private var open: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                HStack(alignment: .bottom) {
                    EditorialMasthead(eyebrow: "Life", title: "Projects", detail: summary)
                    Button("New") { creating = true }
                        .buttonStyle(.editorial(.secondary, size: .compact))
                        .accessibilityLabel("New project")
                }
                if let error = model.syncError {
                    Text(error).font(LifeOSType.caption)
                        .editorialCard(padding: Space.x2)
                }
                contributions
                EditorialSectionHeader(index: 2, title: "Your projects")
                if model.projects.isEmpty {
                    VStack(alignment: .leading, spacing: Space.x1) {
                        Text("No projects yet").editorialEyebrow()
                        Text("Start one with New. Add friends to share it.").font(LifeOSType.secondary)
                    }
                    .editorialCard()
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.x2),
                                         count: layout.isRegular ? 2 : 1), spacing: Space.x2) {
                    ForEach(model.projects) { project in
                        Button { open = project.id } label: { card(project) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("project.\(project.name)")
                    }
                }
                if !model.archived.isEmpty {
                    Button("Archived (\(model.archived.count))") { showArchived.toggle() }
                        .buttonStyle(.editorial(.quiet, size: .compact))
                    if showArchived { ForEach(model.archived) { project in card(project).opacity(0.6) } }
                }
                VStack(alignment: .leading, spacing: Space.x2) {
                    EditorialSectionHeader(index: 3, title: "Today's tasks")
                    if model.todayTasks.isEmpty {
                        Text("Nothing of yours due today.").font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
                    }
                    ForEach(model.todayTasks) { task in
                        Button { open = task.projectID } label: { ProjectTaskRow(task: task) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, layout.gutter)
            .padding(.leading, layout.railInset)
            .padding(.top, Space.x3)
            .padding(.bottom, layout.contentBottomInset)
        }
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
        .refreshable {
            await model.refresh()
            await model.loadContributions(from: github)
        }
        // Keyed to the connection, so connecting or disconnecting GitHub with
        // this tab open swaps the wall without leaving and coming back.
        .task(id: github?.changeCount) {
            model.load()
            await model.refresh()
            await model.loadContributions(from: github)
            // Read each linked repo once, so the cards can say when it last moved.
            for repo in Set(model.projects.compactMap(\.repo)) {
                await ProjectGitHubModel(repo: repo, github: github).refresh()
            }
        }
        .sheet(isPresented: $creating) {
            NewProjectSheet { name, scope, colour, starts, ends, repo in
                if let id = model.createProject(name: name, scope: scope, colour: colour, startsOn: starts,
                                                endsOn: ends, repo: repo) { open = id }
            }
        }
        .navigationDestination(item: $open) { id in ProjectScreen(model: model, projectID: id) }
    }

    private var contributions: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            EditorialSectionHeader(index: 1, title: "Contributions") {
                Text("\(model.contributionTotal) this year").font(LifeOSType.caption.monospacedDigit())
                    .foregroundStyle(Editorial.quietInk(scheme))
            }
            ContributionGrid(counts: model.contributions, colour: .moss, weeks: layout.isRegular ? nil : 26)
            Text(model.contributionsFromGitHub ? "From GitHub" : "Tasks you finished")
                .font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
        }
    }

    private func card(_ project: ProjectSnapshot) -> some View {
        let colour = ProjectColour(named: project.colour)
        return VStack(alignment: .leading, spacing: Space.x1) {
            HStack(spacing: Space.x1) {
                ProjectDot(colour: colour)
                Text(project.name).font(LifeOSType.sectionTitle)
            }
            if !project.scope.isEmpty {
                Text(project.scope).font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme)).lineLimit(2)
            }
            HStack(spacing: Space.x2) {
                EditorialProgressBar(fraction: project.fraction, colour: colour)
                Text("\(Int((project.fraction * 100).rounded()))%").font(LifeOSType.label).monospacedDigit()
            }
            if let progress = try? model.store?.featureProgress(projectID: project.id), progress.total > 0 {
                Text("\(progress.done) of \(progress.total) features done").font(LifeOSType.caption)
            }
            if let repo = project.repo, let last = ProjectGitHubModel.cached(repo, login: github?.connection?.login)?.lastCommitAt {
                Text("Last commit \(GitHubRelative.short(last, now: .now))").font(LifeOSType.caption)
                    .foregroundStyle(Editorial.quietInk(scheme))
            }
            HStack {
                if let next = project.nextMilestone {
                    Text("Next · \(next)").font(LifeOSType.caption).lineLimit(1)
                }
                Spacer()
                MemberAvatars(names: memberNames(project.id))
            }
        }
        .editorialCard()
    }

    /// "2 projects · 4 tasks today", under the title.
    private var summary: String? {
        guard !model.projects.isEmpty else { return nil }
        let projects = model.projects.count == 1 ? "1 project" : "\(model.projects.count) projects"
        let tasks = model.todayTasks.count == 1 ? "1 task today" : "\(model.todayTasks.count) tasks today"
        return "\(projects) · \(tasks)"
    }

    private func memberNames(_ project: UUID) -> [String] {
        ((try? model.store?.members(projectID: project)) ?? []).map { model.name($0.userID) }
    }
}

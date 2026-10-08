import SwiftUI
import DesignSystem
import Persistence

/// The Projects tab: contributions, your projects, and today's tasks across
/// them. Hard edges and colour, unlike the rest of the app.
struct ProjectsHomeScreen: View {
    @Bindable var model: ProjectsViewModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout
    @Environment(\.github) private var github
    @State private var creating = false
    @State private var showArchived = false
    @State private var open: UUID?

    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                HStack(alignment: .firstTextBaseline) {
                    Text("PROJECTS").font(LifeOSType.screenTitle.weight(.black)).tracking(1)
                    Spacer()
                    Button("+ NEW") { creating = true }
                        .font(LifeOSType.label.weight(.heavy))
                        .padding(.horizontal, Space.x2).padding(.vertical, Space.x1)
                        .foregroundStyle(LifeOSTokens.canvas.resolve(scheme))
                        .background(ink)
                        .buttonStyle(.plain)
                        .accessibilityLabel("New project")
                }
                if let error = model.syncError {
                    Text(error).font(LifeOSType.caption.weight(.heavy))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .brutalCard(padding: Space.x1)
                }
                contributions
                if model.projects.isEmpty {
                    VStack(alignment: .leading, spacing: Space.x1) {
                        Text("NO PROJECTS YET").brutalLabel()
                        Text("Start one with + NEW. Add friends to share it.").font(LifeOSType.secondary)
                    }
                    .brutalCard()
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
                    Button("ARCHIVED (\(model.archived.count))") { showArchived.toggle() }.brutalLabel().buttonStyle(.plain)
                    if showArchived { ForEach(model.archived) { project in card(project).opacity(0.6) } }
                }
                VStack(alignment: .leading, spacing: Space.x2) {
                    Text("TODAY'S TASKS").brutalLabel()
                    if model.todayTasks.isEmpty {
                        Text("Nothing of yours due today.").font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
                    }
                    ForEach(model.todayTasks) { task in
                        Button { open = task.projectID } label: { ProjectTaskRow(task: task) }
                            .buttonStyle(.plain)
                    }
                }
                .brutalCard()
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
            HStack {
                Text("CONTRIBUTIONS").brutalLabel()
                Spacer()
                Text("\(model.contributionTotal) THIS YEAR").font(LifeOSType.label.weight(.heavy))
            }
            ContributionGrid(counts: model.contributions, colour: .moss, weeks: layout.isRegular ? nil : 26)
            Text(model.contributionsFromGitHub ? "From GitHub" : "Tasks you finished")
                .font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
        }
        .brutalCard()
    }

    private func card(_ project: ProjectSnapshot) -> some View {
        let colour = ProjectColour(named: project.colour)
        return VStack(alignment: .leading, spacing: Space.x1) {
            Text(project.name.uppercased()).font(LifeOSType.sectionTitle.weight(.black))
            if !project.scope.isEmpty {
                Text(project.scope).font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme)).lineLimit(2)
            }
            HStack(spacing: Space.x2) {
                BrutalProgress(fraction: project.fraction, colour: colour)
                Text("\(Int((project.fraction * 100).rounded()))%").font(LifeOSType.label.weight(.heavy)).monospacedDigit()
            }
            HStack {
                if let next = project.nextMilestone {
                    Text("NEXT · \(next)").font(LifeOSType.caption.weight(.heavy)).lineLimit(1)
                }
                Spacer()
                MemberAvatars(names: memberNames(project.id))
            }
        }
        .foregroundStyle(ink)
        .brutalCard(header: colour.fill.resolve(scheme))
    }

    private func memberNames(_ project: UUID) -> [String] {
        ((try? model.store?.members(projectID: project)) ?? []).map { model.name($0.userID) }
    }
}

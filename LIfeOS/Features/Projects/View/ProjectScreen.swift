import SwiftUI
import DesignSystem
import Persistence
import Integrations
import Insights

/// One project: its header, then Plan, Board, Schedule, Milestones and List.
struct ProjectScreen: View {
    @Bindable var model: ProjectsViewModel
    let projectID: UUID

    enum Pane: String, CaseIterable {
        case plan = "PLAN", board = "BOARD", schedule = "SCHEDULE", milestones = "MILESTONES", list = "LIST"
        case github = "GITHUB"
    }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout
    @Environment(\.github) private var githubConnection
    @Environment(\.dismiss) private var dismiss
    @State private var pane: Pane

    /// Nil opens the plan for a project with a repo and the board otherwise.
    private let initialPaneWasDefault: Bool

    /// The repo as last read; built from the project's repo, or handed in by
    /// previews with a fixed read.
    @State private var github: ProjectGitHubModel?

    init(model: ProjectsViewModel, projectID: UUID, initialPane: Pane? = nil, github: ProjectGitHubModel? = nil,
         presetDraft: [PlanDraft.Item]? = nil) {
        self.model = model
        self.presetDraft = presetDraft
        self.projectID = projectID
        initialPaneWasDefault = initialPane == nil
        _pane = State(initialValue: initialPane ?? .board)
        _github = State(initialValue: github)
    }
    @State private var editing: TaskSheet.Target?
    @State private var showMembers = false
    @State private var newMilestone = ""
    @State private var revision = 0
    @State private var openFeature: UUID?
    @State private var drafting = false
    /// Previews open the draft sheet on a fixed draft instead of asking LIFO.
    private let presetDraft: [PlanDraft.Item]?

    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var project: ProjectSnapshot? { _ = revision; _ = model.projects; return try? model.store?.project(id: projectID) }
    private var tasks: [ProjectTaskSnapshot] { _ = revision; _ = model.projects; return (try? model.store?.tasks(projectID: projectID)) ?? [] }
    private var milestones: [MilestoneSnapshot] { _ = revision; _ = model.projects; return (try? model.store?.milestones(projectID: projectID)) ?? [] }
    private var members: [ProjectMemberSnapshot] { _ = revision; _ = model.projects; return (try? model.store?.members(projectID: projectID)) ?? [] }
    private var isOwner: Bool { project?.ownerID == model.me }
    private var features: [FeatureSnapshot] { _ = revision; _ = model.projects; return (try? model.store?.features(projectID: projectID)) ?? [] }
    private var featureProgress: FeatureProgress {
        _ = revision; _ = model.projects
        return (try? model.store?.featureProgress(projectID: projectID)) ?? .of([])
    }

    var body: some View {
        ScrollView {
            if let project {
                let colour = ProjectColour(named: project.colour)
                VStack(alignment: .leading, spacing: Space.x3) {
                    header(project, colour: colour)
                    panePicker
                    switch pane {
                    case .plan:
                        planPane
                    case .board:
                        ProjectBoardView(tasks: tasks, colour: colour, name: model.name,
                                         onOpen: { editing = .task($0) },
                                         onMove: { id, status, index in model.moveTask(id, to: status, at: index); revision += 1 })
                    case .schedule:
                        ProjectScheduleView(tasks: tasks, colour: colour, name: model.name,
                                            onOpen: { editing = .task($0) },
                                            onCreateAt: { start in editing = .new(start: start) })
                    case .milestones:
                        milestonesPane(colour: colour)
                    case .github:
                        if let github { ProjectGitHubView(github: github, features: features) }
                    case .list:
                        ProjectListView(tasks: tasks, milestones: milestones, members: members, colour: colour,
                                        name: model.name, onOpen: { editing = .task($0) })
                    }
                }
                .padding(.horizontal, layout.gutter)
                .padding(.leading, layout.railInset)
                .padding(.top, Space.x2)
                .padding(.bottom, layout.contentBottomInset)
            }
        }
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
        .refreshable { await model.refresh(); await refreshStages(force: true); revision += 1 }
        // Every five minutes while the project is on screen, as well as on
        // open and on pull to refresh.
        .task(id: project?.repo) {
            guard let repo = project?.repo else { return }
            if github?.repo != repo { github = ProjectGitHubModel(repo: repo, github: githubConnection) }
            while !Task.isCancelled {
                await refreshStages(force: false)
                try? await Task.sleep(for: .seconds(300))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ownerMenu }
        }
        .sheet(item: $editing, onDismiss: { revision += 1 }) { target in
            TaskSheet(model: model, projectID: projectID, target: target, members: members, milestones: milestones,
                      features: features)
        }
        .sheet(isPresented: $showMembers, onDismiss: { revision += 1 }) {
            ProjectMembersSheet(model: model, projectID: projectID, isOwner: isOwner)
        }
        .navigationDestination(item: layout.isRegular ? .constant(nil) : $openFeature) { id in
            ScrollView {
                featureDetail(id)
                    .padding(.horizontal, layout.gutter)
                    .padding(.leading, layout.railInset)
                    .padding(.vertical, Space.x2)
            }
            .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
            .onDisappear { revision += 1 }
        }
        .task { if initialPaneWasDefault, project?.repo != nil { pane = .plan } }
        .sheet(isPresented: $drafting, onDismiss: { revision += 1 }) {
            PlanDraftSheet(model: model, projectID: projectID, github: github, preset: presetDraft)
        }
        .onAppear { if presetDraft != nil { drafting = true } }
    }

    private func header(_ project: ProjectSnapshot, colour: ProjectColour) -> some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(project.name.uppercased()).font(LifeOSType.screenTitle.weight(.black))
            if !project.scope.isEmpty { Text(project.scope).font(LifeOSType.body) }
            HStack(spacing: Space.x2) {
                if let start = project.startsOn, let end = project.endsOn {
                    Text("\(start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(LifeOSType.caption.weight(.heavy))
                }
                if let repo = project.repo { Text(repo).font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme)) }
                Spacer()
                Button { showMembers = true } label: { MemberAvatars(names: members.map { model.name($0.userID) }) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Members")
            }
            HStack(spacing: Space.x2) {
                BrutalProgress(fraction: project.fraction, colour: colour)
                Text("\(project.done)/\(project.total)").font(LifeOSType.label.weight(.heavy)).monospacedDigit()
                Button("+ TASK") { editing = .new(start: nil) }
                    .font(LifeOSType.label.weight(.heavy))
                    .padding(.horizontal, Space.x2).padding(.vertical, Space.x1)
                    .foregroundStyle(LifeOSTokens.canvas.resolve(scheme))
                    .background(ink)
                    .buttonStyle(.plain)
                    .accessibilityLabel("New task")
            }
        }
        .brutalCard(header: colour.fill.resolve(scheme))
    }

    /// On an iPad the plan and the open feature sit side by side.
    @ViewBuilder private var planPane: some View {
        if layout.isRegular {
            HStack(alignment: .top, spacing: Space.x4) {
                planView.frame(maxWidth: 420)
                if let selected = openFeature {
                    featureDetail(selected).id(selected)
                } else {
                    Text("Pick a feature to see its branch, commits and tasks.")
                        .font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
                        .editorialCard()
                }
            }
        } else {
            planView
        }
    }

    private func featureDetail(_ id: UUID) -> some View {
        let feature = try? model.store?.feature(id: id)
        let candidates = feature.flatMap { f in github?.status.map { FeatureStageRefresher.candidates(for: f, in: $0) } } ?? []
        return FeatureDetailView(model: model, featureID: id, candidates: candidates, branches: branchNames,
                                 commits: { FeatureCommits(github: github, feature: try? model.store?.feature(id: id)) })
    }

    private var branchNames: [String] {
        guard let status = github?.status else { return [] }
        return status.branches.map(\.name).filter { $0 != status.defaultBranch }
    }

    private func refreshStages(force: Bool) async {
        guard let github, let repo = project?.repo, let store = model.store else { return }
        await github.refresh(force: force)
        guard let status = github.status else { return }
        if (try? FeatureStageRefresher.apply(status, repo: repo, projectID: projectID, store: store, now: .now)) == true {
            model.syncAfterStages()
        }
        revision += 1
    }

    /// Where the stages came from, or why they could not be refreshed.
    @ViewBuilder private var planGitHubLine: some View {
        if let github {
            if let problem = github.problem {
                ProjectGitHubProblem(problem: problem)
                if let checked = features.compactMap(\.stageCheckedAt).max() {
                    Text("As of \(GitHubRelative.short(checked, now: .now))").font(LifeOSType.caption)
                        .foregroundStyle(Editorial.quietInk(scheme))
                }
            } else if let fetched = github.fetchedAt {
                Text("From GitHub · \(GitHubRelative.short(fetched, now: .now))").font(LifeOSType.caption)
                    .foregroundStyle(Editorial.quietInk(scheme))
            }
        }
    }

    private var planView: some View {
        ProjectPlanView(
            features: features, progress: featureProgress,
            header: { planGitHubLine },
            onOpen: { openFeature = $0 },
            onAdd: { title in model.createFeature(in: projectID, title: title); revision += 1 },
            onMove: { id, index in model.moveFeature(id, to: index); revision += 1 },
            onDelete: { id in model.deleteFeature(id); revision += 1 },
            footer: {
                Button(features.isEmpty ? "Draft with LIFO" : "Draft more with LIFO") { drafting = true }
                    .buttonStyle(.editorial(features.isEmpty ? .primary : .secondary))
            })
    }

    /// Five panes do not fit a phone's width evenly, so there the row scrolls.
    @ViewBuilder private var panePicker: some View {
        if layout.isRegular {
            paneRow(minWidth: nil)
        } else {
            ScrollView(.horizontal, showsIndicators: false) { paneRow(minWidth: 76) }
        }
    }

    private func paneRow(minWidth: CGFloat?) -> some View {
        HStack(spacing: 0) {
            ForEach(Pane.allCases.filter { $0 != .github || project?.repo != nil }, id: \.self) { option in
                Button { pane = option } label: {
                    Text(option.rawValue)
                        .font(LifeOSType.caption.weight(.heavy)).tracking(0.8)
                        .frame(minWidth: minWidth, maxWidth: minWidth == nil ? .infinity : nil)
                        .padding(.vertical, Space.x1).padding(.horizontal, Space.x1)
                        .foregroundStyle(pane == option ? LifeOSTokens.canvas.resolve(scheme) : ink)
                        .background(pane == option ? ink : .clear)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(pane == option ? .isSelected : [])
            }
        }
        .overlay(Rectangle().strokeBorder(ink, lineWidth: 2))
    }

    private func milestonesPane(colour: ProjectColour) -> some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            ForEach(milestones) { milestone in
                VStack(alignment: .leading, spacing: Space.x1) {
                    HStack {
                        Text(milestone.title.uppercased()).font(LifeOSType.rowTitle.weight(.heavy))
                        Spacer()
                        if let due = milestone.dueOn {
                            Text(due.formatted(.dateTime.month(.abbreviated).day())).font(LifeOSType.caption.weight(.heavy))
                        }
                    }
                    HStack(spacing: Space.x2) {
                        BrutalProgress(fraction: milestone.total == 0 ? 0 : Double(milestone.done) / Double(milestone.total),
                                       colour: colour)
                        Text("\(milestone.done)/\(milestone.total)").font(LifeOSType.label.weight(.heavy)).monospacedDigit()
                    }
                    ForEach(tasks.filter { $0.milestoneID == milestone.id }) { task in
                        Button { editing = .task(task.id) } label: {
                            ProjectTaskRow(task: task, owner: task.ownerID.map(model.name))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .brutalCard()
                .accessibilityAction(named: "Move up") {
                    model.moveMilestone(milestone.id, to: max(milestone.position - 1, 0)); revision += 1
                }
                .accessibilityAction(named: "Move down") {
                    model.moveMilestone(milestone.id, to: milestone.position + 1); revision += 1
                }
            }
            HStack(spacing: Space.x1) {
                TextField("New milestone", text: $newMilestone)
                    .font(LifeOSType.body)
                    .padding(Space.x1)
                    .overlay(Rectangle().strokeBorder(ink, lineWidth: 2))
                Button("+ MILESTONE") {
                    let title = newMilestone.trimmingCharacters(in: .whitespaces)
                    guard !title.isEmpty else { return }
                    model.createMilestone(in: projectID, title: title, dueOn: nil)
                    newMilestone = ""
                    revision += 1
                }
                .font(LifeOSType.label.weight(.heavy))
                .buttonStyle(.plain)
            }
        }
    }

    private var ownerMenu: some View {
        Menu {
            Button("Members", systemImage: "person.2") { showMembers = true }
            if isOwner, let project {
                Button("Archive", systemImage: "archivebox") {
                    model.updateProject(projectID, archived: !project.isArchived)
                    dismiss()
                }
            } else {
                Button("Leave project", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    if let me = model.me { model.removeMember(me, from: projectID) }
                    dismiss()
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Project options")
    }
}

import SwiftUI
import DesignSystem
import Persistence

/// One project: its header, then Board, Schedule, Milestones and List.
struct ProjectScreen: View {
    @Bindable var model: ProjectsViewModel
    let projectID: UUID

    enum Pane: String, CaseIterable { case board = "BOARD", schedule = "SCHEDULE", milestones = "MILESTONES", list = "LIST" }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout
    @Environment(\.dismiss) private var dismiss
    @State private var pane: Pane

    init(model: ProjectsViewModel, projectID: UUID, initialPane: Pane = .board) {
        self.model = model
        self.projectID = projectID
        _pane = State(initialValue: initialPane)
    }
    @State private var editing: TaskSheet.Target?
    @State private var showMembers = false
    @State private var newMilestone = ""
    @State private var revision = 0

    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var project: ProjectSnapshot? { _ = revision; _ = model.projects; return try? model.store?.project(id: projectID) }
    private var tasks: [ProjectTaskSnapshot] { _ = revision; _ = model.projects; return (try? model.store?.tasks(projectID: projectID)) ?? [] }
    private var milestones: [MilestoneSnapshot] { _ = revision; _ = model.projects; return (try? model.store?.milestones(projectID: projectID)) ?? [] }
    private var members: [ProjectMemberSnapshot] { _ = revision; _ = model.projects; return (try? model.store?.members(projectID: projectID)) ?? [] }
    private var isOwner: Bool { project?.ownerID == model.me }

    var body: some View {
        ScrollView {
            if let project {
                let colour = ProjectColour(named: project.colour)
                VStack(alignment: .leading, spacing: Space.x3) {
                    header(project, colour: colour)
                    panePicker
                    switch pane {
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
        .refreshable { await model.refresh(); revision += 1 }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ownerMenu }
        }
        .sheet(item: $editing, onDismiss: { revision += 1 }) { target in
            TaskSheet(model: model, projectID: projectID, target: target, members: members, milestones: milestones)
        }
        .sheet(isPresented: $showMembers, onDismiss: { revision += 1 }) {
            ProjectMembersSheet(model: model, projectID: projectID, isOwner: isOwner)
        }
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

    private var panePicker: some View {
        HStack(spacing: 0) {
            ForEach(Pane.allCases, id: \.self) { option in
                Button { pane = option } label: {
                    Text(option.rawValue)
                        .font(LifeOSType.caption.weight(.heavy)).tracking(0.8)
                        .frame(maxWidth: .infinity).padding(.vertical, Space.x1)
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

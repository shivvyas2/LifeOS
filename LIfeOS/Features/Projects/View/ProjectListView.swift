import SwiftUI
import DesignSystem
import Persistence

/// Every task, filtered by status, owner and milestone, sorted by due date
/// then position.
struct ProjectListView: View {
    let tasks: [ProjectTaskSnapshot]
    let milestones: [MilestoneSnapshot]
    let members: [ProjectMemberSnapshot]
    let colour: ProjectColour
    let name: (UUID?) -> String
    var onOpen: (UUID) -> Void
    @State private var status: ProjectStatus?
    @State private var owner: UUID?
    @State private var milestone: UUID?
    @Environment(\.colorScheme) private var scheme

    private var shown: [ProjectTaskSnapshot] {
        tasks.filter { task in
            (status == nil || task.status == status)
                && (owner == nil || task.ownerID == owner)
                && (milestone == nil || task.milestoneID == milestone)
        }
        .sorted { ($0.dueOn ?? .distantFuture, $0.position) < ($1.dueOn ?? .distantFuture, $1.position) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            HStack(spacing: Space.x1) {
                Menu(status?.label ?? "All statuses") {
                    Button("All statuses") { status = nil }
                    ForEach(ProjectStatus.allCases, id: \.self) { option in Button(option.label) { status = option } }
                }
                Menu(owner.map(name) ?? "Anyone") {
                    Button("Anyone") { owner = nil }
                    ForEach(members) { member in Button(name(member.userID)) { owner = member.userID } }
                }
                Menu(milestones.first { $0.id == milestone }?.title ?? "Any milestone") {
                    Button("Any milestone") { milestone = nil }
                    ForEach(milestones) { item in Button(item.title) { milestone = item.id } }
                }
            }
            .font(LifeOSType.caption.weight(.medium))
            .tint(LifeOSTokens.primaryText.resolve(scheme))
            if shown.isEmpty { Text("No tasks match.").font(LifeOSType.secondary) }
            ForEach(shown) { task in
                Button { onOpen(task.id) } label: { ProjectTaskRow(task: task, owner: task.ownerID.map(name)) }
                    .buttonStyle(.plain)
                Hairline()
            }
        }
        .editorialCard()
    }
}

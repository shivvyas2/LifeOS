import SwiftUI
import DesignSystem
import Persistence

/// To do, Doing, Done: cards dragged within and across columns. On a phone
/// the columns scroll sideways, one and a half on screen.
struct ProjectBoardView: View {
    let tasks: [ProjectTaskSnapshot]
    let colour: ProjectColour
    let name: (UUID?) -> String
    var onOpen: (UUID) -> Void
    var onMove: (UUID, ProjectStatus, Int) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout
    @State private var targeted: ProjectStatus?

    var body: some View {
        GeometryReader { proxy in
            let width = layout.isRegular ? (proxy.size.width - 2 * Space.x2) / 3 : proxy.size.width / 1.5
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Space.x2) {
                    ForEach(ProjectStatus.allCases, id: \.self) { status in column(status).frame(width: width) }
                }
            }
        }
        .frame(minHeight: 420)
    }

    private func column(_ status: ProjectStatus) -> some View {
        let cards = tasks.filter { $0.status == status }.sorted { $0.position < $1.position }
        let ink = LifeOSTokens.primaryText.resolve(scheme)
        return VStack(alignment: .leading, spacing: Space.x1) {
            HStack {
                Text(status.label).brutalLabel()
                Spacer()
                Text("\(cards.count)").font(LifeOSType.caption.weight(.heavy))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(colour.fill.resolve(scheme))
                    .overlay(Rectangle().strokeBorder(ink, lineWidth: 2))
            }
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, task in
                Button { onOpen(task.id) } label: { card(task) }
                    .buttonStyle(.plain)
                    .draggable(task.id.uuidString) {
                        Text(task.title).font(LifeOSType.rowTitle).padding(Space.x1).brutalCard(padding: Space.x1)
                    }
                    .dropDestination(for: String.self) { ids, _ in
                        guard let id = ids.first.flatMap(UUID.init(uuidString:)) else { return false }
                        onMove(id, status, index)
                        return true
                    }
                    .accessibilityIdentifier("board.card.\(task.title)")
                    .accessibilityAction(named: "Move to \(next(status).label)") { onMove(task.id, next(status), 0) }
            }
            // Below the last card: drop here for the end of the column.
            Rectangle().fill(targeted == status ? colour.ramp(level: 1).resolve(scheme) : .clear)
                .frame(maxWidth: .infinity, minHeight: 56)
                .overlay(Rectangle().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(Editorial.quietInk(scheme)))
                .dropDestination(for: String.self) { ids, _ in
                    guard let id = ids.first.flatMap(UUID.init(uuidString:)) else { return false }
                    onMove(id, status, cards.count)
                    return true
                } isTargeted: { over in targeted = over ? status : (targeted == status ? nil : targeted) }
                .accessibilityIdentifier("board.drop.\(status.rawValue)")
        }
        .padding(Space.x1)
        .overlay(Rectangle().strokeBorder(ink, lineWidth: 2))
    }

    private func next(_ status: ProjectStatus) -> ProjectStatus {
        switch status { case .todo: .doing; case .doing: .done; case .done: .todo }
    }

    private func card(_ task: ProjectTaskSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Space.half) {
            Text(task.title).font(LifeOSType.rowTitle).strikethrough(task.status == .done).lineLimit(3)
            HStack {
                if let start = task.startsAt {
                    Text(start.formatted(.dateTime.weekday(.abbreviated).hour().minute())).font(LifeOSType.caption.weight(.heavy))
                } else if let due = task.dueOn {
                    Text(due.formatted(.dateTime.month(.abbreviated).day())).font(LifeOSType.caption.weight(.heavy))
                }
                Spacer()
                if task.ownerID != nil { MemberAvatars(names: [name(task.ownerID)], limit: 1) }
            }
        }
        .brutalCard(padding: Space.x1)
    }
}

import SwiftUI
import DesignSystem
import Persistence

/// Initials in small paper circles with a hairline edge, overlapping a little.
struct MemberAvatars: View {
    let names: [String]
    var limit = 3
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: -6) {
            ForEach(Array(names.prefix(limit).enumerated()), id: \.offset) { _, name in
                Text(initials(name))
                    .font(LifeOSType.caption.weight(.medium))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(LifeOSTokens.cardSurface.resolve(scheme)))
                    .overlay(Circle().strokeBorder(Editorial.rule(scheme)))
            }
            if names.count > limit {
                Text("+\(names.count - limit)").font(LifeOSType.caption)
                    .foregroundStyle(Editorial.quietInk(scheme)).padding(.leading, 10)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(names.joined(separator: ", "))
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }
}

/// To do, Doing, Done as the app's outlined tag. Done is quiet; nothing here
/// takes the accent, which stays reserved for what is live.
struct StatusChip: View {
    let status: ProjectStatus
    var colour: ProjectColour = .tomato

    var body: some View {
        EditorialTag(status.label).opacity(status == .done ? 0.6 : 1)
    }
}

/// A thin rounded bar on a hairline track: ink, or the project's colour when
/// it stands for one project.
struct EditorialProgressBar: View {
    let fraction: Double
    var colour: ProjectColour? = nil
    var height: CGFloat = 4
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Editorial.rule(scheme))
                Capsule().fill(colour?.fill.resolve(scheme) ?? LifeOSTokens.primaryText.resolve(scheme))
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}

/// A project's colour as a small dot beside its name: the one place the
/// colour shows outside progress and the contribution wall.
struct ProjectDot: View {
    let colour: ProjectColour
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Circle().fill(colour.fill.resolve(scheme)).frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}

/// One task as a row: the project's dot, title, status, time.
struct ProjectTaskRow: View {
    let task: ProjectTaskSnapshot
    var owner: String? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let colour = ProjectColour(named: task.colour)
        HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
            ProjectDot(colour: colour)
            VStack(alignment: .leading, spacing: Space.half) {
                Text(task.title).font(LifeOSType.rowTitle).strikethrough(task.status == .done)
                HStack(spacing: Space.x1) {
                    StatusChip(status: task.status, colour: colour)
                    Text(task.projectName).font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
                    Spacer(minLength: 0)
                    if let start = task.startsAt {
                        Text(start.formatted(date: .omitted, time: .shortened)).font(LifeOSType.caption.monospacedDigit())
                    } else if let due = task.dueOn {
                        Text(due.formatted(.dateTime.month(.abbreviated).day())).font(LifeOSType.caption.monospacedDigit())
                    }
                    if let owner { MemberAvatars(names: [owner], limit: 1) }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

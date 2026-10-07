import SwiftUI
import DesignSystem
import Persistence

/// Initials in square ink-bordered tiles, overlapping a little.
struct MemberAvatars: View {
    let names: [String]
    var limit = 3
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: -6) {
            ForEach(Array(names.prefix(limit).enumerated()), id: \.offset) { _, name in
                Text(initials(name))
                    .font(LifeOSType.caption.weight(.heavy))
                    .frame(width: 26, height: 26)
                    .background(LifeOSTokens.cardSurface.resolve(scheme))
                    .overlay(Rectangle().strokeBorder(LifeOSTokens.primaryText.resolve(scheme), lineWidth: 2))
            }
            if names.count > limit {
                Text("+\(names.count - limit)").font(LifeOSType.caption.weight(.heavy)).padding(.leading, 10)
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

/// `TO DO`, `DOING`, `DONE` in a hard box; Doing filled with the project colour.
struct StatusChip: View {
    let status: ProjectStatus
    var colour: ProjectColour = .tomato
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink = LifeOSTokens.primaryText.resolve(scheme)
        Text(status.label)
            .font(LifeOSType.caption.weight(.heavy)).tracking(0.8)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(status == .done ? LifeOSTokens.canvas.resolve(scheme) : ink)
            .background(status == .doing ? colour.fill.resolve(scheme) : status == .done ? ink : .clear)
            .overlay(Rectangle().strokeBorder(ink, lineWidth: 2))
    }
}

/// A flat bar in the project's colour with an ink frame.
struct BrutalProgress: View {
    let fraction: Double
    let colour: ProjectColour
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(LifeOSTokens.cardSurface.resolve(scheme))
                Rectangle().fill(colour.fill.resolve(scheme)).frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
            .overlay(Rectangle().strokeBorder(LifeOSTokens.primaryText.resolve(scheme), lineWidth: 2))
        }
        .frame(height: 14)
        .accessibilityElement()
        .accessibilityLabel("\(Int((fraction * 100).rounded())) percent done")
    }
}

/// One task as a row: the project's colour tick, title, status, time.
struct ProjectTaskRow: View {
    let task: ProjectTaskSnapshot
    var owner: String? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let colour = ProjectColour(named: task.colour)
        HStack(alignment: .top, spacing: Space.x2) {
            Rectangle().fill(colour.fill.resolve(scheme)).frame(width: 6)
            VStack(alignment: .leading, spacing: Space.half) {
                Text(task.title).font(LifeOSType.rowTitle).strikethrough(task.status == .done)
                HStack(spacing: Space.x1) {
                    StatusChip(status: task.status, colour: colour)
                    Text(task.projectName).font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
                    Spacer(minLength: 0)
                    if let start = task.startsAt {
                        Text(start.formatted(date: .omitted, time: .shortened)).font(LifeOSType.caption.weight(.heavy))
                    } else if let due = task.dueOn {
                        Text(due.formatted(.dateTime.month(.abbreviated).day())).font(LifeOSType.caption.weight(.heavy))
                    }
                    if let owner { MemberAvatars(names: [owner], limit: 1) }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

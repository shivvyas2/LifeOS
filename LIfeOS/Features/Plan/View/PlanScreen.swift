import SwiftUI
import DesignSystem
import Persistence

struct PlanScreen: View {
    let snapshot: PlanSnapshot
    @Binding var section: PlanSection

    var onAdd: () -> Void = {}
    var onAdvance: (UUID) -> Void = { _ in }
    var onToggleHabit: (UUID) -> Void = { _ in }
    var onDelete: (UUID) -> Void = { _ in }

    var body: some View {
        GradientCanvas(hue: section.hue) {
            ScrollView {
                VStack(spacing: 20) {
                    SegmentedPill(
                        selection: $section,
                        options: PlanSection.allCases.map { ($0, $0.title) }
                    )
                    .padding(.top, 6)

                    let items = snapshot.items(for: section)

                    if items.isEmpty {
                        empty
                    } else if section == .content {
                        // Content is a schedule, not a list, so it gets the
                        // month view its reference calls for.
                        ContentCalendar(
                            items: items,
                            month: .now,
                            onAdvance: onAdvance,
                            onDelete: onDelete
                        )
                    } else {
                        ForEach(items) { item in
                            SolidCard {
                                row(for: item)
                            }
                        }
                    }

                    Button {
                        onAdd()
                    } label: {
                        Label(section.addPrompt, systemImage: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(LifeOSTokens.primaryText.resolve(.light))
                            .padding(.vertical, 13)
                            .frame(maxWidth: .infinity)
                            .background(Capsule().fill(LifeOSTokens.tileSurface.resolve(.light)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 130)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: section)
    }

    @ViewBuilder
    private func row(for item: PlanItemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .font(.system(size: 16, weight: .semibold))
                    .strikethrough(item.status == .done, color: .secondary)
                Spacer()
                statusChip(item)
            }

            if let detail = item.detail {
                Text(detail).font(.system(size: 13)).opacity(0.6)
            }

            switch section {
            case .goals:
                if let fraction = item.fraction {
                    ProgressView(value: fraction)
                        .tint(fraction >= 1 ? LifeOSTokens.accent : LifeOSTokens.primaryText.resolve(.light))
                    HStack {
                        Text(milestoneLabel(item)).font(.system(size: 12)).opacity(0.55)
                        Spacer()
                        Button("Advance") { onAdvance(item.id) }
                            .font(.system(size: 13, weight: .semibold))
                            .tint(LifeOSTokens.accent)
                    }
                }

            case .habits:
                HStack(spacing: 10) {
                    // Same dot vocabulary as the Today grid: a habit's history
                    // reads exactly like a month of days on target.
                    DotGrid(cells: habitCells(item), dotSize: 12, spacing: 4)
                        .frame(maxWidth: 220)
                    Spacer()
                    Button {
                        onToggleHabit(item.id)
                    } label: {
                        Image(systemName: item.recentTicks.last == true ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 26))
                            .foregroundStyle(item.recentTicks.last == true
                                             ? LifeOSTokens.accent
                                             : LifeOSTokens.secondaryText.resolve(.light))
                    }
                    .accessibilityLabel(item.recentTicks.last == true ? "Mark not done" : "Mark done")
                }

            case .notes, .content:
                if let due = item.dueDate {
                    Text(due.formatted(.dateTime.month().day()))
                        .font(.system(size: 12, weight: .medium))
                        .opacity(0.55)
                }
            }
        }
        .contextMenu {
            Button("Delete", role: .destructive) { onDelete(item.id) }
        }
    }

    @ViewBuilder
    private func statusChip(_ item: PlanItemSnapshot) -> some View {
        if section == .habits {
            Text("\(snapshot.streaks[item.id] ?? 0) day streak")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LifeOSTokens.accent)
        } else {
            Text(item.status.title)
                .font(.system(size: 11, weight: .semibold))
                .opacity(0.6)
        }
    }

    /// Habit history reuses `DotCell`, so the dot grid needs no habit-specific code.
    private func habitCells(_ item: PlanItemSnapshot) -> [DotCell] {
        item.recentTicks.enumerated().map { index, done in
            DotCell(id: index, date: nil, state: done ? .onTarget : .missed)
        }
    }

    private func milestoneLabel(_ item: PlanItemSnapshot) -> String {
        guard let value = item.progressValue, let target = item.progressTarget else { return "" }
        return target > 100
            ? "\(Int(value).formatted()) / \(Int(target).formatted())"
            : "\(Int(value)) of \(Int(target)) milestones"
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Text("Nothing here yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LifeOSTokens.onGradient)
            Text("Add your first \(section.title.lowercased().dropLast(section.title.hasSuffix("s") ? 1 : 0))")
                .font(.system(size: 13))
                .foregroundStyle(LifeOSTokens.onGradient.opacity(0.75))
        }
        .padding(.vertical, 50)
    }
}

#Preview {
    @Previewable @State var section = PlanSection.goals
    PlanScreen(
        snapshot: PlanSnapshot(
            goals: [
                PlanItemSnapshot(id: UUID(), kind: .goal, title: "Ship the first release",
                                 status: .inProgress, progressValue: 3, progressTarget: 4),
                PlanItemSnapshot(id: UUID(), kind: .goal, title: "Achieve $10k savings",
                                 detail: "Deadline soon", status: .inProgress,
                                 progressValue: 6_000, progressTarget: 10_000),
            ]
        ),
        section: $section
    )
}

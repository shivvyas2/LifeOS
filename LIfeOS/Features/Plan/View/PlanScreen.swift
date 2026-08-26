import SwiftUI
import DesignSystem
import Persistence

struct PlanScreen: View {
    let snapshot: PlanSnapshot
    @Binding var section: PlanSection
    /// False when the screen is showing one section on purpose, which is how
    /// the notes tab hosts habits. Goals, notes and content are pages now;
    /// habits are not, because a habit is a daily tick with a streak behind it
    /// and Today toggles those same ticks live.
    var showsSections = true

    var onAdd: () -> Void = {}
    var onAdvance: (UUID) -> Void = { _ in }
    var onToggleHabit: (UUID) -> Void = { _ in }
    var onDelete: (UUID) -> Void = { _ in }
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout

    var body: some View {
        GradientCanvas(hue: section.hue) {
            ScrollView {
                VStack(spacing: 20) {
                    if showsSections {
                        SegmentedPill(
                            selection: $section,
                            options: PlanSection.allCases.map { ($0, $0.title) }
                        )
                        .padding(.top, 6)
                    }

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
                            SoftCard {
                                row(for: item)
                            }
                        }
                    }

                    Button {
                        onAdd()
                    } label: {
                        Label(section.addPrompt, systemImage: "plus")
                            .font(LifeOSType.rowTitle)
                            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                            .padding(.vertical, 13)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule()
                                    .fill(LifeOSTokens.tileSurface.resolve(scheme))
                                    .shadow(color: scheme == .dark ? .clear : LifeOSTokens.cardShadow, radius: 8, y: 2)
                            )
                    }
                }
                .frame(maxWidth: layout.maxContentWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, layout.gutter)
                .padding(.leading, layout.railInset)
                .padding(.bottom, layout.contentBottomInset)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: section)
    }

    @ViewBuilder
    private func row(for item: PlanItemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .font(LifeOSType.rowTitle)
                    .strikethrough(item.status == .done, color: .secondary)
                Spacer()
                statusChip(item)
            }

            if let detail = item.detail {
                Text(detail).font(LifeOSType.label.weight(.regular)).opacity(0.6)
            }

            switch section {
            case .goals:
                if let fraction = item.fraction {
                    ProgressView(value: fraction)
                        .tint(fraction >= 1 ? LifeOSTokens.accent : LifeOSTokens.primaryText.resolve(scheme))
                    HStack {
                        Text(milestoneLabel(item)).font(LifeOSType.caption).opacity(0.55)
                        Spacer()
                        Button("Advance") { onAdvance(item.id) }
                            .font(LifeOSType.label.weight(.semibold))
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
                            .font(LifeOSType.screenTitle.weight(.regular))
                            .foregroundStyle(item.recentTicks.last == true
                                             ? LifeOSTokens.accent
                                             : LifeOSTokens.secondaryText.resolve(scheme))
                    }
                    .accessibilityLabel(item.recentTicks.last == true ? "Mark not done" : "Mark done")
                }

            case .notes, .content:
                if let due = item.dueDate {
                    Text(due.formatted(.dateTime.month().day()))
                        .font(LifeOSType.caption.weight(.medium))
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
                .font(LifeOSType.caption.weight(.semibold))
                .foregroundStyle(LifeOSTokens.accent)
        } else {
            Text(item.status.title)
                .font(LifeOSType.eyebrow)
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
                .font(LifeOSType.body.weight(.semibold))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            Text("Add your first \(section.title.lowercased().dropLast(section.title.hasSuffix("s") ? 1 : 0))")
                .font(LifeOSType.label.weight(.regular))
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
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

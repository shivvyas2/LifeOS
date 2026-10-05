import SwiftUI
import DesignSystem
import Persistence

/// One day in full: what the metrics said, and which habits were done.
///
/// Past days are history and render as static marks. Only today gets controls,
/// so the grid can never be rewritten after the fact.
struct DayDetailSheet: View {
    let snapshot: DayDetailSnapshot
    let onToggleHabit: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x3) {
                    EditorialMasthead(
                        eyebrow: snapshot.isToday ? "Today" : "Day",
                        title: snapshot.date.formatted(.dateTime.weekday(.wide).month(.wide).day()),
                        detail: habitsLine
                    )
                    ForEach(Array(sections.enumerated()), id: \.element) { offset, section in
                        VStack(alignment: .leading, spacing: Space.x2) {
                            EditorialSectionHeader(index: offset + 1, title: section.title)
                            content(section)
                        }
                    }
                }
                .padding(.horizontal, Space.x3)
                .padding(.top, Space.x2)
                .padding(.bottom, Space.x5)
            }
            .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private enum Section: Hashable {
        case schedule, readings, habits
        var title: String {
            switch self {
            case .schedule: "Schedule"
            case .readings: "Readings"
            case .habits: "Habits"
            }
        }
    }

    private var sections: [Section] {
        var list: [Section] = []
        if !snapshot.events.isEmpty { list.append(.schedule) }
        list.append(.readings)
        list.append(.habits)
        return list
    }

    private var habitsLine: String? {
        guard !snapshot.habits.isEmpty else { return nil }
        let done = snapshot.habits.filter(\.isDone).count
        return "\(done) of \(snapshot.habits.count) \(snapshot.habits.count == 1 ? "habit" : "habits")"
    }

    @ViewBuilder
    private func content(_ section: Section) -> some View {
        switch section {
        case .schedule:
            ForEach(snapshot.events) { event in
                EditorialRow(event.timeLabel, value: event.title)
            }
        case .readings:
            EditorialRow("Steps", value: snapshot.steps.map { "\($0.formatted()) of \(snapshot.stepsTarget.formatted())" } ?? "—")
            EditorialRow("Sleep", value: snapshot.sleepMinutes.map { "\(TodayScreen.duration($0)) of \(TodayScreen.duration(snapshot.sleepTargetMinutes))" } ?? "—")
            EditorialRow("Weight", value: snapshot.weightKg.map { String(format: "%.1f kg", $0) } ?? "—")
            EditorialRow("Recovery", value: snapshot.recoveryPct.map { "\(Int($0))%" } ?? "—")
        case .habits:
            if snapshot.habits.isEmpty {
                Text("No habits yet. Add one on the Notes tab.")
                    .font(LifeOSType.secondary)
                    .foregroundStyle(Editorial.quietInk(scheme))
            } else {
                ForEach(snapshot.habits) { habit in
                    habitRow(habit)
                }
            }
        }
    }

    @ViewBuilder
    private func habitRow(_ habit: HabitRow) -> some View {
        if snapshot.isToday {
            Button { onToggleHabit(habit.id) } label: { habitLabel(habit) }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    habit.isDone
                        ? "\(habit.title), done. Mark not done"
                        : "\(habit.title), not done. Mark done"
                )
        } else {
            habitLabel(habit)
                .accessibilityLabel("\(habit.title), \(habit.isDone ? "done" : "not done")")
        }
    }

    private func habitLabel(_ habit: HabitRow) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.x2) {
                Image(systemName: habit.isDone ? "checkmark.square.fill" : "square")
                    .font(LifeOSType.rowTitle)
                    .foregroundStyle(habit.isDone ? LifeOSTokens.primaryText.resolve(scheme) : Editorial.quietInk(scheme))
                Text(habit.title)
                    .font(LifeOSType.secondary)
                    .strikethrough(habit.isDone)
                    .foregroundStyle(habit.isDone ? Editorial.quietInk(scheme) : LifeOSTokens.primaryText.resolve(scheme))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            Hairline()
        }
        .contentShape(.rect)
    }
}

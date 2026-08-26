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
                VStack(alignment: .leading, spacing: 22) {
                    if !snapshot.events.isEmpty {
                        schedule
                    }
                    metrics
                    habits
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
            .navigationTitle(snapshot.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Schedule")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))

            SoftCard {
                VStack(spacing: 0) {
                    ForEach(Array(snapshot.events.enumerated()), id: \.element.id) { index, event in
                        if index > 0 { Divider() }
                        scheduleRow(event)
                    }
                }
            }
        }
    }

    private func scheduleRow(_ event: CalendarEventSnapshot) -> some View {
        HStack(spacing: 12) {
            Text(event.timeLabel)
                .font(.system(size: 14))
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                .frame(width: 56, alignment: .leading)

            Text(event.title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .lineLimit(1)

            Spacer()

            Text(event.durationLabel)
                .font(.system(size: 13))
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
        }
        .padding(.vertical, 12)
    }

    private var metrics: some View {
        SoftCard {
            VStack(spacing: 0) {
                MetricRow(
                    label: "Steps",
                    value: snapshot.steps.map { $0.formatted() },
                    detail: "of \(snapshot.stepsTarget.formatted())"
                )
                Divider()
                MetricRow(
                    label: "Sleep",
                    value: snapshot.sleepMinutes.map(TodayScreen.duration),
                    detail: "of \(TodayScreen.duration(snapshot.sleepTargetMinutes))"
                )
                Divider()
                MetricRow(
                    label: "Weight",
                    value: snapshot.weightKg.map { String(format: "%.1f kg", $0) }
                )
                Divider()
                MetricRow(
                    label: "Recovery",
                    value: snapshot.recoveryPct.map { "\(Int($0))%" }
                )
            }
        }
    }

    private var habits: some View {
        VStack(alignment: .leading, spacing: 10) {
            if snapshot.habits.isEmpty {
                Text("No habits yet. Add one on the Plan tab.")
                    .font(.system(size: 15))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            } else {
                // A bare count, never a percentage or a grade. This list
                // includes habits that may not have existed on an older day,
                // so it must not read as a verdict on that day. Suppressed
                // entirely above when there are no habits — "0 of 0 habits"
                // is noise above "No habits yet."
                Text("\(snapshot.habits.filter(\.isDone).count) of \(snapshot.habits.count) \(snapshot.habits.count == 1 ? "habit" : "habits")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))

                SoftCard {
                    VStack(spacing: 0) {
                        ForEach(Array(snapshot.habits.enumerated()), id: \.element.id) { index, habit in
                            if index > 0 { Divider() }
                            habitRow(habit)
                        }
                    }
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
        HStack(spacing: 12) {
            Image(systemName: icon(for: habit))
                .font(.system(size: snapshot.isToday ? 22 : 16, weight: .semibold))
                .foregroundStyle(
                    habit.isDone
                        ? LifeOSTokens.accent
                        : LifeOSTokens.secondaryText.resolve(scheme)
                )
                .frame(width: 24)

            Text(habit.title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))

            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 12)
    }

    /// Today gets the tappable circle vocabulary used on the Plan tab. A past
    /// day gets a plain mark, because there is nothing there to press.
    ///
    /// Not-done on a past day is a dash, not an `xmark`. This list includes
    /// habits that may not have existed on that date (see `DayDetailSnapshot`),
    /// so a ✗ once per row would read as a verdict the sheet does not have the
    /// standing to make. A dash says "not done" without asserting failure.
    private func icon(for habit: HabitRow) -> String {
        if snapshot.isToday {
            habit.isDone ? "checkmark.circle.fill" : "circle"
        } else {
            habit.isDone ? "checkmark" : "minus"
        }
    }
}

/// One metric line. A missing value renders as an em dash rather than hiding the
/// row, so the sheet's height does not jump as you move between days.
private struct MetricRow: View {
    let label: String
    let value: String?
    var detail: String? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))

            Spacer()

            Text(value ?? "—")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))

            // The target is context for a number. With no number it is noise.
            if let detail, value != nil {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
        }
        .padding(.vertical, 12)
    }
}

private let previewHabits = [
    HabitRow(id: UUID(), title: "Read 20 min", isDone: true),
    HabitRow(id: UUID(), title: "Gym", isDone: true),
    HabitRow(id: UUID(), title: "Water 2.5L", isDone: false),
    HabitRow(id: UUID(), title: "Journal", isDone: false),
]

#Preview("Today") {
    DayDetailSheet(
        snapshot: DayDetailSnapshot(
            date: Calendar.current.startOfDay(for: .now),
            isToday: true,
            steps: 3102, stepsTarget: 8000,
            sleepMinutes: 440, sleepTargetMinutes: 420,
            weightKg: 77.4, recoveryPct: 62,
            habits: previewHabits
        ),
        onToggleHabit: { _ in }
    )
}

#Preview("Past day, partial data") {
    DayDetailSheet(
        snapshot: DayDetailSnapshot(
            date: Calendar.current.date(byAdding: .day, value: -7, to: .now)!,
            isToday: false,
            steps: 6204, stepsTarget: 8000,
            sleepMinutes: nil, sleepTargetMinutes: 420,
            weightKg: nil, recoveryPct: nil,
            habits: previewHabits
        ),
        onToggleHabit: { _ in }
    )
}

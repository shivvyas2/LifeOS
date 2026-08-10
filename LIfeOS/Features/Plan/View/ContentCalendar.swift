import SwiftUI
import DesignSystem
import Persistence

/// The content planner's month view: a day grid with a marker on any day that
/// has something scheduled, and the entries listed beneath grouped by status.
///
/// Reuses `MonthGridLayout` for the calendar arithmetic rather than repeating
/// it — the leading-blank and month-boundary maths is already tested.
struct ContentCalendar: View {
    let items: [PlanItemSnapshot]
    let month: Date
    var onAdvance: (UUID) -> Void = { _ in }
    var onDelete: (UUID) -> Void = { _ in }

    private let calendar = Calendar.current

    /// Day → the statuses scheduled on it, built once per render.
    private var byDay: [Date: [PlanStatus]] {
        var map: [Date: [PlanStatus]] = [:]
        for item in items {
            guard let due = item.dueDate else { continue }
            map[calendar.startOfDay(for: due), default: []].append(item.status)
        }
        return map
    }

    var body: some View {
        let marks = byDay

        VStack(spacing: 16) {
            SolidCard {
                VStack(spacing: 12) {
                    HStack {
                        Text(month.formatted(.dateTime.month(.wide).year()))
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                    }

                    WeekdayHeader(calendar: calendar, today: .now, spacing: 4)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                              spacing: 6) {
                        ForEach(cells, id: \.id) { cell in
                            dayCell(cell, marks: marks)
                        }
                    }
                }
            }

            ForEach(groups, id: \.status) { group in
                SolidCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Self.color(for: group.status))
                                .frame(width: 8, height: 8)
                            Text(group.status.title.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.6)
                                .opacity(0.55)
                        }
                        ForEach(group.items) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.system(size: 15, weight: .medium))
                                    if let due = item.dueDate {
                                        Text(due.formatted(.dateTime.month().day()))
                                            .font(.system(size: 12)).opacity(0.5)
                                    }
                                }
                                Spacer()
                                Button("Advance") { onAdvance(item.id) }
                                    .font(.system(size: 13, weight: .semibold))
                                    .tint(LifeOSTokens.accent)
                            }
                            .contextMenu {
                                Button("Delete", role: .destructive) { onDelete(item.id) }
                            }
                        }
                    }
                }
            }
        }
    }

    private var cells: [DotCell] {
        MonthGridLayout.cells(
            monthContaining: month,
            calendar: calendar,
            today: .now,
            status: { _ in .noData }
        )
    }

    @ViewBuilder
    private func dayCell(_ cell: DotCell, marks: [Date: [PlanStatus]]) -> some View {
        if let date = cell.date {
            let statuses = marks[calendar.startOfDay(for: date)] ?? []
            VStack(spacing: 3) {
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: 12, weight: calendar.isDateInToday(date) ? .bold : .regular))
                    .foregroundStyle(calendar.isDateInToday(date) ? LifeOSTokens.accent : .primary)
                HStack(spacing: 2) {
                    ForEach(Array(statuses.prefix(3).enumerated()), id: \.offset) { _, status in
                        Circle().fill(Self.color(for: status)).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(height: 32)
        } else {
            Color.clear.frame(height: 32)
        }
    }

    private var groups: [(status: PlanStatus, items: [PlanItemSnapshot])] {
        let order: [PlanStatus] = [.todo, .inProgress, .scheduled, .done, .blocked]
        return order.compactMap { status in
            let matching = items.filter { $0.status == status }
            return matching.isEmpty ? nil : (status, matching)
        }
    }

    /// Content statuses read as a pipeline, so they get distinct colours rather
    /// than the single accent — this is the one place the app shows several.
    static func color(for status: PlanStatus) -> Color {
        switch status {
        case .todo:       Color(red: 0.23, green: 0.51, blue: 0.93)
        case .inProgress: LifeOSTokens.accent
        case .scheduled:  Color(red: 0.18, green: 0.62, blue: 0.36)
        case .done:       Color(white: 0.55)
        case .blocked:    Color(red: 0.85, green: 0.22, blue: 0.22)
        }
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [ModuleHue.recovery.top, ModuleHue.recovery.bottom],
                       startPoint: .top, endPoint: .bottom)
        ScrollView {
            ContentCalendar(
                items: [
                    PlanItemSnapshot(id: UUID(), kind: .content, title: "Blog post draft",
                                     status: .inProgress, dueDate: .now),
                    PlanItemSnapshot(id: UUID(), kind: .content, title: "Newsletter",
                                     status: .scheduled,
                                     dueDate: .now.addingTimeInterval(3 * 86_400)),
                ],
                month: .now
            )
            .padding()
        }
    }
    .ignoresSafeArea()
}

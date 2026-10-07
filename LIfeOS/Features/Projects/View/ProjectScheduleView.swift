import SwiftUI
import DesignSystem
import Persistence

/// A week strip, then the chosen day's hours with time-blocked tasks laid
/// side by side where they overlap. A tap on an empty hour starts a task there.
struct ProjectScheduleView: View {
    let tasks: [ProjectTaskSnapshot]
    let colour: ProjectColour
    let name: (UUID?) -> String
    var onOpen: (UUID) -> Void
    var onCreateAt: (Date) -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var day = Calendar.current.startOfDay(for: .now)
    private let calendar = Calendar.current
    private let hourHeight: CGFloat = 56
    private let firstHour = 7, lastHour = 22

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            weekStrip
            timeline
        }
    }

    private var weekStrip: some View {
        let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
        let ink = LifeOSTokens.primaryText.resolve(scheme)
        return HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { offset in
                let date = calendar.date(byAdding: .day, value: offset, to: start) ?? start
                let selected = calendar.isDate(date, inSameDayAs: day)
                Button { day = date } label: {
                    VStack(spacing: 2) {
                        Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased()).font(LifeOSType.caption.weight(.heavy))
                        Text(date.formatted(.dateTime.day())).font(LifeOSType.rowTitle.weight(.black))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, Space.x1)
                    .foregroundStyle(selected ? LifeOSTokens.canvas.resolve(scheme) : ink)
                    .background(selected ? ink : calendar.isDateInToday(date) ? colour.ramp(level: 1).resolve(scheme) : .clear)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .overlay(Rectangle().strokeBorder(ink, lineWidth: 2))
    }

    private var timeline: some View {
        let blocks = tasks.compactMap { task -> (ProjectTaskSnapshot, TimeBlock)? in
            guard let start = task.startsAt, calendar.isDate(start, inSameDayAs: day) else { return nil }
            return (task, TimeBlock(id: task.id, start: start, end: task.endsAt ?? start.addingTimeInterval(3_600)))
        }
        let lanes = ScheduleLayout.lanes(blocks.map(\.1))
        let ink = LifeOSTokens.primaryText.resolve(scheme)
        return GeometryReader { proxy in
            let gutter: CGFloat = 52
            let width = proxy.size.width - gutter
            ZStack(alignment: .topLeading) {
                ForEach(firstHour...lastHour, id: \.self) { hour in
                    let y = CGFloat(hour - firstHour) * hourHeight
                    HStack(spacing: 0) {
                        Text(hourLabel(hour)).font(LifeOSType.caption.weight(.heavy)).frame(width: gutter, alignment: .leading)
                        Rectangle().fill(ink.opacity(0.15)).frame(height: 1)
                    }
                    .offset(y: y)
                    Color.clear.contentShape(.rect)
                        .frame(width: width, height: hourHeight)
                        .offset(x: gutter, y: y)
                        .onTapGesture {
                            if let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) { onCreateAt(start) }
                        }
                        .accessibilityLabel("Add a task at \(hourLabel(hour))")
                        .accessibilityAddTraits(.isButton)
                }
                ForEach(blocks, id: \.0.id) { task, block in
                    let place = lanes[block.id] ?? (0, 1)
                    let laneWidth = width / CGFloat(max(place.lanes, 1))
                    let top = offset(block.start)
                    let height = max(offset(block.end) - top, 28)
                    Button { onOpen(task.id) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title).font(LifeOSType.caption.weight(.heavy)).lineLimit(2)
                            StatusChip(status: task.status, colour: colour)
                            if !task.notes.isEmpty {
                                Text(task.notes).font(LifeOSType.caption).lineLimit(1)
                            }
                            if task.ownerID != nil { MemberAvatars(names: [name(task.ownerID)], limit: 1) }
                        }
                        .padding(6)
                        .frame(width: laneWidth - 4, height: height, alignment: .topLeading)
                        .background(colour.ramp(level: 1).resolve(scheme))
                        .overlay(alignment: .leading) { Rectangle().fill(colour.fill.resolve(scheme)).frame(width: 5) }
                        .overlay(Rectangle().strokeBorder(ink, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .offset(x: gutter + CGFloat(place.lane) * laneWidth, y: top)
                    .accessibilityIdentifier("schedule.block.\(task.title)")
                }
            }
        }
        .frame(height: CGFloat(lastHour - firstHour + 1) * hourHeight)
    }

    private func offset(_ date: Date) -> CGFloat {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hours = Double((parts.hour ?? firstHour) - firstHour) + Double(parts.minute ?? 0) / 60
        return CGFloat(max(hours, 0)) * hourHeight
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        return date.formatted(.dateTime.hour())
    }
}

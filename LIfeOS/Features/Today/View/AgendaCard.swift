import SwiftUI
import UIKit
import DesignSystem
import Persistence

/// Shared by `AgendaCard` and `DayDetailSheet`'s schedule section, so both
/// render one event the same way.
extension CalendarEventSnapshot {
    var timeLabel: String {
        isAllDay ? "all day" : startDate.formatted(.dateTime.hour().minute())
    }

    /// "45m", "1h", "1h 30m", or "" for an all-day event. Divides by 60 the
    /// same way `TodayScreen.duration` does, but drops a leading "0h" that
    /// would otherwise clutter every event under an hour. Empty rather than
    /// "all day" because the time slot already says that; a row must omit
    /// this label entirely, not render it a second time.
    var durationLabel: String {
        guard !isAllDay else { return "" }
        let minutes = max(0, Int(endDate.timeIntervalSince(startDate) / 60))
        let hours = minutes / 60
        let mins = minutes % 60
        if hours == 0 { return "\(mins)m" }
        if mins == 0 { return "\(hours)h" }
        return "\(hours)h \(mins)m"
    }
}

/// Today's schedule, plus what's coming after it. Two `SoftCard`s: the
/// agenda always renders (it carries the permission states), Upcoming only
/// when there is something to show and access is granted.
///
/// A pure function of the snapshot, like every other Today subview: the
/// EventKit prompt itself lives behind `onConnect`, never fired from here.
struct AgendaCard: View {
    let access: CalendarAccessState
    let agenda: [CalendarEventSnapshot]
    let upcoming: [UpcomingEvent]
    let onConnect: () -> Void
    let onAddEvent: () -> Void
    let onTapEvent: (CalendarEventSnapshot) -> Void
    let onOpenToday: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    private static let maxAgendaRows = 4
    private static let maxUpcomingRows = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SoftCard {
                VStack(alignment: .leading, spacing: 4) {
                    header
                    body(for: access)
                }
            }

            if access == .authorized, !upcoming.isEmpty {
                SoftCard {
                    VStack(alignment: .leading, spacing: 4) {
                        sectionHeader("UPCOMING")
                        upcomingRows
                    }
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            sectionHeader("TODAY")
            Spacer()
            if access == .authorized, !agenda.isEmpty {
                Text(agenda.count == 1 ? "1 event" : "\(agenda.count) events")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
        }
        .padding(.bottom, 4)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
    }

    // MARK: Agenda body, by access state

    @ViewBuilder
    private func body(for access: CalendarAccessState) -> some View {
        switch access {
        case .notDetermined:
            VStack(alignment: .leading, spacing: 12) {
                Text("See your day's schedule here.")
                    .font(.system(size: 15))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                Button("Connect calendar", action: onConnect)
                    .buttonStyle(.borderedProminent)
                    .tint(LifeOSTokens.accent)
            }
            .padding(.vertical, 4)

        case .denied:
            VStack(alignment: .leading, spacing: 12) {
                Text("Calendar access is off.")
                    .font(.system(size: 15))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(LifeOSTokens.accent)
            }
            .padding(.vertical, 4)

        case .authorized:
            VStack(alignment: .leading, spacing: 0) {
                if agenda.isEmpty {
                    Text("Nothing scheduled today.")
                        .font(.system(size: 15))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(agenda.prefix(Self.maxAgendaRows).enumerated()), id: \.element.id) { index, event in
                        if index > 0 { Divider() }
                        agendaRow(event)
                    }

                    if agenda.count > Self.maxAgendaRows {
                        Divider()
                        Button {
                            onOpenToday()
                        } label: {
                            Text("+\(agenda.count - Self.maxAgendaRows) more")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("+ Add event", action: onAddEvent)
                    .buttonStyle(.plain)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LifeOSTokens.accent)
                    .padding(.top, 8)
            }
        }
    }

    private func agendaRow(_ event: CalendarEventSnapshot) -> some View {
        Button {
            onTapEvent(event)
        } label: {
            eventRow(time: event.timeLabel, title: event.title, duration: event.durationLabel)
        }
        .buttonStyle(.plain)
    }

    // MARK: Upcoming

    private var upcomingRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(upcoming.prefix(Self.maxUpcomingRows).enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider() }
                Button {
                    onTapEvent(row.event)
                } label: {
                    HStack(spacing: 8) {
                        Text(row.dayLabel)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                            .frame(width: 64, alignment: .leading)

                        Text(row.event.timeLabel)
                            .font(.system(size: 13))
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                            .frame(width: 56, alignment: .leading)

                        Text(row.event.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                            .lineLimit(1)

                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }

            if upcoming.count > Self.maxUpcomingRows {
                Text("+\(upcoming.count - Self.maxUpcomingRows) more")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    .padding(.top, 8)
            }
        }
    }

    // MARK: Row building blocks

    private func eventRow(time: String, title: String, duration: String) -> some View {
        HStack(spacing: 12) {
            Text(time)
                .font(.system(size: 14))
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                .frame(width: 56, alignment: .leading)

            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .lineLimit(1)

            Spacer()

            if !duration.isEmpty {
                Text(duration)
                    .font(.system(size: 13))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 10)
    }
}

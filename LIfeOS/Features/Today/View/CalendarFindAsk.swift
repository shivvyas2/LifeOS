import SwiftUI
import DesignSystem
import Insights
import Persistence

/// The block under the field while a query is live: an eyebrow with the
/// count, one quiet sentence naming the months the find covers, then up to
/// eight rows and a `4 more` line. A row tap shows the event's week.
struct ScheduleResultsBlock: View {
    let results: [CalendarEventSnapshot]
    let months: [Date]
    var onSelect: (CalendarEventSnapshot) -> Void
    @Environment(\.colorScheme) private var scheme
    private let calendar = Calendar.current
    private static let limit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(ScheduleFindText.eyebrow(found: results.count)).editorialEyebrow()
            Text(ScheduleFindText.scope(months: months, calendar: calendar))
                .font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
                .fixedSize(horizontal: false, vertical: true)
            if !results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(results.prefix(Self.limit)) { event in
                        ScheduleResultRow(event: event) { onSelect(event) }
                    }
                }
                .padding(.top, Space.x1)
                if results.count > Self.limit {
                    Text(ScheduleFindText.more(results.count - Self.limit))
                        .font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
                        .padding(.top, Space.x1)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// One found event: `Tue 13 · 10:00` in quiet ink, the title in ink, an
/// arrow, a hairline underneath. The same row the week bands draw, so a
/// result and a band entry read as the same thing.
struct ScheduleResultRow: View {
    let event: CalendarEventSnapshot
    var action: () -> Void

    private var label: String {
        ScheduleFindText.rowLabel(start: event.startDate, isAllDay: event.isAllDay)
    }

    var body: some View {
        Button(action: action) {
            EditorialRow(label) {
                HStack(spacing: Space.half) {
                    Text(event.title).lineLimit(2)
                    Image(systemName: "arrow.right").font(LifeOSType.caption.weight(.semibold))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(event.title), \(label)")
        .accessibilityHint("Shows its week")
    }
}

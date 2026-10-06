import SwiftUI
import DesignSystem
import Persistence

/// One event as a row: `time · title · arrow.right`, with a 6pt accent dot
/// before the time when a find has matched it. The bands and the day
/// screen draw this, so an event reads the same in both.
struct AgendaRow: View {
    let event: CalendarEventSnapshot
    var highlighted = false
    var lineLimit = 2
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: Space.half) {
                if highlighted {
                    Circle().fill(LifeOSTokens.accent).frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                EditorialRow(event.timeLabel) {
                    HStack(spacing: Space.half) {
                        Text(event.title).lineLimit(lineLimit)
                        Image(systemName: "arrow.right").font(LifeOSType.caption.weight(.semibold))
                    }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(event.title), \(event.spanLabel)")
        .accessibilityHint("Opens the event")
    }
}

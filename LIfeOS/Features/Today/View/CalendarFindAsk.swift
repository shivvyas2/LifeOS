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

/// One question asked from the calendar: the words, and once the assistant
/// has answered, the id of its reply in the shared conversation.
struct CalendarAsk: Equatable {
    let question: String
    var replyID: UUID?
}

/// The reply, on the calendar: the question as a quiet line, `Thinking…`
/// until the answer lands, the answer, the events it was about as the same
/// rows the find draws, what the tools did as tags, any write awaiting a
/// yes, and `Clear`. The conversation itself stays in the assistant sheet.
struct AssistantReplyCard: View {
    let ask: CalendarAsk
    let assistant: AssistantViewModel
    var onSelect: (CalendarEventSnapshot) -> Void
    var onClear: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var reply: ChatMessageSnapshot? {
        guard let id = ask.replyID else { return nil }
        return assistant.messages.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text("Assistant").editorialEyebrow()
            Text(ask.question)
                .font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
                .fixedSize(horizontal: false, vertical: true)
            if reply == nil, assistant.isThinking, assistant.pending.isEmpty {
                ChatThinking()
            }
            if let reply {
                Text(reply.text)
                    .font(LifeOSType.secondary)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                if let events = assistant.eventsByMessage[reply.id], !events.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(events) { event in
                            ScheduleResultRow(event: event) { onSelect(event) }
                        }
                    }
                }
                if !reply.toolSummaries.isEmpty {
                    ChatToolTags(reply.toolSummaries)
                }
            }
            ForEach(assistant.pending) { write in
                ChatConfirmation(lines: write.preview, framed: false,
                                 onConfirm: { assistant.confirm(write.id) },
                                 onCancel: { assistant.cancel(write.id) })
            }
            Button("Clear", action: onClear)
                .buttonStyle(.editorial(.quiet, size: .compact))
                .accessibilityHint("Hides the reply; the conversation stays in the assistant")
        }
        .editorialCard()
    }
}

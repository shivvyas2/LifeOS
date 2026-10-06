#if DEBUG
import SwiftUI
import SwiftData
import DesignSystem
import Insights
import Persistence

/// Fixture pages for the calendar assistant, mounted by `--design-preview`
/// with `--page=assistant` (a conversation with an agenda card and tool
/// tags), `assistant-confirm` (one question with its pending confirmation
/// card) or `assistant-empty` (the opening; add `--connected` for the prompt
/// rows instead of the connect button).
struct AssistantDesignPreview: View {
    let page: String
    @State private var fixture = AssistantFixture()

    var body: some View {
        Color.clear
            .fullScreenCover(isPresented: .constant(true)) {
                AssistantSheet(model: model)
            }
            .modelContainer(fixture.container)
    }

    private var model: AssistantViewModel {
        switch page {
        case "assistant-empty": fixture.empty
        case "assistant-confirm": fixture.confirm
        default: fixture.full
        }
    }
}

@MainActor private final class AssistantFixture {
    let container = try! LifeOSContainer.make(inMemory: true)
    /// Its own store, or the empty model would load the conversation the
    /// full one seeded under the shared conversation id.
    let emptyContainer = try! LifeOSContainer.make(inMemory: true)
    let confirmContainer = try! LifeOSContainer.make(inMemory: true)
    let full: AssistantViewModel
    let confirm: AssistantViewModel
    let empty: AssistantViewModel

    init() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func at(_ dayOffset: Int, _ hour: Int, _ minutes: Int, _ title: String) -> CalendarEventSnapshot {
            let start = calendar.date(byAdding: .hour, value: hour, to: calendar.date(byAdding: .day, value: dayOffset, to: today)!)!
            return CalendarEventSnapshot(id: UUID(), source: .eventKit, sourceID: title, calendarTitle: "Work", title: title,
                                         startDate: start, endDate: start.addingTimeInterval(Double(minutes) * 60),
                                         isAllDay: false, isRecurring: false, location: nil, notes: nil)
        }
        let events = [at(0, 9, 30, "Standup"), at(0, 12, 60, "Lunch with Sam"), at(0, 16, 90, "Design review"), at(1, 10, 60, "Dentist")]
        let window = DateInterval(start: calendar.date(byAdding: .day, value: -7, to: today)!,
                                  end: calendar.date(byAdding: .day, value: 14, to: today)!)
        try! CalendarStore(context: container.mainContext, calendar: calendar).apply(events, window: window)

        full = AssistantViewModel(context: container.mainContext)
        full.previewAuthorized = true
        // The same conversation id the model will load, so the seeded turns
        // are the ones it shows.
        let id = UUID()
        UserDefaults.currentAccount.set(id.uuidString, forKey: "assistant.conversationID")
        let chat = ChatStore(context: container.mainContext)
        try! chat.append(conversationID: id, role: .user, text: "What's on my calendar today?")
        try! chat.append(conversationID: id, role: .assistant,
                         text: "Three things today: standup at 9, lunch with Sam at 12, and a design review at 4.",
                         toolSummaries: ["Checked your calendar"], eventIDs: events.prefix(3).map(\.id))

        // One question and the card it raised, short enough to fit a capture.
        confirm = AssistantViewModel(context: confirmContainer.mainContext)
        confirm.previewAuthorized = true
        try! ChatStore(context: confirmContainer.mainContext)
            .append(conversationID: id, role: .user, text: "Move the design review to 5.")
        confirm.previewSeed(pending: [PendingWrite(toolName: "update_event",
                                                   preview: ["Now: 16:00 to 17:30 | Design review",
                                                             "Becomes: Design review, 17:00 to 18:30"])])

        empty = AssistantViewModel(context: emptyContainer.mainContext)
        empty.previewAuthorized = ProcessInfo.processInfo.arguments.contains("--connected")
    }
}
#endif

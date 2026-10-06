#if DEBUG
import SwiftUI
import SwiftData
import DesignSystem
import Insights
import Persistence

/// Fixture pages for the calendar assistant, mounted by `--design-preview`
/// with `--page=assistant` (a conversation with an agenda card, tool tags
/// and a pending confirmation) or `assistant-empty` (the opening; add
/// `--connected` for the prompt rows instead of the connect button).
struct AssistantDesignPreview: View {
    let page: String
    @State private var fixture = AssistantFixture()

    var body: some View {
        Color.clear
            .sheet(isPresented: .constant(true)) {
                AssistantSheet(model: page == "assistant-empty" ? fixture.empty : fixture.full)
                    .interactiveDismissDisabled()
            }
            .modelContainer(fixture.container)
    }
}

@MainActor private final class AssistantFixture {
    let container = try! LifeOSContainer.make(inMemory: true)
    let full: AssistantViewModel
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
        try! chat.append(conversationID: id, role: .user, text: "Move the design review to 5.")
        full.previewSeed(pending: [PendingWrite(toolName: "update_event",
                                                preview: ["Now: 16:00 to 17:30 | Design review",
                                                          "Becomes: Design review, 17:00 to 18:30"])])

        empty = AssistantViewModel(context: container.mainContext)
        empty.previewAuthorized = ProcessInfo.processInfo.arguments.contains("--connected")
    }
}
#endif

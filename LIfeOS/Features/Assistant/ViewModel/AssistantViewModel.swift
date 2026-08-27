import Foundation
import FoundationModels
import SwiftData
import SwiftUI
import Assistant
import Insights
import Integrations
import Persistence

extension CalendarSync: CalendarWriting {}

/// Owns one conversation with the calendar assistant. The sheet is a pure
/// function of this state.
@Observable @MainActor
final class AssistantViewModel {
    private(set) var messages: [ChatMessageSnapshot] = []
    private(set) var pending: [PendingWrite] = []
    /// Events surfaced by each assistant turn, for the cards under its reply.
    ///
    /// Rebuilt from the calendar on every reload rather than kept from the
    /// turn that produced it, so a card shows the event as it is now. One that
    /// has since been deleted stops appearing, which is the correct thing for
    /// it to do.
    private(set) var eventsByMessage: [UUID: [CalendarEventSnapshot]] = [:]
    private(set) var isThinking = false
    private(set) var isAuthorized = false
    var draft = ""

    private let chat: ChatStore
    private let store: CalendarStore
    private let sync: CalendarSync
    private let eventKit: EventKitSource
    private var conversationID = UUID()
    private var broker = ConfirmationBroker()

    init(context: ModelContext) {
        self.chat = ChatStore(context: context)
        self.store = CalendarStore(context: context)
        self.eventKit = EventKitSource()
        self.sync = CalendarSync(sources: [eventKit], store: store)
    }

    var modelAvailable: Bool {
        ModelAvailability.from(SystemLanguageModel.default.availability) == .available
    }

    func appear() async {
        conversationID = (try? chat.latestConversationID()) ?? UUID()
        reloadMessages()
        isAuthorized = await eventKit.isAuthorized
        if isAuthorized { await sync.sync() }
    }

    func connectCalendar() async {
        let granted = (try? await eventKit.requestAccess()) ?? false
        isAuthorized = granted
        if granted { await sync.sync() }
    }

    /// The card leaves the screen the moment it is answered. The broker prunes
    /// its own copy on resolve; without this the view's copy lingered with
    /// live-looking buttons until the whole turn finished.
    func confirm(_ id: UUID) {
        pending.removeAll { $0.id == id }
        let broker = broker
        Task { await broker.confirm(id) }
    }

    func cancel(_ id: UUID) {
        pending.removeAll { $0.id == id }
        let broker = broker
        Task { await broker.cancel(id) }
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        draft = ""
        isThinking = true
        defer { isThinking = false; pending = [] }

        try? chat.append(conversationID: conversationID, role: .user, text: text)
        reloadMessages()

        let broker = ConfirmationBroker { [weak self] write in
            Task { @MainActor in self?.pending.append(write) }
        }
        self.broker = broker

        // One per turn, so the cards under a reply are the events that reply
        // was actually about rather than everything the conversation has ever
        // looked at.
        let collector = CalendarEventCollector()
        let tools: [any CoachTool] = isAuthorized
            ? CalendarAssistant.tools(reading: store, writing: sync, collector: collector)
            : []

        do {
            let reply = try await AssistantTurn.run(
                instructions: CalendarAssistant.instructions(authorized: isAuthorized),
                prompt: prompt(for: text),
                tools: tools,
                broker: broker
            )
            let events = await collector.collected()
            try? chat.append(
                conversationID: conversationID, role: .assistant,
                text: reply.text, toolSummaries: reply.toolSummaries,
                eventIDs: events.map(\.id)
            )
        } catch {
            try? chat.append(
                conversationID: conversationID, role: .assistant,
                text: "I couldn't answer that. Try again."
            )
        }
        reloadMessages()
    }

    private func prompt(for text: String) -> String {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: .now)
        let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: dayStart) ?? dayStart
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let today = (try? store.events(from: dayStart, to: tomorrowStart)) ?? []
        let tomorrow = (try? store.events(from: tomorrowStart, to: dayAfterTomorrow)) ?? []

        let history = ((try? chat.recent(conversationID: conversationID)) ?? [])
            .dropLast()  // the just-appended user message; it goes in as the question
            .map { "\($0.role == .user ? "User" : "Assistant"): \($0.text)" }
            .joined(separator: "\n")

        return """
        \(CalendarAssistant.contextPrefix(now: .now, timeZone: .current, today: today, tomorrow: tomorrow))

        \(history)

        User: \(text)
        """
    }

    private func reloadMessages() {
        messages = (try? chat.recent(conversationID: conversationID)) ?? []
        resolveEventCards()
    }

    /// Turns the ids stored on each reply back into events.
    ///
    /// One fetch across the whole conversation rather than one per message,
    /// and a dictionary lookup after: a transcript of twenty replies asking
    /// the calendar twenty times would be twenty round trips for what is one
    /// question.
    private func resolveEventCards() {
        let wanted = Set(messages.flatMap(\.eventIDs))
        guard !wanted.isEmpty else {
            eventsByMessage = [:]
            return
        }

        let found = (try? store.events(withIDs: wanted)) ?? []
        let byID = Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0) })

        var resolved: [UUID: [CalendarEventSnapshot]] = [:]
        for message in messages where !message.eventIDs.isEmpty {
            // compactMap, so an event deleted since the reply was written
            // simply drops out rather than leaving a card describing something
            // that no longer exists.
            let events = message.eventIDs.compactMap { byID[$0] }
            if !events.isEmpty {
                resolved[message.id] = events.sorted { $0.startDate < $1.startDate }
            }
        }
        eventsByMessage = resolved
    }
}

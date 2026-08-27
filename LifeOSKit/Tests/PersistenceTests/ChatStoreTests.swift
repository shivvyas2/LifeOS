// LifeOSKit/Tests/PersistenceTests/ChatStoreTests.swift
import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct ChatStoreTests {
    private func makeStore() throws -> ChatStore {
        let container = try LifeOSContainer.make(inMemory: true)
        return ChatStore(context: ModelContext(container))
    }

    @Test func recentReturnsOldestFirstAndCapsAtTheLimit() throws {
        let store = try makeStore()
        let conversation = UUID()
        let base = Date(timeIntervalSince1970: 1_756_209_600)
        for index in 0..<25 {
            try store.append(
                conversationID: conversation, role: .user, text: "m\(index)",
                at: base.addingTimeInterval(Double(index))
            )
        }

        let recent = try store.recent(conversationID: conversation, limit: 20)
        #expect(recent.count == 20)
        #expect(recent.first?.text == "m5")
        #expect(recent.last?.text == "m24")
    }

    @Test func conversationsDoNotBleedIntoEachOther() throws {
        let store = try makeStore()
        let mine = UUID()
        try store.append(conversationID: mine, role: .user, text: "mine")
        try store.append(conversationID: UUID(), role: .user, text: "theirs")

        #expect(try store.recent(conversationID: mine).map(\.text) == ["mine"])
    }

    @Test func toolSummariesRoundTrip() throws {
        let store = try makeStore()
        let conversation = UUID()
        try store.append(
            conversationID: conversation, role: .assistant,
            text: "Done", toolSummaries: ["Checked your calendar", "Created an event"]
        )

        let saved = try store.recent(conversationID: conversation)
        #expect(saved[0].toolSummaries == ["Checked your calendar", "Created an event"])
        #expect(saved[0].role == .assistant)
    }

    @Test func latestConversationIsTheMostRecentlyWrittenOne() throws {
        let store = try makeStore()
        let older = UUID()
        let newer = UUID()
        try store.append(conversationID: older, role: .user, text: "a")
        try store.append(conversationID: newer, role: .user, text: "b")

        #expect(try store.latestConversationID() == newer)
    }

    @Test func anEmptyStoreHasNoLatestConversation() throws {
        let store = try makeStore()
        #expect(try store.latestConversationID() == nil)
    }
}

@Suite @MainActor struct ChatEventCardTests {
    private func makeStore() throws -> ChatStore {
        ChatStore(context: ModelContext(try LifeOSContainer.make(inMemory: true)))
    }

    @Test func aReplyRemembersTheEventsItWasAbout() throws {
        let store = try makeStore()
        let conversation = UUID()
        let ids = [UUID(), UUID()]

        try store.append(conversationID: conversation, role: .assistant,
                         text: "You have two things on", eventIDs: ids)

        let saved = try #require(try store.recent(conversationID: conversation).first)
        #expect(saved.eventIDs == ids)
    }

    /// A conversation that predates cards, and a plain reply, both carry none.
    @Test func aReplyWithNoEventsCarriesAnEmptyList() throws {
        let store = try makeStore()
        let conversation = UUID()

        try store.append(conversationID: conversation, role: .assistant, text: "Nothing on")

        #expect(try store.recent(conversationID: conversation).first?.eventIDs == [])
    }

    @Test func idsSurviveAReloadInTheOrderTheyWereWritten() throws {
        let store = try makeStore()
        let conversation = UUID()
        let ids = (0..<5).map { _ in UUID() }

        try store.append(conversationID: conversation, role: .assistant,
                         text: "Your week", eventIDs: ids)

        #expect(try store.recent(conversationID: conversation).first?.eventIDs == ids)
    }
}

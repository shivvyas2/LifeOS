import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct AccountDataTests {
    private func context() throws -> ModelContext { ModelContext(try LifeOSContainer.make(inMemory: true)) }
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "account.data.\(UUID().uuidString)")! }

    @Test func clearingOneConversationLeavesTheOthers() throws {
        let context = try context()
        let chats = ChatStore(context: context)
        let coach = UUID(), assistant = UUID()
        try chats.append(conversationID: coach, role: .user, text: "How did I sleep?")
        try chats.append(conversationID: assistant, role: .user, text: "Move standup")
        try chats.deleteConversation(coach)
        #expect(try chats.recent(conversationID: coach).isEmpty)
        #expect(try chats.recent(conversationID: assistant).count == 1)
    }

    @Test func eachCategoryClearsOnlyItsOwn() throws {
        let context = try context()
        let store = defaults()
        let notes = NotesStore(context: context)
        _ = try notes.createDocument(title: "Plan", bucket: .projects)
        context.insert(PlanEntry(kind: .habit, title: "Run"))
        try ChatStore(context: context).append(conversationID: UUID(), role: .user, text: "hi")
        store.set(Date(), forKey: "notes.sync.cursor")
        store.set(UUID().uuidString, forKey: "coach.conversationID")
        try context.save()

        try LocalDataEraser(context: context, defaults: store).erase([.notes])
        #expect(try context.fetchCount(FetchDescriptor<NoteDocument>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PlanEntry>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<ChatMessage>()) == 1)
        #expect(store.object(forKey: "notes.sync.cursor") == nil)
        #expect(store.string(forKey: "coach.conversationID") != nil)

        try LocalDataEraser(context: context, defaults: store).erase([.habits, .chats])
        #expect(try context.fetchCount(FetchDescriptor<PlanEntry>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ChatMessage>()) == 0)
        #expect(store.string(forKey: "coach.conversationID") == nil)
    }

    @Test func categoriesKnowWhereTheyLive() {
        #expect(DataCategory.allCases.filter(\.hasServerRows) == [.notes, .health, .messages])
        #expect(DataCategory.chats.title == "AI chats")
    }

    @Test func onlyConfirmedDeletionsAreWiped() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let list = defaults()
        let kept = UserScope(id: "kept-user"), gone = UserScope(id: "gone-user")
        for scope in [kept, gone] {
            try FileManager.default.createDirectory(at: scope.directory(base: base), withIntermediateDirectories: true)
            UserDefaults(suiteName: scope.defaultsSuiteName)!.set(true, forKey: "marker")
        }
        var wipe = PendingAccountWipe(defaults: list)
        wipe.add(kept.id); wipe.add(gone.id); wipe.add(gone.id)
        #expect(wipe.ids == [kept.id, gone.id])
        try wipe.wipe(gone.id, base: base)
        #expect(!FileManager.default.fileExists(atPath: gone.directory(base: base).path))
        #expect(FileManager.default.fileExists(atPath: kept.directory(base: base).path))
        #expect(UserDefaults(suiteName: gone.defaultsSuiteName)!.object(forKey: "marker") == nil)
        #expect(PendingAccountWipe(defaults: list).ids == [kept.id])
        wipe = PendingAccountWipe(defaults: list)
        wipe.remove(kept.id)
        #expect(wipe.ids.isEmpty)
    }
}

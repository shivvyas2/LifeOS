import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct ProjectsStoreTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private var day: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 9))! }
    private let me = UUID(), friend = UUID()
    private func store() throws -> ProjectsStore {
        ProjectsStore(context: ModelContext(try LifeOSContainer.make(inMemory: true)), calendar: calendar)
    }

    @Test func aNewProjectHasItsOwnerAsAMember() throws {
        let store = try store()
        let id = try store.createProject(name: "LifeOS 1.1", scope: "Ship Notes", colour: "tomato", ownerID: me)
        #expect(try store.projects().map(\.name) == ["LifeOS 1.1"])
        #expect(try store.members(projectID: id).map(\.userID) == [me])
        #expect(try store.members(projectID: id).first?.role == "owner")
    }

    @Test func tasksMoveAcrossTheBoardAndCountTowardProgress() throws {
        let store = try store()
        let project = try store.createProject(name: "P", scope: "", colour: "moss", ownerID: me)
        let a = try store.createTask(projectID: project, title: "Wireframes")
        let b = try store.createTask(projectID: project, title: "Copy")
        try store.moveTask(id: a, to: .doing, at: 0)
        try store.moveTask(id: b, to: .done, at: 0)
        let tasks = try store.tasks(projectID: project)
        #expect(tasks.first { $0.id == a }?.status == .doing)
        #expect(tasks.first { $0.id == b }?.doneAt != nil)
        let snapshot = try #require(try store.projects().first)
        #expect(snapshot.done == 1 && snapshot.total == 2)
    }

    @Test func myTasksTodayAreOpenAndMineDueOrScheduledToday() throws {
        let store = try store()
        let project = try store.createProject(name: "P", scope: "", colour: "iris", ownerID: me)
        let due = try store.createTask(projectID: project, title: "Due today")
        try store.updateTask(id: due, ownerID: me, dueOn: day)
        let block = try store.createTask(projectID: project, title: "Block today")
        try store.updateTask(id: block, ownerID: me, startsAt: day.addingTimeInterval(3_600), endsAt: day.addingTimeInterval(7_200))
        let theirs = try store.createTask(projectID: project, title: "Theirs")
        try store.updateTask(id: theirs, ownerID: friend, dueOn: day)
        let done = try store.createTask(projectID: project, title: "Done")
        try store.updateTask(id: done, ownerID: me, dueOn: day)
        try store.moveTask(id: done, to: .done, at: 0)
        let tomorrow = try store.createTask(projectID: project, title: "Tomorrow")
        try store.updateTask(id: tomorrow, ownerID: me, dueOn: day.addingTimeInterval(86_400))
        #expect(Set(try store.myTasks(userID: me, on: day).map(\.title)) == ["Due today", "Block today"])
    }

    @Test func aDeletedTaskIsHiddenAndPendingForPush() throws {
        let store = try store()
        let project = try store.createProject(name: "P", scope: "", colour: "rose", ownerID: me)
        let task = try store.createTask(projectID: project, title: "Gone")
        try store.markSynced(at: .now)
        try store.deleteTask(id: task)
        #expect(try store.tasks(projectID: project).isEmpty)
        #expect(try store.pending().tasks.map(\.id) == [task])
    }

    @Test func aPulledRowDoesNotOverwriteANewerLocalEdit() throws {
        let store = try store()
        let project = try store.createProject(name: "Local", scope: "", colour: "lagoon", ownerID: me)
        try store.markSynced(at: Date(timeIntervalSince1970: 100))
        try store.updateProject(id: project, name: "Edited here")
        try store.applyRemoteProject(id: project, name: "Edited there", scope: "", startsOn: nil, endsOn: nil,
                                     colour: "lagoon", ownerID: me, repo: nil, archivedAt: nil,
                                     updatedAt: Date(timeIntervalSince1970: 200), deletedAt: nil)
        #expect(try store.projects().first?.name == "Edited here")
    }
}

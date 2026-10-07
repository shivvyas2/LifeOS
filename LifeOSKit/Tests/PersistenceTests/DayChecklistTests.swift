import Testing
import Foundation
@testable import Persistence

@Suite struct DayChecklistTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private var day: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 6))! }
    private let journalID = UUID()

    @Test func rowsComeInOrderJournalDueThenHabits() {
        let run = UUID(), read = UUID()
        let rows = DayChecklist.rows(
            journal: [NoteBlock(kind: .heading1, text: "Tuesday"),
                      NoteBlock(kind: .todo, text: "Call the dentist", isChecked: true),
                      NoteBlock(kind: .todo, text: "Draft the plan")],
            journalID: journalID,
            due: [DayChecklist.DueTask(documentID: UUID(), blockID: UUID(), text: "Buy oat milk", isChecked: false, pageTitle: "Groceries")],
            habits: [DayChecklist.Habit(id: run, title: "5km run", createdAt: day.addingTimeInterval(-86_400 * 30), streak: 6),
                     DayChecklist.Habit(id: read, title: "Read 10 pages", createdAt: day.addingTimeInterval(-86_400), streak: 0)],
            ticked: [run], day: day, editable: true, calendar: calendar, now: day.addingTimeInterval(3_600 * 15)
        )
        #expect(rows.map(\.text) == ["Call the dentist", "Draft the plan", "Buy oat milk", "5km run", "Read 10 pages"])
        #expect(rows.map(\.isDone) == [true, false, false, true, false])
        #expect(rows[2].detail == "Groceries")
        #expect(rows[3].detail == "6 days")
        #expect(rows[4].detail == nil)
        let allEditable = rows.allSatisfy(\.isEditable)
        #expect(allEditable)
        #expect(Set(rows.map(\.id)).count == 5)
    }

    @Test func habitsAreARecordOnAnyDayButToday() {
        let habit = DayChecklist.Habit(id: UUID(), title: "5km run", createdAt: day.addingTimeInterval(-86_400 * 30), streak: 0)
        let journal = [NoteBlock(kind: .todo, text: "Draft the plan")]
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day)!
        let ahead = DayChecklist.rows(journal: journal, journalID: journalID, due: [], habits: [habit], ticked: [],
                                      day: tomorrow, editable: true, calendar: calendar, now: day)
        #expect(ahead.map(\.isEditable) == [true, false])
        let today = DayChecklist.rows(journal: journal, journalID: journalID, due: [], habits: [habit], ticked: [],
                                      day: day, editable: true, calendar: calendar, now: day.addingTimeInterval(3_600 * 15))
        #expect(today.map(\.isEditable) == [true, true])
    }

    @Test func aJournalToDoIsNotAlsoADueRow() {
        let block = NoteBlock(kind: .todo, text: "Draft the plan", dueDate: day)
        let rows = DayChecklist.rows(
            journal: [block], journalID: journalID,
            due: [DayChecklist.DueTask(documentID: journalID, blockID: block.id, text: block.text, isChecked: false, pageTitle: "Tuesday, October 6")],
            habits: [], ticked: [], day: day, editable: true, calendar: calendar
        )
        #expect(rows.map(\.text) == ["Draft the plan"])
    }

    @Test func habitsCreatedLaterAreNotOnAnOldDay() {
        let rows = DayChecklist.rows(
            journal: [], journalID: nil, due: [],
            habits: [DayChecklist.Habit(id: UUID(), title: "Stretch", createdAt: day.addingTimeInterval(86_400 * 2), streak: 0),
                     DayChecklist.Habit(id: UUID(), title: "Walk", createdAt: day.addingTimeInterval(3_600), streak: 0)],
            ticked: [], day: day, editable: false, calendar: calendar
        )
        #expect(rows.map(\.text) == ["Walk"])
        let noneEditable = rows.allSatisfy { !$0.isEditable }
        #expect(noneEditable)
    }

    private func task(_ text: String, daysAgo: Int, checked: Bool = false, page: String = "Health") -> DayChecklist.DueTask {
        DayChecklist.DueTask(documentID: UUID(), blockID: UUID(), text: text, isChecked: checked, pageTitle: page,
                             dueDate: day.addingTimeInterval(-86_400 * Double(daysAgo)))
    }

    @Test func overdueComesAfterTodaysDueOldestFirstOnTodayOnly() {
        let today = day.addingTimeInterval(3_600 * 9)
        let rows = DayChecklist.rows(
            journal: [], journalID: nil,
            due: [DayChecklist.DueTask(documentID: UUID(), blockID: UUID(), text: "Buy oat milk", isChecked: false, pageTitle: "Groceries")],
            overdue: [task("Call the dentist", daysAgo: 1), task("File taxes", daysAgo: 5, page: "Money")],
            habits: [], ticked: [], day: day, editable: true, calendar: calendar, now: today)
        #expect(rows.map(\.text) == ["Buy oat milk", "File taxes", "Call the dentist"])
        #expect(rows[1].detail == "overdue · Money")
        let yesterday = DayChecklist.rows(
            journal: [], journalID: nil, due: [], overdue: [task("Call the dentist", daysAgo: 1)],
            habits: [], ticked: [], day: day, editable: true, calendar: calendar, now: today.addingTimeInterval(86_400))
        #expect(yesterday.isEmpty)
    }

    @Test func overdueSkipsDoneTasks() {
        let rows = DayChecklist.rows(
            journal: [], journalID: nil, due: [], overdue: [task("Done already", daysAgo: 2, checked: true)],
            habits: [], ticked: [], day: day, editable: true, calendar: calendar, now: day.addingTimeInterval(3_600))
        #expect(rows.isEmpty)
    }

    @Test func myProjectTasksComeAfterTheDaysTasksAndBeforeHabits() {
        let task = UUID(), run = UUID()
        let rows = DayChecklist.rows(
            journal: [NoteBlock(kind: .todo, text: "Draft the plan")], journalID: journalID,
            due: [], projectTasks: [DayChecklist.ProjectDue(taskID: task, text: "Wireframes", isDone: false, projectName: "LifeOS 1.1")],
            habits: [DayChecklist.Habit(id: run, title: "5km run", createdAt: day.addingTimeInterval(-86_400), streak: 2)],
            ticked: [], day: day, editable: true, calendar: calendar, now: day.addingTimeInterval(3_600))
        #expect(rows.map(\.text) == ["Draft the plan", "Wireframes", "5km run"])
        #expect(rows[1].detail == "LifeOS 1.1")
        #expect(rows[1].source == .project(taskID: task))
        #expect(rows[1].isEditable)
    }
}


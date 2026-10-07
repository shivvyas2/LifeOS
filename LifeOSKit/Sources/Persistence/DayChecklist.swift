import Foundation

/// One line on the day's checklist, from the journal page, another page
/// due that day, or a habit. Plain values: the screen never holds a model.
public struct ChecklistRow: Identifiable, Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case journal(blockID: UUID)
        case page(documentID: UUID, blockID: UUID)
        case habit(entryID: UUID)
        case project(taskID: UUID)
    }

    public let id: String
    public let source: Source
    public let text: String
    /// The page title for a due row, the streak for a habit, nothing for
    /// the day's own list.
    public let detail: String?
    public let isDone: Bool
    public let isEditable: Bool

    public init(source: Source, text: String, detail: String?, isDone: Bool, isEditable: Bool) {
        self.id = switch source {
        case .journal(let blockID): "journal|\(blockID.uuidString)"
        case .page(let documentID, let blockID): "page|\(documentID.uuidString)|\(blockID.uuidString)"
        case .habit(let entryID): "habit|\(entryID.uuidString)"
        case .project(let taskID): "project|\(taskID.uuidString)"
        }
        self.source = source; self.text = text; self.detail = detail
        self.isDone = isDone; self.isEditable = isEditable
    }
}

/// Merges the three sources of a day's checklist in a fixed order.
public enum DayChecklist {
    public struct DueTask: Equatable, Sendable {
        public let documentID: UUID
        public let blockID: UUID
        public let text: String
        public let isChecked: Bool
        public let pageTitle: String
        public let dueDate: Date?
        public init(documentID: UUID, blockID: UUID, text: String, isChecked: Bool, pageTitle: String, dueDate: Date? = nil) {
            self.documentID = documentID; self.blockID = blockID; self.text = text
            self.isChecked = isChecked; self.pageTitle = pageTitle; self.dueDate = dueDate
        }
    }

    /// A project task assigned to this person for the day.
    public struct ProjectDue: Equatable, Sendable {
        public let taskID: UUID
        public let text: String
        public let isDone: Bool
        public let projectName: String
        public init(taskID: UUID, text: String, isDone: Bool, projectName: String) {
            self.taskID = taskID; self.text = text; self.isDone = isDone; self.projectName = projectName
        }
    }

    public struct Habit: Equatable, Sendable {
        public let id: UUID
        public let title: String
        public let createdAt: Date
        public let streak: Int
        public init(id: UUID, title: String, createdAt: Date, streak: Int) {
            self.id = id; self.title = title; self.createdAt = createdAt; self.streak = streak
        }
    }

    /// The journal page's to-dos in page order, then what is due from other
    /// pages (a journal to-do that also carries the date is not repeated),
    /// then, on today only, what is overdue, then the habits that existed by the end of the day. A habit tick is a
    /// record of the day it is made, so habit rows are editable on today
    /// only, whatever `editable` says for the page rows.
    public static func rows(
        journal: [NoteBlock], journalID: UUID?, due: [DueTask], overdue: [DueTask] = [],
        projectTasks: [ProjectDue] = [], habits: [Habit],
        ticked: Set<UUID>, day: Date, editable: Bool, calendar: Calendar = .current, now: Date = .now
    ) -> [ChecklistRow] {
        var rows: [ChecklistRow] = []
        let habitsEditable = editable && calendar.isDate(day, inSameDayAs: now)
        for block in journal where block.kind == .todo {
            rows.append(ChecklistRow(source: .journal(blockID: block.id), text: block.text, detail: nil,
                                     isDone: block.isChecked, isEditable: editable))
        }
        for task in due where task.documentID != journalID {
            rows.append(ChecklistRow(source: .page(documentID: task.documentID, blockID: task.blockID),
                                     text: task.text, detail: task.pageTitle, isDone: task.isChecked, isEditable: editable))
        }
        // Late to-dos join today's list, oldest first; a past day is a record.
        if calendar.isDate(day, inSameDayAs: now) {
            let late = overdue.filter { !$0.isChecked && $0.documentID != journalID }
                .sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
            for task in late {
                rows.append(ChecklistRow(source: .page(documentID: task.documentID, blockID: task.blockID),
                                         text: task.text, detail: "overdue · \(task.pageTitle)",
                                         isDone: false, isEditable: editable))
            }
        }
        for task in projectTasks {
            rows.append(ChecklistRow(source: .project(taskID: task.taskID), text: task.text, detail: task.projectName,
                                     isDone: task.isDone, isEditable: editable))
        }
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) ?? day
        for habit in habits where habit.createdAt < dayEnd {
            let streak = habit.streak > 0 ? "\(habit.streak) \(habit.streak == 1 ? "day" : "days")" : nil
            rows.append(ChecklistRow(source: .habit(entryID: habit.id), text: habit.title, detail: streak,
                                     isDone: ticked.contains(habit.id), isEditable: habitsEditable))
        }
        return rows
    }
}

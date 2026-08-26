import Foundation
import Persistence

/// One stored score, as plain values. Records rather than `@Model` objects so
/// the whole assembly is testable without a container.
public struct ScoreRecord: Sendable, Equatable {
    public let month: Date
    public let userScore: Int?
    public let proposedScore: Int?
    public let evidenceRows: [EvidenceRow]

    public init(month: Date, userScore: Int?, proposedScore: Int?, evidenceRows: [EvidenceRow]) {
        self.month = month
        self.userScore = userScore
        self.proposedScore = proposedScore
        self.evidenceRows = evidenceRows
    }
}

/// One stored check-in answer, as plain values.
public struct AnswerRecord: Sendable, Equatable {
    public let month: Date
    public let questionID: String
    public let answer: String

    public init(month: Date, questionID: String, answer: String) {
        self.month = month
        self.questionID = questionID
        self.answer = answer
    }
}

/// One decided month, as it was decided.
public struct MonthEntry: Sendable, Equatable {
    public let month: Date
    public let userScore: Int
    public let proposedScore: Int?
    /// Frozen at close time. Never recomputed, so a goal changed later cannot
    /// rewrite what an earlier month's reasoning said.
    public let evidenceRows: [EvidenceRow]
}

/// One question's answers laid across the months, aligned by index to
/// `SectorHistory.months`. `nil` is a month that question was not answered in.
public struct QuestionTrack: Sendable, Equatable {
    public let questionID: String
    public let prompt: String
    public let answers: [String?]
}

/// One free-text answer, kept apart from the comparable tracks because it sits
/// on no scale and is read rather than compared.
public struct HistoryNote: Sendable, Equatable {
    public let month: Date
    public let text: String
}

/// Everything one sector has looked like over time, assembled from stored
/// values.
///
/// Pure and built from plain records rather than `@Model` objects, in the same
/// shape as every scorer. The app target has no test target, so anything that
/// decides something lives here where it can be covered.
public struct SectorHistory: Sendable, Equatable {
    public let sector: LifeSector
    public let months: [MonthEntry]
    public let questions: [QuestionTrack]
    public let notes: [HistoryNote]
    public let observations: [String]

    public static func build(
        sector: LifeSector,
        months: [ScoreRecord],
        answers: [AnswerRecord],
        calendar: Calendar = .current
    ) -> SectorHistory {
        // A month recorded but never decided is not history yet: the person
        // has not passed through it, so there is nothing of theirs to show.
        let decided = months
            .compactMap { record -> MonthEntry? in
                guard let userScore = record.userScore else { return nil }
                return MonthEntry(
                    month: Date.startOfMonth(record.month, calendar: calendar),
                    userScore: userScore,
                    proposedScore: record.proposedScore,
                    evidenceRows: record.evidenceRows
                )
            }
            .sorted { $0.month < $1.month }

        let questionSet = CheckInQuestion.questions(for: sector)
        let byMonth = Dictionary(grouping: answers) {
            Date.startOfMonth($0.month, calendar: calendar)
        }

        // Tracks follow the order the questions are asked in, so the screen
        // reads the way the close did.
        let tracks: [QuestionTrack] = questionSet
            .filter { !$0.isFreeText }
            .compactMap { question in
                let answers = decided.map { entry in
                    byMonth[entry.month]?.first { $0.questionID == question.id }?.answer
                }
                guard answers.contains(where: { $0 != nil }) else { return nil }
                return QuestionTrack(
                    questionID: question.id, prompt: question.prompt, answers: answers
                )
            }

        let freeTextIDs = Set(questionSet.filter(\.isFreeText).map(\.id))
        let notes = answers
            .filter { freeTextIDs.contains($0.questionID) && !$0.answer.isEmpty }
            .map { HistoryNote(month: Date.startOfMonth($0.month, calendar: calendar), text: $0.answer) }
            .sorted { $0.month > $1.month }

        return SectorHistory(
            sector: sector,
            months: decided,
            questions: tracks,
            notes: notes,
            observations: [] // Task 2 replaces this
        )
    }
}

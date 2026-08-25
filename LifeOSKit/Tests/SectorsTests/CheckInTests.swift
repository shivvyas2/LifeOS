import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct CheckInQuestionTests {

    /// These four sectors have no other source, so a missing question set
    /// would leave them permanently unscorable.
    @Test func everyRelationalSectorHasQuestions() {
        for sector in [LifeSector.family, .romance, .friends, .soul] {
            #expect(!CheckInQuestion.questions(for: sector).isEmpty)
        }
    }

    @Test func questionIDsAreUniqueWithinASector() {
        for sector in LifeSector.allCases {
            let ids = CheckInQuestion.questions(for: sector).map(\.id)
            #expect(Set(ids).count == ids.count)
        }
    }

    /// IDs are persisted on CheckInAnswer, so a rename orphans stored answers.
    @Test func questionIDsAreNamespacedBySector() {
        for sector in LifeSector.allCases {
            let questions = CheckInQuestion.questions(for: sector)
            #expect(questions.allSatisfy { $0.id.hasPrefix("\(sector.rawValue).") })
        }
    }

    /// A free text question carries no options by definition, so only the
    /// scored questions are checked for a usable set.
    @Test func everyScoredQuestionHasAUsableOptionSet() {
        for sector in LifeSector.allCases {
            for question in CheckInQuestion.questions(for: sector) where !question.isFreeText {
                #expect(question.options.count >= 2)
                #expect(question.options.allSatisfy { (0...1).contains($0.normalised) })
            }
        }
    }

    @Test func freeTextQuestionsCarryNoOptions() {
        let notes = CheckInQuestion.questions(for: .romance).filter(\.isFreeText)
        #expect(notes.count == 1)
        #expect(notes.first?.options.isEmpty == true)
    }
}

@Suite struct CheckInScorerTests {

    private var romanceQuestions: [CheckInQuestion] {
        CheckInQuestion.questions(for: .romance)
    }

    /// Free text questions are skipped: they have no options to pick a best
    /// from, and they carry no weight in the score anyway.
    @Test func answeringEveryScoredQuestionAtTheTopScoresTen() {
        var answers: [String: String] = [:]
        for question in romanceQuestions where !question.isFreeText {
            guard let best = question.options.max(by: { $0.normalised < $1.normalised })
            else { continue }
            answers[question.id] = best.label
        }
        let scorer = CheckInScorer(sector: .romance, answers: answers)
        #expect(scorer.evidence().proposedScore == 10)
    }

    @Test func noAnswersProposesNothing() {
        #expect(CheckInScorer(sector: .romance, answers: [:]).evidence().proposedScore == nil)
    }

    /// A half-finished check-in scores on what was answered, so leaving the
    /// close midway does not silently score the person down.
    @Test func unansweredQuestionsAreSkippedNotCountedAsZero() {
        let first = romanceQuestions[0]
        let best = first.options.max { $0.normalised < $1.normalised }!
        let scorer = CheckInScorer(sector: .romance, answers: [first.id: best.label])
        #expect(scorer.evidence().rows.count == 1)
        #expect(scorer.evidence().proposedScore == 10)
    }

    /// Free text has no scale, so it is recorded as context and left unweighted.
    @Test func freeTextIsShownButNotScored() {
        let scorer = CheckInScorer(sector: .romance, answers: ["romance.note": "a good month"])
        let row = scorer.evidence().rows.first { $0.label.contains("worth remembering") }
        #expect(row?.weight == 0)
    }

    @Test func anUnrecognisedAnswerIsIgnored() {
        let first = romanceQuestions[0]
        let scorer = CheckInScorer(sector: .romance, answers: [first.id: "nonsense"])
        #expect(scorer.evidence().proposedScore == nil)
    }
}

import Foundation
import Persistence

/// A sector scored from what the person answered at close time.
///
/// This is what makes month one scorable for the four sectors with no tracked
/// data at all, and over time the answers themselves become the trend line.
public struct CheckInScorer: SectorScorer {
    public let sector: LifeSector

    /// Answers keyed by question id, holding the chosen option's label or the
    /// free text.
    private let answers: [String: String]

    public init(sector: LifeSector, answers: [String: String]) {
        self.sector = sector
        self.answers = answers
    }

    public func evidence() -> Evidence {
        let rows: [EvidenceRow] = CheckInQuestion.questions(for: sector).compactMap { question in
            guard let answer = answers[question.id], !answer.isEmpty else { return nil }

            if question.isFreeText {
                // No scale to place it on, so it is context and nothing more.
                return EvidenceRow(
                    label: question.prompt.lowercased(), value: answer,
                    normalised: 0, weight: 0
                )
            }

            // An answer that matches no option is stale data from a question
            // that has since changed. Dropping it beats guessing at it.
            guard let option = question.options.first(where: { $0.label == answer }) else {
                return nil
            }

            return EvidenceRow(
                label: question.prompt.lowercased(), value: option.label,
                normalised: option.normalised, weight: question.weight
            )
        }

        return Evidence(rows)
    }
}

import Foundation
import SwiftData
import Persistence
import Sectors

/// Drives one sector's history screen. Follows `LifeBoardViewModel`'s shape:
/// `attach(_:)` hands over the context once, `load(sector:)` refreshes from
/// it, and the screen owns the instance and calls both.
///
/// Deliberately thin. There is no test target for the app, so nothing put
/// here can be unit tested; every decision about what the history looks like
/// lives in `SectorHistory.build`, in the `Sectors` package, where it is.
@MainActor
@Observable
final class SectorDetailViewModel {
    private(set) var history: SectorHistory?

    private var store: SectorStore?
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func attach(_ context: ModelContext) {
        store = SectorStore(context: context, calendar: calendar)
    }

    /// Fetch, map to plain records, then one pure call. No decisions here.
    func load(sector: LifeSector, months: Int = 12) {
        guard let store else { return }
        let scores = (try? store.history(sector: sector, months: months)) ?? []
        let records = scores.map {
            ScoreRecord(
                month: $0.month, userScore: $0.userScore,
                proposedScore: $0.proposedScore, evidenceRows: $0.archivedEvidence.rows
            )
        }
        let answers = records.flatMap { record in
            ((try? store.answers(sector: sector, month: record.month)) ?? []).map {
                AnswerRecord(month: $0.month, questionID: $0.questionID, answer: $0.answer)
            }
        }
        history = SectorHistory.build(
            sector: sector, months: records, answers: answers, calendar: calendar
        )
    }
}

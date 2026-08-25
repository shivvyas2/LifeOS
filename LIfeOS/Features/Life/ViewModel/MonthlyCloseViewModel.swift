import Foundation
import SwiftData
import Persistence
import Sectors
import Insights

/// Drives one pass through the nine-sector close.
///
/// Each sector commits to the store as soon as the person moves past it, so
/// leaving the sheet midway is a normal thing to do rather than an error
/// state: reopening it builds a fresh `MonthlyCloseViewModel`, which resumes
/// at the first sector `CloseProgress` says is still unscored.
///
/// A skip is different from a commit: it must move the close past the sector
/// on screen without ever writing a score nobody looked at, and it must not
/// keep the sector hidden the *next* time the close is opened, since nothing
/// was decided. `skippedThisSession` is exactly that: an in-memory set, alive
/// only for this instance, unioned with the store's committed sectors before
/// asking `CloseProgress` what is next. A fresh instance next time starts
/// with an empty set, so a skipped sector is offered again.
@MainActor
@Observable
final class MonthlyCloseViewModel {
    private(set) var sector: LifeSector?
    private(set) var evidence = Evidence()
    private(set) var proposed: Int?
    private(set) var previousUserScore: Int?
    private(set) var note: String?
    private(set) var position = 1
    private(set) var total = LifeSector.boardOrder.count
    private(set) var isComplete = false

    /// Answers for the sector on screen, keyed by question id.
    private(set) var answers: [String: String] = [:]
    var chosenScore: Int = 5

    private var skippedThisSession: Set<LifeSector> = []

    private let store: SectorStore
    private let month: Date
    private let calendar: Calendar
    private let engine: Engine

    init(
        context: ModelContext, month: Date,
        engine: Engine = OnDeviceEngine(), calendar: Calendar = .current
    ) {
        self.store = SectorStore(context: context, calendar: calendar)
        self.month = month
        self.calendar = calendar
        self.engine = engine
    }

    var questions: [CheckInQuestion] {
        sector.map { CheckInQuestion.questions(for: $0) } ?? []
    }

    /// Moves to the first sector `CloseProgress` says is still open, given
    /// what is committed in the store plus what has been skipped this
    /// session. Called on first appearance and after every commit or skip.
    func advance() {
        let progress = CloseProgress(scored: committedSectors().union(skippedThisSession))
        position = progress.position
        total = progress.total
        isComplete = progress.isComplete
        sector = progress.next

        answers = [:]
        note = nil

        guard let sector else { return }

        previousUserScore = previousScore(for: sector)
        for stored in (try? store.answers(sector: sector, month: month)) ?? [] {
            answers[stored.questionID] = stored.answer
        }
        recompute()
    }

    /// Rebuilds the proposal from the answers on screen.
    ///
    /// Only the check-in sectors recompute live here. The six data-fed
    /// sectors (Body, Money, Mission, Growth, Mind, Soul) are not wired into
    /// this yet, so they fall through to `CheckInScorer`, which returns no
    /// rows for a sector with no check-in questions and therefore proposes
    /// nothing — the honest answer for a sector with no evidence, not a bug.
    func recompute() {
        guard let sector else { return }
        evidence = CheckInScorer(sector: sector, answers: answers).evidence()
        proposed = evidence.proposedScore
        chosenScore = proposed ?? previousUserScore ?? 5
    }

    func answer(_ question: CheckInQuestion, with value: String) {
        guard let sector else { return }
        answers[question.id] = value
        try? store.saveAnswer(
            sector: sector, month: month,
            questionID: question.id, answer: value
        )
        recompute()
    }

    /// Records the score, both proposed and chosen, then advances. Once a
    /// sector is scored `SectorStore.record` will not overwrite it, so this
    /// is safe to call exactly once per sector, which is what the "Next"
    /// button does.
    func commit() {
        guard let sector else { return }
        let score = try? store.record(
            sector: sector, month: month, proposed: proposed, evidence: evidence
        )
        if let score {
            try? store.commit(userScore: chosenScore, to: score)
        }
        advance()
    }

    /// Moves on without deciding. The sector stays genuinely unscored in the
    /// store; only this session remembers it was passed over.
    func skip() {
        guard let sector else { return }
        skippedThisSession.insert(sector)
        advance()
    }

    /// Asks the on-device model for one sentence about the sector on screen.
    ///
    /// Skipped when there is no evidence: nothing for the model to describe,
    /// and a sentence about nothing would look like an opinion the rule
    /// never formed. `ModelAvailability` inside `Engine` handles Apple
    /// Intelligence being off or unsupported by throwing, which `try?` turns
    /// into a silent "no note" rather than a crash — the intended fallback.
    func loadNote() async {
        guard let sector, !evidence.isEmpty else { return }
        let context = SectorEvidenceContext(
            sectorTitle: sector.title, rows: evidence.rows, previousUserScore: previousUserScore
        )
        note = try? await engine.run(SectorNoteTask(sectorTitle: sector.title), context).summary
    }

    private func committedSectors() -> Set<LifeSector> {
        Set(
            ((try? store.scores(forMonth: month)) ?? [])
                .filter(\.isScored)
                .map(\.sector)
        )
    }

    private func previousScore(for sector: LifeSector) -> Int? {
        guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: month) else { return nil }
        return (try? store.score(sector, month: lastMonth))?.userScore
    }
}

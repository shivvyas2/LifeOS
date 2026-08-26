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

    /// The person's pick for the sector on screen. `setChosenScore(_:)` is
    /// the only way this should change from user input: it also flips
    /// `hasChosenScore`, which is what stops a later `recompute()` — one runs
    /// on every keystroke into a free-text answer — from silently reverting a
    /// number the person already chose. The spec's first decision is that the
    /// user's number is what gets stored; this is what makes that true.
    private(set) var chosenScore: Int = 5
    private var hasChosenScore = false

    private var skippedThisSession: Set<LifeSector> = []
    /// This month's store reads, already fetched and month-filtered. Rebuilt
    /// once per sector in `advance()`, not on every keystroke: `recompute()`
    /// only re-runs `SectorEvidenceFactory` against what is already here.
    private var monthInputs = MonthInputs()

    /// Whether `evidence` was empty the last time `recompute()` ran, so a
    /// note request can fire on the transition into having some rather than
    /// on the sector merely appearing (see `NoteRequest.shouldRequest`).
    private var evidenceWasEmpty = true
    private var noteRequestTask: Task<Void, Never>?

    /// Debounced free-text saves, keyed by question id, plus the question and
    /// latest value each is waiting to persist. Choice answers never go
    /// through this: they save immediately, on `AnswerPersistence`'s say-so.
    private var pendingSaveTasks: [String: Task<Void, Never>] = [:]
    private var pendingSaveValues: [String: (question: CheckInQuestion, value: String)] = [:]

    private let store: SectorStore
    private let metricsStore: MetricsStore
    private let moneyStore: MoneyStore
    private let planStore: PlanStore
    private let month: Date
    private let calendar: Calendar
    private let router: CoachRouter

    init(
        context: ModelContext, month: Date,
        router: CoachRouter = CoachRouter(onDevice: OnDeviceEngine(), remote: nil),
        calendar: Calendar = .current
    ) {
        self.store = SectorStore(context: context, calendar: calendar)
        self.metricsStore = MetricsStore(context: context, calendar: calendar)
        self.moneyStore = MoneyStore(context: context, calendar: calendar)
        self.planStore = PlanStore(context: context, calendar: calendar)
        self.month = month
        self.calendar = calendar
        self.router = router
    }

    var questions: [CheckInQuestion] {
        sector.map { CheckInQuestion.questions(for: $0) } ?? []
    }

    /// Moves to the first sector `CloseProgress` says is still open, given
    /// what is committed in the store plus what has been skipped this
    /// session. Called on first appearance and after every commit or skip.
    func advance() {
        noteRequestTask?.cancel()
        noteRequestTask = nil

        let progress = CloseProgress(scored: committedSectors().union(skippedThisSession))
        position = progress.position
        total = progress.total
        isComplete = progress.isComplete
        sector = progress.next

        answers = [:]
        note = nil
        evidenceWasEmpty = true
        hasChosenScore = false

        guard let sector else { return }

        previousUserScore = previousScore(for: sector)
        for stored in (try? store.answers(sector: sector, month: month)) ?? [] {
            answers[stored.questionID] = stored.answer
        }
        monthInputs = (try? loadMonthInputs()) ?? MonthInputs()
        recompute()
    }

    /// Rebuilds the proposal for the sector on screen from `monthInputs` and
    /// the answers on screen. All the routing and merging logic — which
    /// scorer serves which sector, how Soul's journal and check-in evidence
    /// combine — lives in `SectorEvidenceFactory`, which is pure and unit
    /// tested; this is the single call into it.
    func recompute() {
        guard let sector else { return }
        evidence = SectorEvidenceFactory.evidence(
            for: sector, inputs: monthInputs, answers: answers, calendar: calendar
        )
        proposed = evidence.proposedScore
        chosenScore = ChosenScore.seeded(
            current: chosenScore, hasChosen: hasChosenScore,
            proposed: proposed, previousUserScore: previousUserScore
        )

        let isEmptyNow = evidence.isEmpty
        if NoteRequest.shouldRequest(wasEmpty: evidenceWasEmpty, isEmptyNow: isEmptyNow) {
            scheduleNoteRequest(for: sector)
        }
        evidenceWasEmpty = isEmptyNow
    }

    /// Records the person's own pick. The only path that should set
    /// `chosenScore` from outside; everything else only seeds it.
    func setChosenScore(_ value: Int) {
        chosenScore = value
        hasChosenScore = true
    }

    /// Updates the in-memory answer immediately, so `recompute()` and the
    /// score it seeds stay responsive as the person types. Persistence is
    /// immediate for a discrete choice and debounced for free text, per
    /// `AnswerPersistence`: saving every keystroke would fire a
    /// `context.save()`, and `RootView` turns every save into a `reloadAll()`
    /// across nine view models.
    func answer(_ question: CheckInQuestion, with value: String) {
        guard sector != nil else { return }
        answers[question.id] = value
        recompute()

        if AnswerPersistence.isImmediate(question) {
            persistAnswer(question, value: value)
        } else {
            scheduleDebouncedSave(question, value: value)
        }
    }

    /// Records the score, both proposed and chosen, then advances.
    /// `SectorStore.commit` refuses to overwrite a sector once it is scored,
    /// so this stays safe even though `advance()` never re-offers a
    /// committed sector in the first place.
    func commit() {
        guard let sector else { return }
        flushPendingSaves()
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
        flushPendingSaves()
        skippedThisSession.insert(sector)
        advance()
    }

    /// Reads and month-filters everything the six data-fed scorers need.
    /// `MonthWindow` (from `Sectors`) owns the date-boundary arithmetic and
    /// the filtering itself, so this is store reads plus assembly, nothing
    /// that needs its own test coverage.
    private func loadMonthInputs() throws -> MonthInputs {
        let window = MonthWindow(for: month, calendar: calendar)

        let readings = try metricsStore.metrics(from: window.start, to: window.lastDay).map(\.reading)
        let targets = try metricsStore.goals().targets

        let amounts = try moneyStore.entries(from: window.start, to: window.lastDay)
            .filter { !$0.pending }
            .map(\.amount)

        let goals = try planStore.entries(kind: .goal)
        let habits = try planStore.entries(kind: .habit)
        let goalStatuses = window.filter(goals, on: \.updatedAt).map(\.status)
        let planStatuses = window.filter(goals + habits, on: \.updatedAt).map(\.status)

        let perHabitTicks = try habits.map {
            try planStore.recentTicks(for: $0, days: window.daysInMonth, endingOn: window.lastDay)
        }
        let habitTickRate = SectorEvidenceFactory.habitTickRate(perHabitTicks: perHabitTicks)

        let journalEntries = try planStore.entries(kind: .journal)
        let journalDates = window.filter(journalEntries, on: \.createdAt).map(\.createdAt)

        var previousAmounts: [Double] = []
        var previousJournalCount: Int?
        if let previousMonth = calendar.date(byAdding: .month, value: -1, to: month) {
            let previousWindow = MonthWindow(for: previousMonth, calendar: calendar)
            previousAmounts = try moneyStore.entries(from: previousWindow.start, to: previousWindow.lastDay)
                .filter { !$0.pending }
                .map(\.amount)
            previousJournalCount = previousWindow.filter(journalEntries, on: \.createdAt).count
        }

        return MonthInputs(
            readings: readings, targets: targets,
            amounts: amounts, previousAmounts: previousAmounts,
            planStatuses: planStatuses, goalStatuses: goalStatuses,
            habitTickRate: habitTickRate,
            journalDates: journalDates, previousJournalCount: previousJournalCount,
            daysInMonth: window.daysInMonth
        )
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

    // MARK: - Free-text debounce

    private func persistAnswer(_ question: CheckInQuestion, value: String) {
        guard let sector else { return }
        try? store.saveAnswer(
            sector: sector, month: month, questionID: question.id, answer: value
        )
        pendingSaveTasks[question.id] = nil
        pendingSaveValues[question.id] = nil
    }

    private func scheduleDebouncedSave(_ question: CheckInQuestion, value: String) {
        pendingSaveTasks[question.id]?.cancel()
        pendingSaveValues[question.id] = (question, value)
        pendingSaveTasks[question.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.persistAnswer(question, value: value)
        }
    }

    /// Saves anything still waiting on its debounce, synchronously. Called
    /// before `advance()` clears `answers` on both `commit()` and `skip()`,
    /// so leaving a sector mid-sentence never drops the last few keystrokes.
    private func flushPendingSaves() {
        for (id, task) in pendingSaveTasks {
            task.cancel()
            if let pending = pendingSaveValues[id] {
                persistAnswer(pending.question, value: pending.value)
            }
        }
        pendingSaveTasks.removeAll()
        pendingSaveValues.removeAll()
    }

    // MARK: - The sector note

    /// Asks the coach for one sentence about the sector on screen, through
    /// `CoachRouter` like every other coach surface (`CoachViewModel` does
    /// the same). Routing through it, rather than an `Engine` directly,
    /// keeps availability caching, `retryLocally` handling for on-device
    /// session contention, and `.refused` surfacing all working the way they
    /// do everywhere else in the app.
    ///
    /// Debounced via `scheduleNoteRequest`, and guarded on arrival by
    /// `NoteRequest.shouldApply`: the close may have advanced to a different
    /// sector by the time this resolves, and an unavailable model must still
    /// leave the close fully usable with evidence rows and no sentence.
    private func scheduleNoteRequest(for sector: LifeSector) {
        noteRequestTask?.cancel()
        noteRequestTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.requestNote(for: sector)
        }
    }

    private func requestNote(for sector: LifeSector) async {
        let context = SectorEvidenceContext(
            sectorTitle: sector.title, rows: evidence.rows, previousUserScore: previousUserScore
        )
        let result = await router.run(SectorNoteTask(sectorTitle: sector.title), context)
        guard NoteRequest.shouldApply(resultSector: sector, currentSector: self.sector) else { return }

        switch result {
        case .answered(let output), .degraded(let output):
            note = output.summary
        case .refused, .exhausted, .unavailable, .tooLarge:
            note = nil
        }
    }
}

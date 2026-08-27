import Foundation
import SwiftData
import Persistence
import Sectors

/// One sector's month in flight: the band, what still moves it, and the
/// check-in questions that can be answered before close.
///
/// Thin by the same rule as `LifeBoardViewModel`: every number here is
/// computed in the `Sectors` package, which is where it can be tested.
@MainActor @Observable
final class InFlightSectorViewModel {
    private(set) var band: SectorBand?
    private(set) var levers: [LeverDelta] = []
    private(set) var answers: [String: String] = [:]
    private(set) var remainingDays = 0
    /// True when the ceiling came from targets the person never set, so the
    /// sheet can say whose numbers they are.
    private(set) var usesDefaultTargets = false

    private let sector: LifeSector
    private let calendar: Calendar
    private var context: ModelContext?

    /// Debounced free-text saves, keyed by question id. Choice answers save
    /// immediately, on `AnswerPersistence`'s say-so, exactly as they do in
    /// the close.
    private var pendingSaveTasks: [String: Task<Void, Never>] = [:]

    init(sector: LifeSector, calendar: Calendar = .current) {
        self.sector = sector
        self.calendar = calendar
    }

    var questions: [CheckInQuestion] { CheckInQuestion.questions(for: sector) }

    func attach(_ context: ModelContext) { self.context = context }

    func load(now: Date = .now) {
        guard let context else { return }
        let month = Date.startOfMonth(now, calendar: calendar)
        let store = SectorStore(context: context, calendar: calendar)

        answers = [:]
        for stored in (try? store.answers(sector: sector, month: month)) ?? [] {
            answers[stored.questionID] = stored.answer
        }

        let window = MonthWindow(for: month, calendar: calendar)
        let progress = MonthProgress(window: window, now: now, calendar: calendar)
        remainingDays = progress.remainingDays

        let inputs = (try? MonthInputsLoader.load(
            context: context, month: month, now: now, calendar: calendar
        )) ?? MonthInputs()
        usesDefaultTargets = inputs.targets == .default

        band = SectorBand.band(
            for: sector, inputs: inputs, progress: progress,
            answers: answers, calendar: calendar
        )
        levers = Leverage.ranked(
            for: sector, inputs: inputs, progress: progress,
            answers: answers, calendar: calendar
        )
    }

    /// Records an answer against the month being lived. The close reads the
    /// same rows back and lets them be revised: `SectorStore.saveAnswer`
    /// upserts, one answer per question per sector-month.
    func answer(_ question: CheckInQuestion, with value: String) {
        answers[question.id] = value
        if AnswerPersistence.isImmediate(question) {
            persist(question, value: value)
            load()
        } else {
            pendingSaveTasks[question.id]?.cancel()
            pendingSaveTasks[question.id] = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                self?.persist(question, value: value)
            }
        }
    }

    private func persist(_ question: CheckInQuestion, value: String) {
        guard let context else { return }
        let month = Date.startOfMonth(.now, calendar: calendar)
        try? SectorStore(context: context, calendar: calendar).saveAnswer(
            sector: sector, month: month, questionID: question.id, answer: value
        )
    }
}

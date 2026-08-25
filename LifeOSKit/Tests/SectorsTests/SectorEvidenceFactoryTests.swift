import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct SectorEvidenceFactoryTests {

    private func day(steps: Int? = 9000, sleep: Int? = 450, exercise: Int? = 40, water: Double? = 2600) -> DayReading {
        DayReading(steps: steps, sleepMinutes: sleep, exerciseMinutes: exercise, waterML: water)
    }

    // MARK: - Routing

    @Test func bodyRoutesToBodyScorer() {
        var inputs = MonthInputs()
        inputs.readings = Array(repeating: day(), count: 10)
        inputs.targets = .default
        let evidence = SectorEvidenceFactory.evidence(for: .body, inputs: inputs, answers: [:])
        #expect(evidence.rows.contains { $0.label == "days on target" })
    }

    @Test func moneyRoutesToMoneyScorer() {
        var inputs = MonthInputs()
        inputs.amounts = [1000, -400]
        let evidence = SectorEvidenceFactory.evidence(for: .money, inputs: inputs, answers: [:])
        #expect(evidence.rows.contains { $0.label == "kept of what came in" })
    }

    @Test func missionRoutesToMissionScorer() {
        var inputs = MonthInputs()
        inputs.planStatuses = [.done, .todo]
        let evidence = SectorEvidenceFactory.evidence(for: .mission, inputs: inputs, answers: [:])
        #expect(evidence.rows.contains { $0.label == "goals moved" })
    }

    @Test func growthRoutesToGrowthScorer() {
        var inputs = MonthInputs()
        inputs.goalStatuses = [.done]
        let evidence = SectorEvidenceFactory.evidence(for: .growth, inputs: inputs, answers: [:])
        #expect(evidence.rows.contains { $0.label == "goals completed" })
    }

    @Test func mindRoutesToJournalScorer() {
        var inputs = MonthInputs()
        inputs.journalDates = [Date()]
        inputs.daysInMonth = 30
        let evidence = SectorEvidenceFactory.evidence(for: .mind, inputs: inputs, answers: [:])
        #expect(evidence.rows.contains { $0.label == "days written" })
    }

    @Test func familyRoutesToCheckInScorer() {
        let answers = ["family.contact": "a lot"]
        let evidence = SectorEvidenceFactory.evidence(for: .family, inputs: MonthInputs(), answers: answers)
        #expect(evidence.rows.contains { $0.label == "how much did you speak with family?" })
    }

    @Test func romanceRoutesToCheckInScorer() {
        let answers = ["romance.state": "together"]
        let evidence = SectorEvidenceFactory.evidence(for: .romance, inputs: MonthInputs(), answers: answers)
        #expect(evidence.rows.contains { $0.label == "where are things?" })
    }

    @Test func friendsRoutesToCheckInScorer() {
        let answers = ["friends.seen": "a lot"]
        let evidence = SectorEvidenceFactory.evidence(for: .friends, inputs: MonthInputs(), answers: answers)
        #expect(evidence.rows.contains { $0.label == "how often did you see friends?" })
    }

    @Test func soulRoutesToBothJournalAndCheckIn() {
        var inputs = MonthInputs()
        inputs.journalDates = [Date()]
        inputs.daysInMonth = 30
        let answers = ["soul.settled": "a lot"]
        let evidence = SectorEvidenceFactory.evidence(for: .soul, inputs: inputs, answers: answers)
        #expect(evidence.rows.contains { $0.label == "days written" })
        #expect(evidence.rows.contains { $0.label == "how settled did you feel?" })
    }

    // MARK: - Empty input proposes nil everywhere

    @Test func emptyMonthInputsProposesNothingForEverySector() {
        for sector in LifeSector.allCases {
            let evidence = SectorEvidenceFactory.evidence(for: sector, inputs: MonthInputs(), answers: [:])
            #expect(evidence.proposedScore == nil, "\(sector.rawValue) proposed \(String(describing: evidence.proposedScore)) instead of nil")
        }
    }

    // MARK: - Growth targets rule

    @Test func allFourAveragesMeetingGoalGivesFourOfFour() {
        var inputs = MonthInputs()
        inputs.readings = Array(repeating: day(), count: 20)
        inputs.targets = .default
        let evidence = SectorEvidenceFactory.evidence(for: .growth, inputs: inputs, answers: [:])
        let row = evidence.rows.first { $0.label == "targets met" }
        #expect(row?.value == "4/4")
    }

    @Test func twoOfFourMeetingGoalGivesTwoOfFour() {
        var inputs = MonthInputs()
        inputs.readings = Array(repeating: day(steps: 9000, sleep: 450, exercise: 5, water: 500), count: 20)
        inputs.targets = .default
        let evidence = SectorEvidenceFactory.evidence(for: .growth, inputs: inputs, answers: [:])
        let row = evidence.rows.first { $0.label == "targets met" }
        #expect(row?.value == "2/4")
    }

    /// Water never logged all month: it drops out of the denominator rather
    /// than counting as a miss, so three tracked metrics all on target read
    /// as 3/3, not 3/4.
    @Test func aMetricNeverLoggedReducesTheTotalRatherThanCountingAsAMiss() {
        var inputs = MonthInputs()
        inputs.readings = Array(repeating: day(steps: 9000, sleep: 450, exercise: 40, water: nil), count: 20)
        inputs.targets = .default
        let evidence = SectorEvidenceFactory.evidence(for: .growth, inputs: inputs, answers: [:])
        let row = evidence.rows.first { $0.label == "targets met" }
        #expect(row?.value == "3/3")
    }

    @Test func nothingLoggedAtAllProducesNoTargetsRow() {
        var inputs = MonthInputs()
        inputs.readings = []
        inputs.targets = .default
        let evidence = SectorEvidenceFactory.evidence(for: .growth, inputs: inputs, answers: [:])
        #expect(!evidence.rows.contains { $0.label == "targets met" })
    }

    @Test func blankReadingsProduceNoTargetsRowEither() {
        var inputs = MonthInputs()
        let blank = DayReading(steps: nil, sleepMinutes: nil, exerciseMinutes: nil, waterML: nil)
        inputs.readings = Array(repeating: blank, count: 20)
        inputs.targets = .default
        let evidence = SectorEvidenceFactory.evidence(for: .growth, inputs: inputs, answers: [:])
        #expect(!evidence.rows.contains { $0.label == "targets met" })
    }

    // MARK: - Soul's merge

    @Test func soulMergesJournalAndCheckInRowsWithoutDoubleCounting() {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let journalDates = (0..<24).map { Calendar.current.date(byAdding: .day, value: $0, to: start)! }

        var combinedInputs = MonthInputs()
        combinedInputs.journalDates = journalDates
        combinedInputs.daysInMonth = 30
        let answers = ["soul.settled": "a fair amount", "soul.note": "a good month"]

        let combined = SectorEvidenceFactory.evidence(for: .soul, inputs: combinedInputs, answers: answers)

        let journalOnly = JournalScorer(
            sector: .soul, entryDates: journalDates, daysInMonth: 30, previousEntryCount: nil
        ).evidence()
        let checkInOnly = CheckInScorer(sector: .soul, answers: answers).evidence()

        // Every row from each source is present, and the row count is
        // exactly the sum of the two: nothing was dropped, and nothing was
        // added or merged into a combined row that would count evidence
        // twice.
        #expect(combined.rows.count == journalOnly.rows.count + checkInOnly.rows.count)
        for row in journalOnly.rows { #expect(combined.rows.contains(row)) }
        for row in checkInOnly.rows { #expect(combined.rows.contains(row)) }
    }

    @Test func soulWithOnlyJournalDataStillProposes() {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let journalDates = (0..<24).map { Calendar.current.date(byAdding: .day, value: $0, to: start)! }
        var inputs = MonthInputs()
        inputs.journalDates = journalDates
        inputs.daysInMonth = 30
        let evidence = SectorEvidenceFactory.evidence(for: .soul, inputs: inputs, answers: [:])
        #expect(evidence.proposedScore != nil)
    }

    @Test func soulWithOnlyCheckInAnswersStillProposes() {
        let evidence = SectorEvidenceFactory.evidence(
            for: .soul, inputs: MonthInputs(), answers: ["soul.settled": "a lot"]
        )
        #expect(evidence.proposedScore != nil)
    }

    // MARK: - The habit tick rate helper

    @Test func habitTickRateFlattensAcrossHabits() {
        let rate = SectorEvidenceFactory.habitTickRate(perHabitTicks: [
            [true, true, false, false],
            [true, false],
        ])
        #expect(rate == 0.5)
    }

    @Test func noHabitDaysProduceNoRate() {
        #expect(SectorEvidenceFactory.habitTickRate(perHabitTicks: []) == nil)
        #expect(SectorEvidenceFactory.habitTickRate(perHabitTicks: [[]]) == nil)
    }
}

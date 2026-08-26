import Testing
import Foundation
import SwiftData
import Persistence
@testable import Insights

@Suite @MainActor struct CoachTaskTests {

    private func digest() throws -> MetricsDigest {
        let container = try LifeOSContainer.make(inMemory: true)
        let store = MetricsStore(context: ModelContext(container))
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_770_000_000))
        try store.upsert(date: day) {
            $0.steps = 8_000
            $0.whoopRecoveryPct = 62
            $0.hrvMs = 41.2
        }
        return MetricsDigest.from(
            metrics: try store.metrics(from: day, to: day), sleeps: [], workouts: []
        )
    }

    @Test func theBriefRunsOnDeviceByDefault() {
        #expect(BriefTask().floor == .onDevice)
    }

    @Test func chatRunsOnDeviceByDefault() {
        #expect(AnswerTask(question: "why is my recovery low?").floor == .onDevice)
    }

    @Test func theBriefPromptCarriesTheDigest() throws {
        let prompt = BriefTask().prompt(try digest(), for: .onDevice)

        #expect(prompt.contains("62"))
        #expect(prompt.contains("8000"))
    }

    @Test func aChatPromptCarriesBothTheQuestionAndTheDigest() throws {
        let prompt = AnswerTask(question: "how did I sleep?")
            .prompt(ContextBundle(digest: try digest()), for: .onDevice)

        #expect(prompt.contains("how did I sleep?"))
        #expect(prompt.contains("62"))
    }

    /// Instructions are cacheable prefix and must not vary per request; a
    /// digest baked into them would defeat that and change every call.
    @Test func instructionsDoNotVaryWithTheData() throws {
        let task = BriefTask()
        #expect(task.instructions == BriefTask().instructions)
        #expect(task.instructions.contains("62") == false)
    }

    @Test func theOffDeviceRenderCarriesNoRawSeries() throws {
        let bundle = ContextBundle(digest: try digest())
        let task = AnswerTask(question: "How did I sleep?")
        let local = task.prompt(bundle, for: .onDevice)
        let remote = task.prompt(bundle, for: .offDevice)
        #expect(local != remote)
        // The on-device baseline includes HRV; the off-device render must not.
        #expect(!remote.contains("hrv"))
    }

    @Test func theAnswerTaskRendersTheWholeBundleOffDevice() {
        let bundle = ContextBundle(
            digest: MetricsDigest.from(metrics: [], sleeps: [], workouts: []),
            money: ContextBundle.Money(income: 100, expenses: 50, savingsRate: nil,
                                       netWorth: nil, recent: []),
            sectors: [ContextBundle.Sector(name: "Body", score: 8, delta: nil)],
            firstName: nil
        )
        let task = AnswerTask(question: "Am I saving?")
        let remote = task.prompt(bundle, for: .offDevice)
        #expect(remote.contains("income 100"))
        #expect(remote.contains("Body 8"))
        #expect(remote.contains("Am I saving?"))
    }
}

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
        let prompt = BriefTask().prompt(try digest())

        #expect(prompt.contains("62"))
        #expect(prompt.contains("8000"))
    }

    @Test func aChatPromptCarriesBothTheQuestionAndTheDigest() throws {
        let prompt = AnswerTask(question: "how did I sleep?").prompt(try digest())

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
}

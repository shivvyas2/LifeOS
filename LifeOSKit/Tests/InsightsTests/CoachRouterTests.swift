import Testing
import Foundation
import FoundationModels
@testable import Insights

/// A stand-in engine, so the router's decisions can be tested without a model.
private struct StubEngine: Engine {
    let outcome: @Sendable () throws -> DailyBrief

    func run<T: CoachTask>(_ task: T, _ digest: MetricsDigest) async throws -> T.Output {
        try outcome() as! T.Output
    }
}

@Suite struct CoachRouterTests {

    private let empty = MetricsDigest(
        days: [],
        averages: MetricsDigest.Averages(recoveryPct: nil, sleepMinutes: nil, steps: nil)
    )

    private let brief = DailyBrief(headline: "Fine.", observations: ["a", "b"])
    private let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")

    private func router(
        onDevice: @escaping @Sendable () throws -> DailyBrief,
        remote: (@Sendable () throws -> DailyBrief)? = nil,
        availability: ModelAvailability = .available
    ) -> CoachRouter {
        CoachRouter(
            onDevice: StubEngine(outcome: onDevice),
            remote: remote.map { StubEngine(outcome: $0) },
            availability: { availability }
        )
    }

    @Test func aSuccessfulLocalRunIsAnswered() async {
        let result = await router(onDevice: { self.brief }).run(BriefTask(), empty)
        #expect(result == .answered(brief))
    }

    /// With no remote engine — the shape this app ships in before the cloud
    /// tier exists — an escalating failure is unavailable, not a crash.
    @Test func anEscalationWithNoRemoteEngineIsUnavailable() async {
        let result = await router(
            onDevice: { throw LanguageModelSession.GenerationError.exceededContextWindowSize(self.context) }
        ).run(BriefTask(), empty)

        #expect(result == .unavailable)
    }

    @Test func anEscalationReachesTheRemoteEngineWhenThereIsOne() async {
        let cloud = DailyBrief(headline: "From the cloud.", observations: ["a", "b"])
        let result = await router(
            onDevice: { throw LanguageModelSession.GenerationError.exceededContextWindowSize(self.context) },
            remote: { cloud }
        ).run(BriefTask(), empty)

        #expect(result == .answered(cloud))
    }

    @Test func aRefusalIsSurfacedEvenWhenARemoteEngineIsAvailable() async {
        let refusal = LanguageModelSession.GenerationError.Refusal(transcriptEntries: [])
        let result = await router(
            onDevice: { throw LanguageModelSession.GenerationError.refusal(refusal, self.context) },
            remote: { DailyBrief(headline: "Should never be reached.", observations: ["a", "b"]) }
        ).run(BriefTask(), empty)

        guard case .refused = result else {
            Issue.record("a refusal must never be answered by the cloud, got \(result)")
            return
        }
    }

    @Test func anIneligibleDeviceGoesStraightToTheCloud() async {
        let cloud = DailyBrief(headline: "From the cloud.", observations: ["a", "b"])
        let result = await router(
            onDevice: { Issue.record("the on-device engine must not be called"); return self.brief },
            remote: { cloud },
            availability: .unavailablePermanently
        ).run(BriefTask(), empty)

        #expect(result == .answered(cloud))
    }

    /// The policy calls a concurrency failure our own bug. This is the router
    /// honouring that: however many times it fails, it must not reach for a
    /// paid engine, even when one is sitting right there.
    @Test func ourOwnConcurrencyBugNeverReachesThePaidEngine() async {
        let result = await router(
            onDevice: { throw LanguageModelSession.GenerationError.concurrentRequests(self.context) },
            remote: {
                Issue.record("a concurrency bug of ours must never be billed to the cloud")
                return self.brief
            }
        ).run(BriefTask(), empty)

        #expect(result == .unavailable)
    }

    @Test func anIneligibleDeviceWithNoCloudIsUnavailable() async {
        let result = await router(
            onDevice: { self.brief },
            availability: .unavailablePermanently
        ).run(BriefTask(), empty)

        #expect(result == .unavailable)
    }
}

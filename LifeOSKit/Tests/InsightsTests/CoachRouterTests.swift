import Testing
import Foundation
import FoundationModels
@testable import Insights

/// A synchronous call counter, because the availability closure the router
/// takes is not async and so cannot await an actor.
private final class ReadCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    /// Returns how many calls came before this one.
    func next() -> Int {
        lock.withLock {
            defer { count += 1 }
            return count
        }
    }
}

/// A stand-in engine, so the router's decisions can be tested without a model.
private struct StubEngine: Engine {
    let outcome: @Sendable () throws -> DailyBrief

    func run<T: CoachTask>(_ task: T, _ context: T.Context) async throws -> T.Output {
        try outcome() as! T.Output
    }
}

@Suite struct CoachRouterTests {

    private let empty = MetricsDigest(
        days: [],
        averages: MetricsDigest.Averages(
            recoveryPct: nil, sleepMinutes: nil, steps: nil,
            hrvMs: nil, restingHR: nil, strain: nil, sleepDebtMinutes: nil
        )
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
    /// `assetsUnavailable` is used here rather than
    /// `exceededContextWindowSize`, which now maps to `.tooLarge`; see
    /// `anOversizedPromptIsReportedAsSuchRatherThanAsAMissingModel` below.
    @Test func anEscalationWithNoRemoteEngineIsUnavailable() async {
        let result = await router(
            onDevice: { throw LanguageModelSession.GenerationError.assetsUnavailable(self.context) }
        ).run(BriefTask(), empty)

        #expect(result == .unavailable)
    }

    /// An oversized prompt is our fault and is fixed by sending less. Telling
    /// the user their device lacks Apple Intelligence sends them to a settings
    /// screen that will not help.
    @Test func anOversizedPromptIsReportedAsSuchRatherThanAsAMissingModel() async throws {
        let router = router(
            onDevice: { throw LanguageModelSession.GenerationError.exceededContextWindowSize(self.context) },
            remote: nil
        )

        let result = await router.run(BriefTask(), empty)

        #expect(result == .tooLarge)
    }

    @Test func anEscalationReachesTheRemoteEngineWhenThereIsOne() async {
        let cloud = DailyBrief(headline: "From the cloud.", observations: ["a", "b"])
        let result = await router(
            onDevice: { throw LanguageModelSession.GenerationError.exceededContextWindowSize(self.context) },
            remote: { cloud }
        ).run(BriefTask(), empty)

        #expect(result == .answered(cloud))
    }

    /// A refusal is an answer. Falling through to the other engine would be a
    /// way around it rather than a second opinion, so whichever tier refuses,
    /// the refusal stands.
    @Test func aRemoteRefusalIsNeverRetriedOnDevice() async {
        let result = await router(
            onDevice: {
                Issue.record("a refusal must not be routed around")
                return self.brief
            },
            remote: { throw RemoteEngineError.refused("not something I can help with") }
        ).run(BriefTask(), empty)

        guard case .refused = result else {
            Issue.record("expected the refusal to stand, got \(result)")
            return
        }
    }

    @Test func aLocalRefusalStandsWhenTheDeviceIsTheOnlyTier() async {
        let refusal = LanguageModelSession.GenerationError.Refusal(transcriptEntries: [])
        let result = await router(
            onDevice: { throw LanguageModelSession.GenerationError.refusal(refusal, self.context) }
        ).run(BriefTask(), empty)

        guard case .refused = result else {
            Issue.record("expected a refusal, got \(result)")
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

    /// A concurrency failure is contention on a local session, and a second
    /// local attempt is the only thing that can help. With the cloud tried
    /// first this is now reached only as the fallback path, but the rule is
    /// unchanged: contention retries locally rather than escalating.
    @Test func contentionRetriesLocallyRatherThanEscalating() async {
        let attempts = ReadCount()
        let result = await router(
            onDevice: {
                if attempts.next() == 0 {
                    throw LanguageModelSession.GenerationError.concurrentRequests(self.context)
                }
                return self.brief
            },
            remote: { throw RemoteEngineError.exhausted }
        ).run(BriefTask(), empty)

        // Degraded, not answered: the cloud was wanted and the device replied.
        #expect(result == .degraded(brief))
    }

    /// The user can switch Apple Intelligence off while the app is
    /// backgrounded, so availability is re-read on every request rather than
    /// remembered. With the cloud unreachable, the first call falls back to the
    /// device and the second has no tier left at all.
    @Test func availabilityIsReReadRatherThanTrustedForeverOnceAvailable() async {
        let reads = ReadCount()
        let router = CoachRouter(
            onDevice: StubEngine(outcome: { self.brief }),
            remote: StubEngine(outcome: { throw RemoteEngineError.exhausted }),
            availability: { reads.next() == 0 ? .available : .unavailablePermanently }
        )

        let first = await router.run(BriefTask(), empty)
        let second = await router.run(BriefTask(), empty)

        #expect(first == .degraded(brief))
        #expect(second == .unavailable)
    }

    /// The whole point of the inversion: when both tiers can answer, the
    /// better one does.
    @Test func theCloudAnswersWhenBothTiersCould() async {
        let cloud = DailyBrief(headline: "From the cloud.", observations: ["a", "b"])
        let result = await router(
            onDevice: {
                Issue.record("the device must not be asked while the cloud can answer")
                return self.brief
            },
            remote: { cloud }
        ).run(BriefTask(), empty)

        #expect(result == .answered(cloud))
    }

    /// A spent allowance is not an error. The device picks it up, and the
    /// screen is told the answer came from the smaller model.
    @Test func aSpentAllowanceFallsBackToTheDeviceAsDegraded() async {
        let result = await router(
            onDevice: { self.brief },
            remote: { throw RemoteEngineError.exhausted }
        ).run(BriefTask(), empty)

        #expect(result == .degraded(brief))
    }

    @Test func anIneligibleDeviceWithNoCloudIsUnavailable() async {
        let result = await router(
            onDevice: { self.brief },
            availability: .unavailablePermanently
        ).run(BriefTask(), empty)

        #expect(result == .unavailable)
    }
}

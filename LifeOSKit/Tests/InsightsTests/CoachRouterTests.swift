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

    /// A concurrency failure is contention, and no paid model fixes
    /// contention. However many times it fails, the router must not reach for
    /// a paid engine, even when one is sitting right there.
    @Test func aContentionFailureNeverReachesThePaidEngine() async {
        let result = await router(
            onDevice: { throw LanguageModelSession.GenerationError.concurrentRequests(self.context) },
            remote: {
                Issue.record("a concurrency bug of ours must never be billed to the cloud")
                return self.brief
            }
        ).run(BriefTask(), empty)

        #expect(result == .unavailable)
    }

    /// The user can switch Apple Intelligence off while the app is
    /// backgrounded. A router that remembered `.available` would keep taking
    /// the local path, fail, escalate, and bill every later request to the
    /// cloud, so availability is re-read on every request.
    @Test func availabilityIsReReadRatherThanTrustedForeverOnceAvailable() async {
        let cloud = DailyBrief(headline: "From the cloud.", observations: ["a", "b"])
        let reads = ReadCount()
        let router = CoachRouter(
            onDevice: StubEngine(outcome: { self.brief }),
            remote: StubEngine(outcome: { cloud }),
            availability: { reads.next() == 0 ? .available : .unavailablePermanently }
        )

        let first = await router.run(BriefTask(), empty)
        let second = await router.run(BriefTask(), empty)

        #expect(first == .answered(brief))
        #expect(second == .answered(cloud))
    }

    @Test func anIneligibleDeviceWithNoCloudIsUnavailable() async {
        let result = await router(
            onDevice: { self.brief },
            availability: .unavailablePermanently
        ).run(BriefTask(), empty)

        #expect(result == .unavailable)
    }
}

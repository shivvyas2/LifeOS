import Foundation
import FoundationModels

/// What the UI renders. Failures are states, not thrown errors, because every
/// one of them has a different right answer on screen.
public enum CoachResult<Output: Sendable>: Sendable {
    /// Served at or above the tier the task asked for.
    case answered(Output)
    /// The on-device model answered where the cloud was wanted. Say so — a
    /// weekly review that silently ran locally reads as the coach getting
    /// worse for no reason. Never mentions the allowance.
    ///
    /// Nothing in Plan 1 produces this: escalating *up* to the cloud is the
    /// router working, not degrading. Plan 2 produces it, when a cloud-floor
    /// task falls back because the allowance is spent.
    case degraded(Output)
    /// A safety refusal, with its explanation. Offers no retry.
    case refused(String)
    /// The monthly allowance is spent and this task needs the cloud.
    /// Produced by Plan 2; declared here so the UI seam is complete.
    case exhausted
    /// The cloud path cannot run right now. Transient; retry is the right
    /// affordance, and the allowance is never mentioned.
    case unavailable
}

extension CoachResult: Equatable where Output: Equatable {}

/// Picks a tier, and decides what a failure means.
///
/// An actor because it holds mutable state — `cachedAvailability` — and that
/// alone is reason enough. It is deliberately *not* a serialisation point for
/// model calls: an actor releases its executor at every `await`, so two
/// concurrent `run(_:_:)` calls do interleave with requests in flight. That is
/// the behaviour we want. Making a chat turn queue behind a daily brief would
/// be worse than anything it prevents.
public actor CoachRouter {

    private let onDevice: any Engine
    private let remote: (any Engine)?
    private let availability: @Sendable () -> ModelAvailability
    private var cachedAvailability: ModelAvailability?

    public init(
        onDevice: any Engine,
        remote: (any Engine)?,
        availability: @escaping @Sendable () -> ModelAvailability = {
            ModelAvailability.from(SystemLanguageModel.default.availability)
        }
    ) {
        self.onDevice = onDevice
        self.remote = remote
        self.availability = availability
    }

    public func run<T: CoachTask>(
        _ task: T,
        _ digest: MetricsDigest
    ) async -> CoachResult<T.Output> {
        if case .cloud = task.floor {
            return await runRemote(task, digest)
        }
        guard currentAvailability() == .available else {
            return await runRemote(task, digest)
        }
        return await runLocal(task, digest, retriesLeft: 1)
    }

    private func runLocal<T: CoachTask>(
        _ task: T,
        _ digest: MetricsDigest,
        retriesLeft: Int
    ) async -> CoachResult<T.Output> {
        do {
            return .answered(try await onDevice.run(task, digest))
        } catch let error as LanguageModelSession.GenerationError {
            switch EscalationPolicy.disposition(for: error) {
            case .escalate:
                return await runRemote(task, digest)

            case .retryLocally:
                // Never reaches the cloud, however many times it fails. This
                // error is contention on a local session, and a paid model
                // fixes nothing about contention — it only bills for it. A
                // second local attempt, once the contending request has
                // finished, is the only thing that can help.
                guard retriesLeft > 0 else { return .unavailable }
                return await runLocal(task, digest, retriesLeft: retriesLeft - 1)

            case .retryThenEscalate:
                guard retriesLeft > 0 else { return await runRemote(task, digest) }
                return await runLocal(task, digest, retriesLeft: retriesLeft - 1)

            case .surface:
                return .refused(error.localizedDescription)

            case .programmerError:
                assertionFailure("schema is unusable on-device: \(error)")
                return .unavailable
            }
        } catch {
            return .unavailable
        }
    }

    private func runRemote<T: CoachTask>(
        _ task: T,
        _ digest: MetricsDigest
    ) async -> CoachResult<T.Output> {
        // Until Plan 2 lands there is no remote engine, and that is a real
        // shipping state rather than a stub: the coach works on-device and
        // says so when it cannot reach further.
        guard let remote else { return .unavailable }
        do {
            return .answered(try await remote.run(task, digest))
        } catch {
            return .unavailable
        }
    }

    /// Only `.unavailablePermanently` is remembered. It means the hardware is
    /// ineligible, which cannot change while the process is alive.
    ///
    /// Everything else is re-read on every request, `.available` included.
    /// Apple Intelligence can be switched off while the app is backgrounded,
    /// and a router that still believed `.available` would take the local path,
    /// throw `.assetsUnavailable`, escalate, and bill every remaining request
    /// of the process to the cloud — over a condition one property read
    /// catches. That read is the whole cost of being right.
    private func currentAvailability() -> ModelAvailability {
        if cachedAvailability == .unavailablePermanently {
            return .unavailablePermanently
        }
        let fresh = availability()
        cachedAvailability = fresh
        return fresh
    }
}

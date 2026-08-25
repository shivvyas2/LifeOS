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
/// An actor because `.concurrentRequests` is a real on-device failure mode:
/// serialising here is cheaper than handling it, and the escalation policy
/// treats that error as our bug precisely because this type is supposed to
/// prevent it.
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
                // error means the router failed to serialise, and billing a
                // cloud call for our own race condition is exactly what the
                // policy exists to prevent.
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

    private func currentAvailability() -> ModelAvailability {
        if let cached = cachedAvailability, cached.isWorthReChecking == false {
            return cached
        }
        let fresh = availability()
        cachedAvailability = fresh
        return fresh
    }
}

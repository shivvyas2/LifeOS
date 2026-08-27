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
    /// The prompt did not fit and there is no larger tier to send it to.
    /// Distinct from `unavailable`, which means no model could run at all:
    /// this one is our fault and is fixed by sending less, not by the user
    /// changing a device setting.
    case tooLarge
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
    /// Read per request rather than captured, for the same reason availability
    /// is: it can be changed in Settings while a screen holding this router is
    /// still on screen.
    private let preference: @Sendable () -> TierPreference
    private var cachedAvailability: ModelAvailability?

    public init(
        onDevice: any Engine,
        remote: (any Engine)?,
        availability: @escaping @Sendable () -> ModelAvailability = {
            ModelAvailability.from(SystemLanguageModel.default.availability)
        },
        preference: @escaping @Sendable () -> TierPreference = { .automatic }
    ) {
        self.onDevice = onDevice
        self.remote = remote
        self.availability = availability
        self.preference = preference
    }

    /// The cloud answers first, and the device is the fallback.
    ///
    /// It used to be the other way round, on the reasoning that the free
    /// engine should be tried before the paid one. The reasoning was sound and
    /// the result was not: the on-device model is markedly weaker at the kind
    /// of question this app gets asked, so the common path was the worse
    /// answer and the better one only appeared when the weaker model failed
    /// outright, which it rarely does. Quality, not availability, is what
    /// should pick a tier.
    ///
    /// What keeps this affordable is that the remote engine is metered. A
    /// daily token cap lives on the server, and when it is spent this falls
    /// back to the device rather than to a bill or to an error. So the cost
    /// ceiling is enforced where it can actually be enforced, and the device
    /// stops being a permanent second-best and becomes what it is good at
    /// being: the thing that still works when the cloud will not.
    public func run<T: CoachTask>(
        _ task: T,
        _ context: T.Context
    ) async -> CoachResult<T.Output> {
        // The floor wins over the preference. A task that cannot run on the
        // device is not made to by choosing the device; it goes where it runs.
        if case .cloud = task.floor {
            return await runRemote(task, context)
        }

        // No remote engine configured at all: the device is the only tier.
        guard remote != nil else {
            guard currentAvailability() == .available else { return .unavailable }
            return await runLocal(task, context, retriesLeft: 1)
        }

        switch preference() {
        case .cloud:
            // No fallback on purpose. Someone who chose the stronger model
            // wants to be told when it did not answer, not quietly handed a
            // weaker answer that looks the same.
            return await runRemote(task, context)
        case .onDevice:
            guard currentAvailability() == .available else { return .unavailable }
            return await runLocal(task, context, retriesLeft: 1)
        case .automatic:
            break
        }

        switch await runRemote(task, context, fallback: .unavailable) {
        case .answered(let output):
            return .answered(output)
        case .refused(let reason):
            // The model answered and declined. A second model is not a second
            // opinion on a refusal, it is a way around one.
            return .refused(reason)
        case .exhausted, .unavailable, .tooLarge, .degraded:
            // Everything else is the cloud being unable to answer, which is
            // exactly what the device is for. Marked degraded so the screen can
            // say the answer came from the smaller model rather than letting it
            // read as the coach quietly getting worse.
            guard currentAvailability() == .available else { return .unavailable }
            switch await runLocal(task, context, retriesLeft: 1) {
            case .answered(let output): return .degraded(output)
            case let other:             return other
            }
        }
    }

    private func runLocal<T: CoachTask>(
        _ task: T,
        _ context: T.Context,
        retriesLeft: Int
    ) async -> CoachResult<T.Output> {
        do {
            return .answered(try await onDevice.run(task, context))
        } catch let error as LanguageModelSession.GenerationError {
            switch EscalationPolicy.disposition(for: error) {
            case .escalate:
                if case .exceededContextWindowSize = error {
                    return await runRemote(task, context, fallback: .tooLarge)
                }
                return await runRemote(task, context)

            case .retryLocally:
                // Never reaches the cloud, however many times it fails. This
                // error is contention on a local session, and a paid model
                // fixes nothing about contention — it only bills for it. A
                // second local attempt, once the contending request has
                // finished, is the only thing that can help.
                guard retriesLeft > 0 else { return .unavailable }
                return await runLocal(task, context, retriesLeft: retriesLeft - 1)

            case .retryThenEscalate:
                guard retriesLeft > 0 else { return await runRemote(task, context) }
                return await runLocal(task, context, retriesLeft: retriesLeft - 1)

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
        _ context: T.Context,
        fallback: CoachResult<T.Output> = .unavailable
    ) async -> CoachResult<T.Output> {
        // Until Plan 2 lands there is no remote engine, and that is a real
        // shipping state rather than a stub: the coach works on-device and
        // says so when it cannot reach further.
        guard let remote else { return fallback }
        do {
            return .answered(try await remote.run(task, context))
        } catch RemoteEngineError.exhausted {
            // Distinct from unavailable on purpose: the allowance is spent, so
            // the UI must not offer a retry that cannot succeed today.
            return .exhausted
        } catch RemoteEngineError.refused(let reason) {
            // The model answered; it declined. Surfacing that as a failure
            // would invite a retry of a question it will decline again.
            return .refused(reason)
        } catch {
            return fallback
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

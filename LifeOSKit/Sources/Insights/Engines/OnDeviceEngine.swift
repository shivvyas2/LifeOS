import FoundationModels

/// Apple's on-device model.
///
/// A session is created per call rather than stored: `LanguageModelSession` is
/// a non-`Sendable` final class, and `Engine` is `Sendable`. That is also the
/// right lifetime for one-shot tasks — a session carries a transcript, and a
/// brief has no conversation to remember.
public struct OnDeviceEngine: Engine {

    public init() {}

    public func run<T: CoachTask>(_ task: T, _ digest: MetricsDigest) async throws -> T.Output {
        let session = LanguageModelSession(instructions: task.instructions)
        let response = try await session.respond(
            to: task.prompt(digest),
            generating: T.Output.self
        )
        return response.content
    }
}

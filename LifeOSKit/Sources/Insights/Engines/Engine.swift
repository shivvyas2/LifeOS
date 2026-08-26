/// What both tiers look like from the router's side.
///
/// Deliberately one method. When iOS 27's `LanguageModelExecutor` ships, the
/// remote engine conforms to Apple's protocol instead and this one is deleted
/// without any caller changing.
///
/// A remote conformance must not build its request by calling
/// `task.prompt(context)` the way the on-device engine does: that method has
/// no audience parameter, so it always yields the on-device render, raw
/// Whoop series included. Threading an audience through `CoachTask.prompt`
/// (and this protocol, so `run` can say who the render is for) is a
/// prerequisite of a correct remote engine, not an optional refinement made
/// after the fact.
public protocol Engine: Sendable {
    func run<T: CoachTask>(_ task: T, _ context: T.Context) async throws -> T.Output
}

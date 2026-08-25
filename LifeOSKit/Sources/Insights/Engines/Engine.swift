/// What both tiers look like from the router's side.
///
/// Deliberately one method. When iOS 27's `LanguageModelExecutor` ships, the
/// remote engine conforms to Apple's protocol instead and this one is deleted
/// without any caller changing.
public protocol Engine: Sendable {
    func run<T: CoachTask>(_ task: T, _ digest: MetricsDigest) async throws -> T.Output
}

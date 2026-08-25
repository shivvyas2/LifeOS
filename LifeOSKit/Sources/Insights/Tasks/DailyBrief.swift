import FoundationModels

/// What the coach says about today.
///
/// Deliberately small. The on-device model has a context window measured in
/// thousands of tokens, and a wide schema is the fastest way to spend it on
/// structure instead of substance.
@Generable
public struct DailyBrief: Equatable, Sendable {

    @Guide(description: "One sentence on how the body is doing today. Plain and specific. No encouragement, no advice.")
    public var headline: String

    @Guide(
        description: "Concrete observations, each tied to a number that appears in the data. Never invent a figure.",
        .count(2...3)
    )
    public var observations: [String]
}

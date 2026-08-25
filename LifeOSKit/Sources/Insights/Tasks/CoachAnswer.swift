import FoundationModels

@Generable
public struct CoachAnswer: Equatable, Sendable {

    @Guide(description: "A direct answer in one short paragraph. No preamble, no restating the question.")
    public var answer: String
}

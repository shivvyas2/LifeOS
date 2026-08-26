import FoundationModels

@Generable
public struct CoachAnswer: Equatable, Sendable {

    @Guide(description: "A direct answer in one short paragraph. No preamble, no restating the question.")
    public var answer: String
}

/// Decoded from the Edge Function's JSON as well as generated on-device.
/// The conformance is declared in this file so Swift can synthesise it from
/// the stored properties; an extension in another file cannot.
extension CoachAnswer: Decodable {}

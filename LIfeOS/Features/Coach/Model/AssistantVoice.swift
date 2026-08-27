import Foundation

/// A voice the assistant can speak in.
///
/// Three, deliberately. A list of dozens is a settings screen nobody finishes
/// reading, and the difference between the fortieth voice and the thirty ninth
/// is not a choice anyone makes well. These are ElevenLabs' own stock voices,
/// whose identifiers are stable and public, so nothing here needs provisioning
/// against an account.
nonisolated enum AssistantVoice: String, CaseIterable, Identifiable, Sendable {
    case rachel
    case adam
    case sarah

    var id: String { rawValue }

    /// ElevenLabs' identifier. Stable across accounts: these are the shared
    /// stock voices rather than anything cloned or generated, so a build does
    /// not depend on a voice existing in one particular library.
    var voiceID: String {
        switch self {
        case .rachel: "21m00Tcm4TlvDq8ikWAM"
        case .adam:   "pNInz6obpgDQGcFmaJgB"
        case .sarah:  "EXAVITQu4vr4xnSDxMaL"
        }
    }

    var title: String {
        switch self {
        case .rachel: "Rachel"
        case .adam:   "Adam"
        case .sarah:  "Sarah"
        }
    }

    /// What the voice actually sounds like, rather than a label of who it is
    /// for. Someone choosing a voice is choosing a tone.
    var detail: String {
        switch self {
        case .rachel: "Warm and even, a little lower"
        case .adam:   "Steady and plain, no lift at the end"
        case .sarah:  "Brighter and quicker, softer edges"
        }
    }

    static let `default` = AssistantVoice.rachel

    /// Spoken replies are off until asked for. A coach that starts talking
    /// because an answer arrived, in a room the phone knows nothing about, is
    /// a worse default than silence.
    static let enabledKey = "assistantSpeaksReplies"
    static let voiceKey = "assistantVoice"
}

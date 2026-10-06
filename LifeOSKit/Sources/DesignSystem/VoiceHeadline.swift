import Foundation

/// What the voice screen is doing, as one state. The screen has a phase
/// and a player that can both be true at once (the phase is `answered`
/// while the reply is still being read); this collapses them in the order
/// that matters to the person listening.
public enum VoiceState: Hashable, Sendable {
    case idle, listening, thinking, speaking

    public static func from(isListening: Bool, isThinking: Bool, isSpeaking: Bool) -> VoiceState {
        if isSpeaking { return .speaking }
        if isListening { return .listening }
        if isThinking { return .thinking }
        return .idle
    }
}

/// The voice screen's masthead by state. A value so the wording is tested.
public struct VoiceHeadline: Equatable, Sendable {
    public let eyebrow: String
    public let title: String
    public let detail: String

    public init(eyebrow: String, title: String, detail: String) {
        self.eyebrow = eyebrow; self.title = title; self.detail = detail
    }

    /// The eyebrow names the state, not the screen: the header above the
    /// masthead already says "Voice conversation", and two lines saying the
    /// same thing a few points apart read as a mistake.
    public static func make(_ state: VoiceState) -> VoiceHeadline {
        switch state {
        case .idle:
            return VoiceHeadline(eyebrow: "Ready", title: "A moment for you",
                                 detail: "Tap the microphone whenever you're ready.")
        case .listening:
            return VoiceHeadline(eyebrow: "Listening", title: "I'm listening",
                                 detail: "Speak naturally. I'll follow along.")
        case .thinking:
            return VoiceHeadline(eyebrow: "Thinking", title: "Connecting the dots…",
                                 detail: "Making sense of your question.")
        case .speaking:
            return VoiceHeadline(eyebrow: "Speaking", title: "Let's talk it through",
                                 detail: "Your answer is here to read, too.")
        }
    }
}

/// The calendar assistant's masthead. The support line is the one piece
/// that changes: it must never tell a connected person to connect.
public struct AssistantHeadline: Equatable, Sendable {
    public let eyebrow: String
    public let title: String
    public let detail: String

    public init(eyebrow: String, title: String, detail: String) {
        self.eyebrow = eyebrow; self.title = title; self.detail = detail
    }

    public static func make(connected: Bool) -> AssistantHeadline {
        AssistantHeadline(
            eyebrow: "Calendar assistant",
            title: "Make room for your day",
            detail: connected
                ? "Ask about your schedule, or tell me to move something."
                : "Connect your calendar so I can see your schedule."
        )
    }
}

import Testing
@testable import DesignSystem

@Suite struct VoiceHeadlineTests {
    @Test func titlesByState() {
        #expect(VoiceHeadline.make(.idle).title == "A moment for you")
        #expect(VoiceHeadline.make(.idle).detail == "Tap the microphone whenever you're ready.")
        #expect(VoiceHeadline.make(.listening).title == "I'm listening")
        #expect(VoiceHeadline.make(.listening).detail == "Speak naturally. I'll follow along.")
        #expect(VoiceHeadline.make(.thinking).title == "Connecting the dots…")
        #expect(VoiceHeadline.make(.thinking).detail == "Making sense of your question.")
        #expect(VoiceHeadline.make(.speaking).title == "Let's talk it through")
        #expect(VoiceHeadline.make(.speaking).detail == "Your answer is here to read, too.")
        // The header already says "Voice conversation"; the masthead's eyebrow
        // names the state so the two lines never repeat each other.
        #expect(VoiceHeadline.make(.idle).eyebrow == "Ready")
        #expect(VoiceHeadline.make(.listening).eyebrow == "Listening")
        #expect(VoiceHeadline.make(.thinking).eyebrow == "Thinking")
        #expect(VoiceHeadline.make(.speaking).eyebrow == "Speaking")
    }

    @Test func speakingWinsOverAnswered() {
        // The screen maps its phase and its player to one state; the player
        // speaking is the state that matters, whatever the phase says.
        #expect(VoiceState.from(isListening: false, isThinking: false, isSpeaking: true) == .speaking)
        #expect(VoiceState.from(isListening: true, isThinking: false, isSpeaking: false) == .listening)
        #expect(VoiceState.from(isListening: false, isThinking: true, isSpeaking: false) == .thinking)
        #expect(VoiceState.from(isListening: false, isThinking: false, isSpeaking: false) == .idle)
    }
}

@Suite struct AssistantHeadlineTests {
    @Test func supportLineFollowsConnection() {
        let connected = AssistantHeadline.make(connected: true)
        #expect(connected.eyebrow == "Calendar assistant")
        #expect(connected.title == "Make room for your day")
        #expect(connected.detail == "Ask about your schedule, or tell me to move something.")
        let not = AssistantHeadline.make(connected: false)
        #expect(not.detail == "Connect your calendar so I can see your schedule.")
        #expect(!not.detail.isEmpty && not.detail != connected.detail)
    }
}

import Foundation

/// What Apple's speech recognizer is for on a given turn.
///
/// There are two transcribers and only one of them can own the sentence.
/// ElevenLabs Scribe transcribes a clip that is uploaded once the turn is
/// over, which is accurate but cannot show a word while someone is still
/// speaking. Apple's recognizer reports partial results as they are heard,
/// which is what makes the screen feel alive.
///
/// So when there is a Scribe key both run, with different jobs: Scribe
/// produces the sentence, Apple only draws it. Getting that split wrong fails
/// quietly, which is why it is a value type here rather than a pair of
/// booleans in an audio callback. Let Apple emit its final as well and the two
/// transcripts race, so the answer comes back to whichever finished first
/// rather than to the better one, intermittently and invisibly.
public struct SpeechCapturePlan: Equatable, Sendable {

    public enum AppleRole: Equatable, Sendable {
        /// Apple produces the sentence that gets sent. No Scribe key.
        case transcriber
        /// Scribe produces the sentence; Apple only puts words on screen.
        case liveTextOnly
        /// Apple does not run: refused, or unavailable on this device.
        case off
    }

    public let appleRole: AppleRole
    public let hasScribeKey: Bool
    private let supportsOnDeviceRecognition: Bool

    public init(
        hasScribeKey: Bool,
        speechAuthorized: Bool,
        recognizerAvailable: Bool,
        supportsOnDeviceRecognition: Bool
    ) {
        self.hasScribeKey = hasScribeKey
        self.supportsOnDeviceRecognition = supportsOnDeviceRecognition
        // Refused and unavailable are the same fact to everything downstream:
        // there is no recognizer to run.
        let appleUsable = speechAuthorized && recognizerAvailable
        switch (appleUsable, hasScribeKey) {
        case (false, _):    appleRole = .off
        case (true, true):  appleRole = .liveTextOnly
        case (true, false): appleRole = .transcriber
        }
    }

    /// Whether Apple's final result is the sentence to send.
    public var emitsFinalTranscript: Bool { appleRole == .transcriber }

    /// Whether a recognizer failure should end the turn.
    ///
    /// False on the Scribe path on purpose. There, a recognizer that dies has
    /// cost the words under the waveform and nothing else, and tearing down a
    /// recording still in progress would turn a cosmetic failure into a lost
    /// sentence.
    public var failureEndsTheTurn: Bool { appleRole == .transcriber }

    /// Whether the turn can proceed at all.
    ///
    /// Refusing speech recognition is only fatal when Apple was the only
    /// transcriber. With a Scribe key the turn goes ahead silently.
    public var canListen: Bool { hasScribeKey || appleRole == .transcriber }

    /// Whether to pin recognition to the device.
    ///
    /// Only for the display-only role, and only where the device can. The clip
    /// already goes to one vendor, and it need not go to a second merely to
    /// show someone the words they are still saying. Never pinned when Apple
    /// is the transcriber: that transcript is the sentence, and accuracy
    /// outranks the preference.
    public var requiresOnDeviceRecognition: Bool {
        appleRole == .liveTextOnly && supportsOnDeviceRecognition
    }
}

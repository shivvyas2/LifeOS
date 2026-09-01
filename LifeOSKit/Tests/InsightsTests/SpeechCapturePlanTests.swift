import Testing
@testable import Insights

/// The rule that decides what Apple's recognizer is for on a given turn.
///
/// Worth testing rather than reading: the costly mistake is silent. Let Apple
/// keep emitting a final while Scribe is primary and two transcripts race, so
/// the answer comes back to whichever won rather than to the better one, and
/// only sometimes. Nothing on screen says which transcript was used.
struct SpeechCapturePlanTests {

    private func plan(
        scribe: Bool, authorized: Bool = true,
        available: Bool = true, onDevice: Bool = true
    ) -> SpeechCapturePlan {
        SpeechCapturePlan(
            hasScribeKey: scribe, speechAuthorized: authorized,
            recognizerAvailable: available, supportsOnDeviceRecognition: onDevice
        )
    }

    @Test func withNoScribeKeyAppleIsTheTranscriber() {
        let p = plan(scribe: false)
        #expect(p.appleRole == .transcriber)
        #expect(p.emitsFinalTranscript)
        #expect(p.failureEndsTheTurn)
        #expect(p.canListen)
    }

    @Test func withAScribeKeyAppleOnlyDrawsTheWords() {
        let p = plan(scribe: true)
        #expect(p.appleRole == .liveTextOnly)
        // The whole point: Scribe owns the sentence that gets sent.
        #expect(!p.emitsFinalTranscript)
        // And a recogniser that dies must not tear down a live recording.
        #expect(!p.failureEndsTheTurn)
        #expect(p.canListen)
    }

    @Test func refusingSpeechCostsOnlyTheLiveTextWhenScribeCanTranscribe() {
        let p = plan(scribe: true, authorized: false)
        #expect(p.appleRole == .off)
        #expect(p.canListen)
    }

    @Test func refusingSpeechEndsTheTurnWhenAppleWasTheOnlyTranscriber() {
        let p = plan(scribe: false, authorized: false)
        #expect(p.appleRole == .off)
        #expect(!p.canListen)
    }

    @Test func anUnavailableRecognizerIsTreatedTheSameAsARefusedOne() {
        #expect(plan(scribe: true, available: false).appleRole == .off)
        #expect(plan(scribe: false, available: false).canListen == false)
    }

    @Test func displayOnlyRecognitionStaysOnTheDeviceWhenItCan() {
        // The clip already goes to one vendor. It should not go to a second
        // merely to put words under a waveform.
        #expect(plan(scribe: true, onDevice: true).requiresOnDeviceRecognition)
    }

    @Test func displayOnlyFallsBackToTheServerWhenTheDeviceCannot() {
        // Live text is the feature; losing it to preserve a preference would
        // be the wrong trade.
        #expect(!plan(scribe: true, onDevice: false).requiresOnDeviceRecognition)
    }

    @Test func theTranscriberIsNeverPinnedToTheDevice() {
        // Accuracy matters more when this transcript is the sentence sent.
        #expect(!plan(scribe: false, onDevice: true).requiresOnDeviceRecognition)
    }
}

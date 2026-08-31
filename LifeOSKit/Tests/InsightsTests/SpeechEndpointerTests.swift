import Foundation
import Testing
@testable import Insights

/// The rule that closes the microphone on its own.
///
/// Every case here is a room and a person: a quiet study, a café, someone who
/// pauses mid-sentence, someone who says nothing at all. They run against a
/// made-up timeline at the rate a real audio tap delivers buffers, so a test
/// is the same shape as a turn, minus the waiting.
@Suite struct SpeechEndpointerTests {

    /// 1024 frames at 48kHz, which is the tap the listener installs.
    private static let frame: TimeInterval = 1024.0 / 48000.0

    private struct Outcome {
        var verdict: SpeechEndpointer.Verdict
        var at: TimeInterval
    }

    /// Play a timeline of (level, seconds) through the endpointer and report
    /// the first verdict that is not "keep listening", if one comes.
    private func play(
        _ segments: [(level: Double, seconds: TimeInterval)],
        tuning: SpeechEndpointer.Tuning = SpeechEndpointer.Tuning()
    ) -> Outcome? {
        var endpointer = SpeechEndpointer(tuning: tuning)
        var elapsed: TimeInterval = 0
        for segment in segments {
            var spent: TimeInterval = 0
            while spent < segment.seconds {
                elapsed += Self.frame
                spent += Self.frame
                let verdict = endpointer.observe(level: segment.level, at: elapsed)
                if verdict != .keepListening {
                    return Outcome(verdict: verdict, at: elapsed)
                }
            }
        }
        return nil
    }

    private let quiet = 0.010
    private let voice = 0.500

    // MARK: - Ending on the speaker

    /// The point of the whole thing: say something, stop, and the turn ends by
    /// itself a beat later.
    @Test func aFinishedSentenceEndsTheTurnByItself() throws {
        let outcome = try #require(play([
            (quiet, 0.5),
            (voice, 1.2),
            (quiet, 4.0),
        ]))
        #expect(outcome.verdict == .finished)
        // The last voice was at 1.7s, so the turn should end one trailing
        // silence later and not before.
        #expect(abs(outcome.at - (1.7 + 1.5)) < 0.1)
    }

    /// The delay is the part that keeps the second half of a thought. A pause
    /// long enough to sound like the end of a sentence, but shorter than the
    /// trailing silence, must not end the turn.
    @Test func aPauseMidThoughtDoesNotEndTheTurn() {
        let outcome = play([
            (quiet, 0.5),
            (voice, 1.0),
            (quiet, 1.2),
            (voice, 1.0),
            (quiet, 1.2),
        ])
        #expect(outcome == nil)
    }

    /// A quiet voice in a quiet room is the case a fixed threshold set high
    /// enough for a café would never hear.
    @Test func aQuietVoiceInAQuietRoomStillCounts() throws {
        let outcome = try #require(play([
            (0.006, 0.5),
            (0.090, 1.0),
            (0.006, 3.0),
        ]))
        #expect(outcome.verdict == .finished)
    }

    /// And the café is the case a threshold set low enough for a whisper would
    /// hear as one unbroken sentence forever. The floor is learned from the
    /// room, so the same voice still ends the turn.
    @Test func aNoisyRoomIsLearnedRatherThanHeardAsSpeech() throws {
        let noisy = 0.090
        let outcome = try #require(play([
            (noisy, 0.6),
            (0.600, 1.0),
            (noisy, 4.0),
        ]))
        #expect(outcome.verdict == .finished)
        #expect(abs(outcome.at - (1.6 + 1.5)) < 0.15)
    }

    // MARK: - Ending on nobody

    /// Opening the mic and saying nothing closes it, rather than leaving a
    /// screen claiming to listen until someone notices.
    @Test func anEmptyTurnClosesOnItsOwnPatience() throws {
        let outcome = try #require(play([(quiet, 12.0)]))
        #expect(outcome.verdict == .nothingHeard)
        #expect(abs(outcome.at - 7.0) < 0.1)
    }

    /// It waits the full patience first. Closing early on someone still
    /// gathering their thought is the same bug as cutting them off.
    @Test func silenceAloneDoesNotCloseEarly() {
        #expect(play([(quiet, 6.5)]) == nil)
    }

    /// A door, a cough, a chair. Too short to be a sentence, so it neither
    /// ends the turn nor holds the microphone open waiting for the rest of it.
    @Test func aBlipIsNotASentence() throws {
        let outcome = try #require(play([
            (quiet, 0.5),
            (0.600, 0.15),
            (quiet, 12.0),
        ]))
        #expect(outcome.verdict == .nothingHeard)
        #expect(abs(outcome.at - 7.0) < 0.1)
    }

    // MARK: - Backstops

    /// A room loud enough that every frame reads as voice can never fall
    /// silent, so the turn has to end on the clock instead.
    @Test func aTurnThatCanNeverFallSilentStillEnds() throws {
        let outcome = try #require(play([(0.900, 70.0)]))
        #expect(outcome.verdict == .finished)
        #expect(abs(outcome.at - 60.0) < 0.1)
    }

    /// The audio thread keeps delivering buffers after the verdict. They must
    /// not produce a second one: the turn is already being transcribed.
    @Test func aVerdictIsReturnedOnlyOnce() {
        var endpointer = SpeechEndpointer()
        var elapsed: TimeInterval = 0
        var verdicts: [SpeechEndpointer.Verdict] = []
        for _ in 0..<1200 {
            elapsed += Self.frame
            let level = (0.5...1.7).contains(elapsed) ? voice : quiet
            let verdict = endpointer.observe(level: level, at: elapsed)
            if verdict != .keepListening { verdicts.append(verdict) }
        }
        #expect(verdicts == [.finished])
    }

    /// Endpointing waits out the calibration window, but nothing is lost by
    /// it: the recording is already running, and a sentence that starts in the
    /// first fraction of a second is still ended correctly.
    @Test func speakingImmediatelyStillEndsTheTurn() throws {
        let outcome = try #require(play([
            (voice, 1.5),
            (quiet, 4.0),
        ]))
        #expect(outcome.verdict == .finished)
    }
}

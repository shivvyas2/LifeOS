import Testing
@testable import Insights

/// What a voice is handed should read the way a person says it. A synthesiser
/// given "7h 24m" says "seven h twenty four m", which is the sound of text
/// being read out rather than something being said.
@Suite struct SpokenFormTests {
    @Test func durationsBecomeWords() {
        #expect(SpokenForm.normalize("You slept 7h 24m on average.") == "You slept 7 hours 24 minutes on average.")
        #expect(SpokenForm.normalize("Only 1h 1m last night.") == "Only 1 hour 1 minute last night.")
        #expect(SpokenForm.normalize("About 8h of sleep.") == "About 8 hours of sleep.")
        #expect(SpokenForm.normalize("Only 35 min of exercise.") == "Only 35 minutes of exercise.")
    }

    @Test func percentagesRatesAndUnitsBecomeWords() {
        #expect(SpokenForm.normalize("Recovery is 72%.") == "Recovery is 72 percent.")
        #expect(SpokenForm.normalize("8,610 steps / day this week.") == "8,610 steps a day this week.")
        #expect(SpokenForm.normalize("You weigh 77.4 kg.") == "You weigh 77.4 kilograms.")
        #expect(SpokenForm.normalize("Resting heart rate 54 bpm.") == "Resting heart rate 54 beats per minute.")
        #expect(SpokenForm.normalize("You ran 5 km today.") == "You ran 5 kilometres today.")
    }

    @Test func rangesAndSeparatorsReadNaturally() {
        #expect(SpokenForm.normalize("Aim for 7-8 hours.") == "Aim for 7 to 8 hours.")
        #expect(SpokenForm.normalize("Sleep · 7h 02m") == "Sleep, 7 hours 2 minutes")
    }

    @Test func passagesAreNormalizedByTheTrack() {
        let track = SpokenTrack(parsing: "SAY: You hit 72% recovery and slept 7h 24m.\n\nDetail.", final: true)
        #expect(track.opening == "You hit 72 percent recovery and slept 7 hours 24 minutes.")
    }

    @Test func theInstructionAsksForTalkNotReading() {
        let text = CoachPresentation.spokenTrackInstruction
        #expect(text.contains("contractions"))
        #expect(text.contains("the way people say them"))
        #expect(text.contains("Never read"))
    }
}

import Testing
@testable import Insights

/// One streamed reply, two audiences: passages for the voice interleaved
/// with sections for the screen. These pin the seam, the half-arrived
/// states a stream spends most of its time in, the cap, and how many
/// blocks each passage lets onto the screen.
@Suite struct SpokenTrackTests {
    private let threePassages = """
    SAY: Honestly, you slept well this week. Keep that wake time.

    Your sleep is more consistent this week.

    ## This week
    | Metric | Value |
    | --- | --- |
    | Average sleep | 7 h 24 min |
    | Recovery | 72% |

    SAY: Those two are up a notch on last week, and recovery is the one to watch.

    ## Next step
    - Start winding down 30 minutes before your usual bedtime.

    SAY: One small thing tonight, and that is plenty.
    """

    @Test func aWholeReplyParsesIntoSegmentsInOrder() {
        let track = SpokenTrack(parsing: threePassages, final: true)
        #expect(track.segments.count == 3)
        #expect(track.segments[0].spoken == "Honestly, you slept well this week. Keep that wake time.")
        #expect(track.segments[0].shown.hasPrefix("Your sleep is more consistent"))
        #expect(track.segments[1].spoken?.hasPrefix("Those two are up") == true)
        #expect(track.segments[1].shown.hasPrefix("## Next step"))
        #expect(track.segments[2].spoken == "One small thing tonight, and that is plenty.")
        #expect(track.segments[2].shown.isEmpty)
        #expect(!track.isOpeningPending)
        #expect(!track.shownText.contains("SAY:"))
        #expect(track.shownText.hasPrefix("Your sleep is more consistent"))
    }

    @Test func aStreamStillInsideTheOpeningShowsNothingYet() {
        let track = SpokenTrack(parsing: "SAY: Honestly, you slept we")
        #expect(track.opening == nil)
        #expect(track.shownText.isEmpty)
        #expect(track.isOpeningPending)
        #expect(SpokenTrack(parsing: "").isOpeningPending)
        #expect(SpokenTrack(parsing: "SA").isOpeningPending)
    }

    @Test func theOpeningIsCompleteTheMomentItsNewlineArrives() {
        let track = SpokenTrack(parsing: "SAY: You slept well.\n")
        #expect(track.opening == "You slept well.")
        #expect(track.shownText.isEmpty)
        #expect(!track.isOpeningPending)
    }

    @Test func aSecondPassageIsPendingUntilItsNewline() {
        let track = SpokenTrack(parsing: "SAY: Opening.\n\nA sentence.\n\nSAY: Half a passa")
        #expect(track.segments.count == 1)
        #expect(track.segments[0].shown == "A sentence.")
        let complete = SpokenTrack(parsing: "SAY: Opening.\n\nA sentence.\n\nSAY: Half a passage.\n")
        #expect(complete.segments.count == 2)
        #expect(complete.segments[1].spoken == "Half a passage.")
    }

    @Test func aTrailingPassageCountsOnlyWhenTheReplyIsFinal() {
        // The model's last line rarely ends with a newline. While streaming it
        // may still be growing; once the reply is whole it is a passage.
        let streaming = SpokenTrack(parsing: threePassages)
        #expect(streaming.segments.count == 2)
        let whole = SpokenTrack(parsing: threePassages, final: true)
        #expect(whole.segments.count == 3)
        #expect(SpokenTrack(parsing: "SAY: Just this.", final: true).opening == "Just this.")
        #expect(SpokenTrack(parsing: "SAY: Just this.").isOpeningPending)
    }

    @Test func aSectionWithoutAPassageMergesIntoThePrevious() {
        let track = SpokenTrack(parsing: "SAY: Opening.\n\nFirst.\n\n## Second\nMore.\n")
        #expect(track.segments.count == 1)
        #expect(track.segments[0].shown == "First.\n\n## Second\nMore.")
        #expect(track.shownText == "First.\n\n## Second\nMore.")
    }

    @Test func aReplyWithoutAnyPassageIsOneSegmentShownWhole() {
        let text = "No recovery data is available yet."
        let track = SpokenTrack(parsing: text)
        #expect(track.segments.count == 1)
        #expect(track.segments[0].spoken == nil)
        #expect(track.segments[0].shown == text)
        #expect(track.shownText == text)
        #expect(!track.isOpeningPending)
    }

    @Test func thePrefixIsMatchedLooselyAndPassagesAreCleaned() {
        let track = SpokenTrack(parsing: "\n say: \"**Nice** work - 7h 24m tonight.\"\n\nDetail here.")
        #expect(track.opening == "Nice work, 7 hours 24 minutes tonight.")
        #expect(track.shownText == "Detail here.")
    }

    @Test func anEmptyPassageCountsAsAbsent() {
        let track = SpokenTrack(parsing: "SAY:\n\nJust the answer.")
        #expect(track.opening == nil)
        #expect(track.shownText == "Just the answer.")
    }

    @Test func revealedBlocksAccumulate() {
        let track = SpokenTrack(parsing: threePassages, final: true)
        // Segment 0 shows a paragraph, a heading and a table: three blocks.
        #expect(track.revealedBlocks(throughSegment: 0) == 3)
        // Segment 1 adds a heading and a list: five.
        #expect(track.revealedBlocks(throughSegment: 1) == 5)
        // Segment 2 has no section of its own.
        #expect(track.revealedBlocks(throughSegment: 2) == 5)
        #expect(track.blockCount == 5)
    }

    @Test func cappingKeepsTheOpeningAndCutsAtSentences() {
        let track = SpokenTrack(parsing: threePassages, final: true)
        // Budget enough for the opening and part of the second passage.
        let capped = track.capped(to: 56 + 30)
        #expect(capped.segments[0].spoken == track.segments[0].spoken)
        #expect(capped.segments[1].spoken == nil)
        #expect(capped.segments[2].spoken == nil)
        #expect(capped.shownText == track.shownText)

        // A budget inside the opening itself trims it to a sentence, never to nothing.
        let tiny = track.capped(to: 30)
        #expect(tiny.segments[0].spoken == "Honestly, you slept well this week.")

        // Two whole passages fit; the third does not.
        let two = track.capped(to: 56 + 75)
        #expect(two.segments[1].spoken == track.segments[1].spoken)
        #expect(two.segments[2].spoken == nil)
    }

    @Test func theInstructionAsksForThePrefixAndTheWrittenRulesDoNot() {
        #expect(CoachPresentation.spokenTrackInstruction.contains(SpokenTrack.prefix))
        #expect(CoachPresentation.spokenTrackInstruction.contains("four"))
        #expect(!CoachPresentation.instruction.contains(SpokenTrack.prefix))
    }
}

import Testing
@testable import Insights

/// The reply arrives as one stream with two audiences in it: a line for the
/// voice and the rest for the screen. These pin the seam between them,
/// including the half-arrived states a stream spends most of its time in.
@Suite struct SpokenReplyTests {

    @Test func aCompleteReplySplitsIntoSpokenAndShown() {
        let reply = SpokenReply(parsing: """
        SAY: Honestly, you slept well this week. Keep that wake time.

        ## This week
        | Metric | Value |
        | --- | --- |
        | Sleep | 7 h 24 min |
        """)
        #expect(reply.spoken == "Honestly, you slept well this week. Keep that wake time.")
        #expect(reply.shown.hasPrefix("## This week"))
        #expect(!reply.shown.contains("SAY:"))
        #expect(!reply.isSpokenLinePending)
    }

    @Test func aStreamStillInsideTheSpokenLineShowsNothingYet() {
        let reply = SpokenReply(parsing: "SAY: Honestly, you slept we")
        #expect(reply.spoken == nil)
        #expect(reply.shown.isEmpty)
        #expect(reply.isSpokenLinePending)
    }

    @Test func theSpokenLineIsCompleteTheMomentItsNewlineArrives() {
        let reply = SpokenReply(parsing: "SAY: You slept well.\n")
        #expect(reply.spoken == "You slept well.")
        #expect(reply.shown.isEmpty)
        #expect(!reply.isSpokenLinePending)
    }

    @Test func aFewCharactersThatCouldStillBecomeThePrefixArePending() {
        #expect(SpokenReply(parsing: "").isSpokenLinePending)
        #expect(SpokenReply(parsing: "SA").isSpokenLinePending)
        #expect(SpokenReply(parsing: "SA").shown.isEmpty)
    }

    @Test func aReplyWithoutTheLineIsShownWholeAndSpokenByNobody() {
        let text = "No recovery data is available yet."
        let reply = SpokenReply(parsing: text)
        #expect(reply.spoken == nil)
        #expect(reply.shown == text)
        #expect(!reply.isSpokenLinePending)
    }

    @Test func thePrefixIsMatchedLooselyAndTheLineIsCleanedForAVoice() {
        let reply = SpokenReply(parsing: "\n say: \"**Nice** work - 7h 24m tonight.\"\n\nDetail here.")
        #expect(reply.spoken == "Nice work, 7h 24m tonight.")
        #expect(reply.shown == "Detail here.")
    }

    @Test func anEmptySpokenLineCountsAsAbsent() {
        let reply = SpokenReply(parsing: "SAY:\n\nJust the answer.")
        #expect(reply.spoken == nil)
        #expect(reply.shown == "Just the answer.")
    }

    @Test func theInstructionAsksForThePrefixOnItsOwnFirstLine() {
        #expect(CoachPresentation.spokenLineInstruction.contains(SpokenReply.prefix))
        #expect(!CoachPresentation.instruction.contains(SpokenReply.prefix))
    }
}

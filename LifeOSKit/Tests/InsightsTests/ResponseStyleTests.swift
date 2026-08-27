import Testing
@testable import Insights

@Suite struct ResponseStyleTests {

    @Test func markdownEmphasisIsRemovedAndTheWordsSurvive() {
        #expect(ResponseStyle.clean("You slept **7h 20m** last night") == "You slept 7h 20m last night")
        #expect(ResponseStyle.clean("Your _resting_ heart rate fell") == "Your resting heart rate fell")
        #expect(ResponseStyle.clean("Use `steps` here") == "Use steps here")
    }

    @Test func bulletsBecomePlainLines() {
        let cleaned = ResponseStyle.clean("- Ran 5km\n- Slept badly\n* Ate late")
        #expect(cleaned == "Ran 5km\nSlept badly\nAte late")
    }

    @Test func numberedListsLoseTheirNumbers() {
        #expect(ResponseStyle.clean("1. First\n2) Second") == "First\nSecond")
    }

    @Test func headingsAndQuotesLoseTheirMarks() {
        #expect(ResponseStyle.clean("## Sleep\n> it was short") == "Sleep\nit was short")
    }

    /// A spaced dash was standing in for a comma, so it becomes one.
    @Test func spacedDashesBecomeCommas() {
        #expect(ResponseStyle.clean("You slept well \u{2014} better than Tuesday")
                == "You slept well, better than Tuesday")
        #expect(ResponseStyle.clean("Steps were low - about 4000")
                == "Steps were low, about 4000")
    }

    /// Joining the words would invent a compound that was never written.
    @Test func unspacedDashesBecomeSpaces() {
        #expect(ResponseStyle.clean("Monday\u{2014}Friday") == "Monday Friday")
    }

    /// The two things a blunt filter gets wrong. Both must survive.
    @Test func contractionsAndHyphenatedWordsSurvive() {
        #expect(ResponseStyle.clean("You didn't hit your well-being target")
                == "You didn't hit your well-being target")
    }

    @Test func quotationMarksGoButApostrophesStay() {
        #expect(ResponseStyle.clean("Your \u{201C}rest day\u{201D} wasn't restful")
                == "Your rest day wasn't restful")
    }

    /// A hyphen starting a line is a bullet; one inside a sentence is not.
    @Test func onlyLeadingHyphensAreTreatedAsBullets() {
        #expect(ResponseStyle.clean("- a point about e-bikes") == "a point about e-bikes")
    }

    @Test func removalsDoNotLeaveDoubleSpacesOrFloatingPunctuation() {
        #expect(ResponseStyle.clean("Sleep **was** fine .") == "Sleep was fine.")
        #expect(!ResponseStyle.clean("A ** ** B").contains("  "))
    }

    @Test func blankLinesAreCollapsedRatherThanKept() {
        #expect(ResponseStyle.clean("One\n\n\n\nTwo") == "One\nTwo")
    }

    /// A reply that cleans down to nothing must not become an empty bubble
    /// that reads as a failure.
    @Test func aReplyOfNothingButMarkupCleansToEmpty() {
        #expect(ResponseStyle.clean("***\n---\n") == "")
    }

    @Test func plainProseIsLeftExactlyAsItIs() {
        let prose = "You averaged 7h 12m of sleep this week, up 24 minutes on last week."
        #expect(ResponseStyle.clean(prose) == prose)
    }

    @Test func theInstructionForbidsWhatTheCleanerStrips() {
        for forbidden in ["markdown", "em dash", "quotation marks", "asterisks"] {
            #expect(ResponseStyle.instruction.lowercased().contains(forbidden.lowercased()))
        }
    }
}

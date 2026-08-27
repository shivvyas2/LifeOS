import Testing
@testable import Insights

/// The trimming rule for spoken replies lives in the app target, so what is
/// tested here is the thing it depends on: that the text handed to a voice has
/// already had its markup removed. Paying a per-character meter to narrate
/// asterisks would be paying twice for a formatting bug.
@Suite struct SpokenTextTests {

    @Test func markupNeverReachesAVoice() {
        let cleaned = ResponseStyle.clean("**Sleep** was short - about 5h")
        #expect(!cleaned.contains("*"))
        #expect(!cleaned.contains(" - "))
        #expect(cleaned == "Sleep was short, about 5h")
    }

    /// Numbers are the part of an answer a person is actually listening for,
    /// so the cleaner must not touch them.
    @Test func figuresSurviveCleaningIntact() {
        let text = "You averaged 7h 12m, up 24 minutes on last week."
        #expect(ResponseStyle.clean(text) == text)
    }
}

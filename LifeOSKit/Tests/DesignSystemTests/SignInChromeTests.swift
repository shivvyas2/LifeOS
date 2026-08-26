import Testing
@testable import DesignSystem

/// The sign-in screen could previously stack three coloured messages at once:
/// a validation error, a "phone is unavailable in your region" note, and a
/// configuration warning. Three simultaneous complaints read as a broken app
/// rather than as one thing to fix, so exactly one wins.
@Suite struct InlineStatusTests {

    @Test func nothingWrongShowsNothing() {
        #expect(InlineStatus.resolve(error: nil, configuration: nil, warning: nil) == nil)
    }

    /// The error is the thing the user just caused, so it is the thing they can
    /// act on now.
    @Test func anErrorOutranksEverythingElse() {
        let status = InlineStatus.resolve(
            error: "That code has expired.",
            configuration: "Sign-in is unavailable.",
            warning: "Phone sign-in isn't available in your region."
        )

        #expect(status?.message == "That code has expired.")
        #expect(status?.severity == .error)
    }

    /// If sign-in is not configured at all, nothing on the screen can succeed.
    /// That outranks a note about one channel being unavailable.
    @Test func aConfigurationProblemOutranksAChannelWarning() {
        let status = InlineStatus.resolve(
            error: nil,
            configuration: "Sign-in is unavailable.",
            warning: "Phone sign-in isn't available in your region."
        )

        #expect(status?.message == "Sign-in is unavailable.")
        #expect(status?.severity == .error)
    }

    /// A channel note is a warning, not an error: the screen still works, just
    /// not the way the user picked.
    @Test func aChannelNoteAloneIsAWarning() {
        let status = InlineStatus.resolve(
            error: nil,
            configuration: nil,
            warning: "Phone sign-in isn't available in your region."
        )

        #expect(status?.severity == .warning)
    }

    /// An empty string is absence, not a message. Rendering it would leave a
    /// coloured gap under the field with nothing in it.
    @Test func blankMessagesCountAsAbsent() {
        #expect(InlineStatus.resolve(error: "", configuration: "  ", warning: nil) == nil)
        #expect(InlineStatus.resolve(error: "", configuration: nil, warning: "Real note")?.severity == .warning)
    }
}

/// The six-digit code display. The digits shown are derived, never stored, so
/// the boxes cannot drift out of step with the field backing them.
@Suite struct CodeDigitsTests {

    @Test func aPartialCodeFillsFromTheLeftAndLeavesTheRestEmpty() {
        let digits = CodeDigits.digits(from: "123", count: 6)

        #expect(digits.count == 6)
        #expect(digits[0] == "1")
        #expect(digits[2] == "3")
        #expect(digits[3] == nil)
    }

    /// Autofill and paste both deliver text with spaces and dashes in it.
    @Test func nonDigitsAreIgnoredRatherThanShown() {
        let digits = CodeDigits.digits(from: "12-34 5", count: 6)

        #expect(digits[0] == "1")
        #expect(digits[3] == "4")
        #expect(digits[4] == "5")
        #expect(digits[5] == nil)
    }

    /// A long paste must not spill a seventh box onto the screen.
    @Test func extraDigitsAreDroppedRatherThanOverflowing() {
        let digits = CodeDigits.digits(from: "1234567890", count: 6)

        #expect(digits.count == 6)
        #expect(digits[5] == "6")
    }

    @Test func anEmptyCodeIsAllEmptyBoxes() {
        #expect(CodeDigits.digits(from: "", count: 6).allSatisfy { $0 == nil })
    }

    @Test func aZeroLengthCodeHasNoBoxes() {
        #expect(CodeDigits.digits(from: "123", count: 0).isEmpty)
    }
}

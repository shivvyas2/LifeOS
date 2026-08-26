import Testing
import Foundation
@testable import Persistence

@Suite struct NoteBlockTests {

    @Test func markdownPrefixesResolveToTheirBlock() {
        #expect(NoteBlockParser.shortcut(in: "# Heading")?.kind == .heading1)
        #expect(NoteBlockParser.shortcut(in: "## Heading")?.kind == .heading2)
        #expect(NoteBlockParser.shortcut(in: "- item")?.kind == .bulleted)
        #expect(NoteBlockParser.shortcut(in: "1. item")?.kind == .numbered)
        #expect(NoteBlockParser.shortcut(in: "[] task")?.kind == .todo)
        #expect(NoteBlockParser.shortcut(in: "> quote")?.kind == .quote)
    }

    @Test func aPrefixIsEatenAndTheRestSurvives() {
        let resolved = NoteBlockParser.shortcut(in: "## Week four")
        #expect(resolved?.remainder == "Week four")
    }

    /// Longer prefixes must win. `## ` also starts with `# `, and resolving it
    /// to a level-one heading would make level two unreachable by typing.
    @Test func theLongestMatchingPrefixWins() {
        #expect(NoteBlockParser.shortcut(in: "### deep")?.kind == .heading3)
        #expect(NoteBlockParser.shortcut(in: "## mid")?.kind == .heading2)
    }

    /// A rule is a whole line. Someone typing an em dash sequence mid-sentence
    /// must not have the line turn into a divider under them.
    @Test func dividersOnlyFireOnTheirOwnLine() {
        #expect(NoteBlockParser.shortcut(in: "---")?.kind == .divider)
        #expect(NoteBlockParser.shortcut(in: "--- and more") == nil)
    }

    @Test func textWithNoPrefixResolvesToNothing() {
        #expect(NoteBlockParser.shortcut(in: "just typing") == nil)
        #expect(NoteBlockParser.shortcut(in: "") == nil)
    }

    @Test func markdownRoundTripsThroughBlocks() {
        let source = """
        # Marathon
        - [ ] Long run
        - [x] Easy run
        > Keep Tuesday easy
        """
        let blocks = NoteBlockParser.blocks(fromMarkdown: source)

        #expect(blocks[0].kind == .heading1)
        #expect(blocks[1].kind == .todo)
        #expect(blocks[1].isChecked == false)
        #expect(blocks[2].isChecked == true)
        #expect(blocks[3].kind == .quote)
    }

    @Test func numberedListsRenumberOnTheWayOut() {
        let blocks = [
            NoteBlock(kind: .numbered, text: "first"),
            NoteBlock(kind: .numbered, text: "second"),
            NoteBlock(kind: .paragraph, text: "break"),
            NoteBlock(kind: .numbered, text: "restarted"),
        ]
        let markdown = NoteBlockParser.markdown(blocks)

        #expect(markdown.contains("1. first"))
        #expect(markdown.contains("2. second"))
        // The run restarts after the paragraph rather than continuing at three.
        #expect(markdown.contains("1. restarted"))
    }

    @Test func emptyMarkdownStillProducesSomewhereToType() {
        #expect(NoteBlockParser.blocks(fromMarkdown: "").count == 1)
    }

    @Test func taskProgressCountsOnlyTodoBlocks() {
        let blocks = [
            NoteBlock(kind: .todo, text: "a", isChecked: true),
            NoteBlock(kind: .todo, text: "b"),
            NoteBlock(kind: .bulleted, text: "not a task"),
        ]
        let progress = NoteBlockParser.taskProgress(blocks)

        #expect(progress.done == 1)
        #expect(progress.total == 2)
    }

    @Test func wikiLinksAreFoundInOrderAndDeduplicated() {
        let links = NoteLinkScanner.links(in: "See [[Marathon]] and [[Diet]] and [[marathon]] again")

        #expect(links == ["Marathon", "Diet"])
    }

    @Test func anUnclosedLinkIsNotALink() {
        #expect(NoteLinkScanner.links(in: "start of [[something").isEmpty)
    }

    @Test func linkRangesCoverTheBracketsToo() {
        let text = "go to [[Marathon]] now"
        let ranges = NoteLinkScanner.ranges(in: text)

        #expect(ranges.count == 1)
        #expect(String(text[ranges[0]]) == "[[Marathon]]")
    }

    @Test func indentIsClampedToTheAllowedDepth() {
        #expect(NoteBlock(indent: 99).indent == NoteBlock.maxIndent)
        #expect(NoteBlock(indent: -4).indent == 0)
    }
}

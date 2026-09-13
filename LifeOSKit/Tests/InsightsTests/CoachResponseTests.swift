import Testing
@testable import Insights

@Suite struct CoachResponseTests {
    @Test func shortAnswersStayPlain() {
        #expect(CoachResponse("No recovery data is available yet.").blocks == [
            .paragraph("No recovery data is available yet.")
        ])
    }

    @Test func metricsKeepExactUnitsAndMissingValues() {
        let response = CoachResponse("""
        ## This week
        | Metric | Value |
        | --- | --- |
        | Sleep | 7 h 24 min |
        | Recovery | Not available |
        """)
        #expect(response.blocks == [.heading("This week"), .table(
            headers: ["Metric", "Value"],
            rows: [["Sleep", "7 h 24 min"], ["Recovery", "Not available"]])])
    }

    @Test func comparisonsRetainHeadersColumnsAndNegativeAmounts() {
        let response = CoachResponse("""
        | Category | Last month | This month |
        | :--- | ---: | ---: |
        | Refunds | -$20.00 | -$5.25 |
        """)
        #expect(response.blocks == [.table(headers: ["Category", "Last month", "This month"],
            rows: [["Refunds", "-$20.00", "-$5.25"]])])
    }

    @Test func escapedPipesDoNotAddColumns() {
        let response = CoachResponse("| Name | Value |\n| --- | --- |\n| Food \\| coffee | $14.75 |")
        #expect(response.blocks == [.table(headers: ["Name", "Value"], rows: [["Food | coffee", "$14.75"]])])
    }

    @Test func malformedRowsRemainVisibleRatherThanInventingCells() {
        let response = CoachResponse("| A | B |\n| --- | --- |\n| one | two |\n| three | four | five |")
        #expect(response.blocks.last == .paragraph("| three | four | five |"))
    }

    @Test func actionsRenderAsAList() {
        #expect(CoachResponse("- Keep your wake-up time.\n- Take a short walk.").blocks == [
            .list(["Keep your wake-up time.", "Take a short walk."])
        ])
    }

    @Test func voiceReadsTableValuesWithoutMarkdown() {
        let text = CoachResponse("| Metric | Value |\n| --- | --- |\n| Sleep | 7 h |").spokenText
        #expect(text == "Metric: Sleep, Value: 7 h")
        #expect(!text.contains("|"))
    }

    @Test func onlyCoachFormattingBypassesPlainTextCleaner() {
        let markdown = "## Sleep\n- Wake up at 7"
        #expect(CoachPresentation.clean(markdown, instructions: CoachPresentation.instruction) == markdown)
        #expect(CoachPresentation.clean(markdown, instructions: "Calendar assistant") == ResponseStyle.clean(markdown))
    }
}

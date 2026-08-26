import Testing
import Foundation
import FoundationModels
@testable import Insights

@Generable
private struct ProbeArguments {
    @Guide(description: "Any short string")
    var value: String
}

private struct ProbeTool: CoachTool {
    let name = "probe"
    let description = "A probe"
    var parameters: GenerationSchema { ProbeArguments.generationSchema }
    func call(_ arguments: GeneratedContent) async throws -> String { "ok" }
}

@Suite struct CoachToolTests {
    /// Pins the schema-sharing assumption: `GenerationSchema` is Codable, so
    /// one declaration can serve the on-device binding today and a remote
    /// `tools[]` payload later. If an OS update breaks this, Phase B's remote
    /// story changes and this test says so first.
    @Test func toolParametersRoundTripThroughJSON() throws {
        let encoded = try JSONEncoder().encode(ProbeTool().parameters)
        #expect(!encoded.isEmpty)
        let decoded = try JSONDecoder().decode(GenerationSchema.self, from: encoded)
        _ = decoded
    }

    @Test func confirmationAndSummaryHaveSafeDefaults() async {
        let tool = ProbeTool()
        #expect(tool.requiresConfirmation == false)
        #expect(tool.summary("x".generatedContent) == "probe")
        #expect(await tool.confirmationPreview("x".generatedContent) == ["probe"])
    }
}

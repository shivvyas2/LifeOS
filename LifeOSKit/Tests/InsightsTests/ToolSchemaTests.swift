import Testing
import Foundation
import FoundationModels
@testable import Insights

@Generable private struct RangeArgs {
    @Guide(description: "ISO-8601 start") var start: String
    @Guide(description: "ISO-8601 end") var end: String
}

private struct StubTool: CoachTool {
    let name = "get_events"
    let description = "Reads calendar events in a range."
    var parameters: GenerationSchema { RangeArgs.generationSchema }
    func call(_ arguments: GeneratedContent) async throws -> String { "ok" }
}

@Suite struct ToolSchemaTests {

    private func function(_ tool: any CoachTool) throws -> [String: Any] {
        let json = try ToolSchema.function(for: tool)
        return try #require(json["function"] as? [String: Any])
    }

    @Test func aToolBecomesAnOpenAIFunctionDeclaration() throws {
        let json = try ToolSchema.function(for: StubTool())
        #expect(json["type"] as? String == "function")

        let function = try #require(json["function"] as? [String: Any])
        #expect(function["name"] as? String == "get_events")
        #expect(function["description"] as? String == "Reads calendar events in a range.")
    }

    @Test func theGenerationSchemaSurvivesAsTheParameterObject() throws {
        let function = try function(StubTool())
        let parameters = try #require(function["parameters"] as? [String: Any])
        #expect(parameters["type"] as? String == "object")

        let properties = try #require(parameters["properties"] as? [String: Any])
        #expect(properties.keys.contains("start"))
        #expect(properties.keys.contains("end"))
    }

    /// A model that invents an argument we never declared is a model whose
    /// call we cannot decode. Refusing extras at the schema is cheaper than
    /// discovering it at `GeneratedContent(json:)`.
    @Test func extraArgumentsAreForbidden() throws {
        let function = try function(StubTool())
        let parameters = try #require(function["parameters"] as? [String: Any])
        #expect(parameters["additionalProperties"] as? Bool == false)
    }

    /// Strict mode would list every property as required, quietly making an
    /// optional tool argument mandatory. See the ruling in the plan.
    @Test func theDeclarationIsNotStrict() throws {
        let function = try function(StubTool())
        #expect(function["strict"] as? Bool == false)
    }
}

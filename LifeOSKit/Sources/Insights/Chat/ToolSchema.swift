import Foundation
import FoundationModels

/// Renders a `CoachTool` into the shape OpenAI's function calling expects.
///
/// This is the whole reason `CoachTool.parameters` was declared as a
/// `GenerationSchema` rather than as an on-device-only type: the schema is
/// Codable, and what it encodes to is already JSON Schema in all but name.
/// `SchemaEncodingTests` pins that assumption; this file depends on it.
public enum ToolSchema {

    public static func function(for tool: any CoachTool) throws -> [String: Any] {
        let data = try JSONEncoder().encode(tool.parameters)
        var parameters = (try JSONSerialization.jsonObject(with: data)
            as? [String: Any]) ?? [:]

        // Not a stylistic addition. An argument we never declared cannot be
        // decoded by `GeneratedContent(json:)` on the way back in, so the
        // cheapest place to refuse it is before the model emits it.
        parameters["additionalProperties"] = false

        return [
            "type": "function",
            "function": [
                "name": tool.name,
                "description": tool.description,
                "parameters": parameters,
                // Deliberately false. Strict mode requires every property to
                // be listed as required, which would turn an optional tool
                // argument into a mandatory one without anyone deciding to.
                "strict": false,
            ] as [String: Any],
        ]
    }
}

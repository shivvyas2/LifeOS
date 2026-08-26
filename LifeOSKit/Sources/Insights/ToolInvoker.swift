import Foundation
import FoundationModels

/// Executes tool calls on the model's behalf: enforces the per-turn cap,
/// holds gated calls at the broker, turns failures into result strings the
/// model can recover from, and records chips for the UI.
///
/// One invoker per user turn; the cap and the summaries are turn state.
public actor ToolInvoker {
    public static let invocationLimit = 6

    private let toolsByName: [String: any CoachTool]
    private let broker: ConfirmationBroker
    private var invocations = 0
    private var summaries: [String] = []

    public init(tools: [any CoachTool], broker: ConfirmationBroker) {
        self.toolsByName = Dictionary(
            tools.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.broker = broker
    }

    public func toolSummaries() -> [String] { summaries }

    public func invoke(name: String, arguments: GeneratedContent) async -> String {
        guard let tool = toolsByName[name] else {
            return "No tool named \(name) is available."
        }
        guard invocations < Self.invocationLimit else {
            return "The tool limit for this request was reached. Tell the user the request could not be completed."
        }
        invocations += 1

        if tool.requiresConfirmation {
            let write = PendingWrite(
                toolName: tool.name,
                preview: await tool.confirmationPreview(arguments)
            )
            guard await broker.decision(for: write) else {
                return "User declined this change."
            }
        }

        do {
            let result = try await tool.call(arguments)
            summaries.append(tool.summary(arguments))
            return result
        } catch {
            return "The \(name) tool failed: \(error.localizedDescription). Recover or explain what happened."
        }
    }
}

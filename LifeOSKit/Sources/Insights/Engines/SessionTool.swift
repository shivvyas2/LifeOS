import FoundationModels

/// Binds one `CoachTool` into a `LanguageModelSession`. The session drives
/// `call`; everything of substance (gating, cap, error shaping) happens in
/// the shared invoker so it is identical for every tool and testable without
/// a model.
struct SessionTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema
    private let invoker: ToolInvoker

    init(_ tool: any CoachTool, invoker: ToolInvoker) {
        self.name = tool.name
        self.description = tool.description
        self.parameters = tool.parameters
        self.invoker = invoker
    }

    func call(arguments: GeneratedContent) async throws -> String {
        await invoker.invoke(name: name, arguments: arguments)
    }
}

import Foundation
import FoundationModels

/// The cloud tier of the conversation.
///
/// The loop lives here, on the device, and not in the Edge Function. Every
/// tool reads device-local state through EventKit, HealthKit or SwiftData,
/// so a server-driven loop would have to call back into the phone. Keeping
/// the rounds here also means a tool result never travels anywhere except
/// back to the provider that asked for it.
public struct RemoteChatEngine: ChatEngine {
    private let baseURL: URL
    private let anonKey: String
    private let accessToken: @Sendable () -> String?
    private let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// `transport` is injectable so the round loop can be tested without a
    /// network. It defaults to the shared session, which is what ships.
    public init(
        baseURL: URL, anonKey: String,
        accessToken: @escaping @Sendable () -> String?,
        transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
            = { try await URLSession.shared.data(for: $0) }
    ) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.accessToken = accessToken
        self.transport = transport
    }

    public func reply(
        to thread: [ChatTurnMessage],
        tools: [any CoachTool],
        invoker: ToolInvoker
    ) async throws -> AssistantTurn.Reply {
        guard let token = accessToken(), !token.isEmpty else {
            throw RemoteEngineError.notSignedIn
        }

        var messages = thread.map {
            ChatWire.Message(role: $0.role.rawValue, content: $0.text)
        }

        // Bounded by the invoker's own cap rather than a second number of
        // this file's invention. One extra round is allowed on top, for the
        // reply that comes after the last permitted tool call.
        for _ in 0...ToolInvoker.invocationLimit {
            let request = try ChatWire.request(
                baseURL: baseURL, anonKey: anonKey, accessToken: token,
                messages: messages, tools: tools
            )

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await transport(request)
            } catch {
                // Offline, DNS, timeout. Transient by nature.
                throw RemoteEngineError.unavailable
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            switch try ChatWire.reply(data: data, status: status) {
            case .text(let text):
                return AssistantTurn.Reply(
                    text: ResponseStyle.clean(text),
                    toolSummaries: await invoker.toolSummaries()
                )

            case .toolCalls(let calls):
                // The assistant turn that asked, so the thread we resend
                // reads back the way the provider produced it.
                messages.append(ChatWire.Message(
                    role: "assistant", content: "", toolCalls: calls
                ))
                for call in calls {
                    // Every call must be answered, even one whose arguments
                    // will not parse: a provider left waiting on a result
                    // that never arrives simply asks again, and the loop
                    // spends its remaining rounds on it.
                    let result: String
                    if let arguments = try? GeneratedContent(json: call.argumentsJSON) {
                        result = await invoker.invoke(name: call.name, arguments: arguments)
                    } else {
                        result = "The \(call.name) tool was given arguments that could not be read. Explain what happened rather than retrying."
                    }
                    messages.append(ChatWire.Message(
                        role: "tool", content: result, toolCallID: call.id
                    ))
                }
            }
        }

        // The loop ran out of rounds without the model committing to prose.
        // The invoker has already been returning its cap message for the
        // last few, so this is a model that will not stop; say so rather
        // than returning an empty bubble.
        return AssistantTurn.Reply(
            text: "That turned into more steps than I can take in one go. Try asking for one thing at a time.",
            toolSummaries: await invoker.toolSummaries()
        )
    }
}

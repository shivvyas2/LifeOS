// LifeOSKit/Sources/Insights/Chat/ChatWire.swift
import Foundation

/// The chat wire format, kept out of the engine so every decision it makes
/// is testable without a network. The same division `RemoteWire` uses, for
/// the same reason.
public enum ChatWire {

    /// One tool call the model asked for.
    ///
    /// `argumentsJSON` stays a string rather than being decoded here: the
    /// only consumer is `GeneratedContent(json:)`, which takes a string, and
    /// decoding it twice would be work done only to undo it.
    public struct ToolCall: Sendable, Equatable {
        public let id: String
        public let name: String
        public let argumentsJSON: String

        public init(id: String, name: String, argumentsJSON: String) {
            self.id = id
            self.name = name
            self.argumentsJSON = argumentsJSON
        }
    }

    public struct Message: Sendable, Equatable {
        public let role: String
        public let content: String
        /// Set only on a tool result, naming the call it answers.
        public let toolCallID: String?
        /// Set only on an assistant turn that asked for tools, so the thread
        /// we resend reads back to the provider the way it produced it.
        public let toolCalls: [ToolCall]?

        public init(role: String, content: String,
                    toolCallID: String? = nil, toolCalls: [ToolCall]? = nil) {
            self.role = role
            self.content = content
            self.toolCallID = toolCallID
            self.toolCalls = toolCalls
        }

        var payload: [String: Any] {
            var json: [String: Any] = ["role": role, "content": content]
            if let toolCallID { json["tool_call_id"] = toolCallID }
            if let toolCalls, !toolCalls.isEmpty {
                json["tool_calls"] = toolCalls.map {
                    ["id": $0.id, "name": $0.name, "arguments": $0.argumentsJSON]
                }
            }
            return json
        }
    }

    public enum Reply: Sendable, Equatable {
        case text(String)
        case toolCalls([ToolCall])
    }

    public static func request(
        baseURL: URL, anonKey: String, accessToken: String,
        messages: [Message], tools: [any CoachTool]
    ) throws -> URLRequest {
        var request = URLRequest(
            url: baseURL.appendingPathComponent("functions/v1/lifo-agent")
        )
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "task": "chat",
            "messages": messages.map(\.payload),
            "tools": try tools.map { try ToolSchema.function(for: $0) },
        ])
        return request
    }

    private struct TextReply: Decodable {
        struct Output: Decodable { let text: String }
        let output: Output
    }

    private struct ToolCallsReply: Decodable {
        struct Call: Decodable {
            let id: String
            let name: String
            let arguments: String
        }
        let tool_calls: [Call]
    }

    public static func reply(data: Data, status: Int) throws -> Reply {
        if let error = RemoteWire.failure(data: data, status: status) { throw error }

        // Tool calls first. A reply carrying both is the provider telling us
        // it wants a tool run before it will commit to prose, and answering
        // with the prose would strand the call.
        if let calls = try? JSONDecoder().decode(ToolCallsReply.self, from: data),
           !calls.tool_calls.isEmpty {
            return .toolCalls(calls.tool_calls.map {
                ToolCall(id: $0.id, name: $0.name, argumentsJSON: $0.arguments)
            })
        }
        if let text = try? JSONDecoder().decode(TextReply.self, from: data) {
            return .text(text.output.text)
        }
        // A 200 whose body fits neither shape is the server being wrong,
        // which the user cannot fix and a retry might. Never a refusal.
        throw RemoteEngineError.unavailable
    }
}

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

    /// `context` is the caller's instructions: the rendered data bundle, or
    /// the calendar assistant's rules and the current date. It travels in a
    /// field of its own rather than as a `{role: "system"}` message the
    /// client wrote, because the server has to be able to tell the two
    /// apart. A client-authored system message would land after the scope
    /// guardrail and providers weight the later one heavily, which is a way
    /// around the guardrail rather than a way to carry data. The server
    /// wraps this in its own system message, behind `SCOPE`.
    /// `stream` asks the server to hand text back as it arrives.
    ///
    /// Only ever true for a turn with no tools, and the server enforces that
    /// independently rather than trusting the flag: a tool call arrives in a
    /// stream as fragments of a JSON argument string spread across chunks, and
    /// the round loop below needs whole ones.
    public static func request(
        baseURL: URL, anonKey: String, accessToken: String,
        messages: [Message], tools: [any CoachTool], context: String = "",
        stream: Bool = false
    ) throws -> URLRequest {
        var request = URLRequest(
            url: baseURL.appendingPathComponent("functions/v1/lifo-agent")
        )
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        var body: [String: Any] = [
            "task": "chat",
            "messages": messages.map(\.payload),
            "tools": try tools.map { try ToolSchema.function(for: $0) },
        ]
        // Absent rather than empty when there is nothing to say, so the
        // server never builds a system message with no content in it.
        if !context.isEmpty { body["context"] = context }
        if stream { body["stream"] = true }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// One frame of the server's own event stream.
    ///
    /// Deliberately our shape, not the provider's: the function re-emits what
    /// it reads so the device never learns a provider's chunk format, and
    /// changing providers stays a deploy rather than an app release.
    public enum StreamEvent: Sendable, Equatable {
        case delta(String)
        case refused(String)
        case done
    }

    /// Reads one `data:` payload. Returns nil for a frame that carries
    /// nothing we act on, which is not an error: a keep-alive comment and an
    /// unparseable frame both mean "no text yet", and failing the turn over
    /// one would throw away the sentence around it.
    public static func streamEvent(payload: String) -> StreamEvent? {
        let trimmed = payload.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == "[DONE]" { return .done }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let message = object["message"] as? String, object["error"] as? String == "refused" {
            return .refused(message)
        }
        if let delta = object["delta"] as? String { return .delta(delta) }
        return nil
    }

    /// The payload of one SSE line, or nil for a line that is not data.
    public static func payload(inLine line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        return String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
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

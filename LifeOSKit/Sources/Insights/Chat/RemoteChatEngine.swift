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
    private let streamTransport: @Sendable (URLRequest) async throws -> (LineStream, URLResponse)

    /// The server's event stream, one line at a time.
    ///
    /// Our own type rather than `URLSession.AsyncBytes.Lines`, so a test can
    /// hand the engine a scripted stream without a network. The shipping
    /// implementation is the two lines in `liveLines` below.
    public typealias LineStream = AsyncThrowingStream<String, Error>

    /// Both transports are injectable so the round loop and the stream reader
    /// can be tested without a network. They default to the shared session,
    /// which is what ships.
    public init(
        baseURL: URL, anonKey: String,
        accessToken: @escaping @Sendable () -> String?,
        transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
            = { try await URLSession.shared.data(for: $0) },
        streamTransport: @escaping @Sendable (URLRequest) async throws -> (LineStream, URLResponse)
            = { try await Self.liveLines(for: $0) }
    ) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.accessToken = accessToken
        self.transport = transport
        self.streamTransport = streamTransport
    }

    /// `URLSession`'s byte stream, split into lines and rewrapped in our own
    /// type. The rewrap is the whole of it: nothing here decides anything.
    public static func liveLines(for request: URLRequest) async throws -> (LineStream, URLResponse) {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let stream = LineStream { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines { continuation.yield(line) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (stream, response)
    }

    /// `instructions` is the user's own data, rendered for the off-device
    /// audience by the caller. It is sent in the request's `context` field,
    /// which the server places in a system message of its own behind the
    /// scope guardrail. Without it the model is told to cite only numbers it
    /// was given and then given none, which is how a coach ends up answering
    /// "how did I sleep" with nothing.
    public func reply(
        to thread: [ChatTurnMessage],
        instructions: String,
        tools: [any CoachTool],
        invoker: ToolInvoker,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> AssistantTurn.Reply {
        guard let token = accessToken(), !token.isEmpty else {
            throw RemoteEngineError.notSignedIn
        }

        var messages = thread.map {
            ChatWire.Message(role: $0.role.rawValue, content: $0.text)
        }

        // No tools means no rounds: the model either answers or it does not,
        // so there is nothing the loop below would do a second time and the
        // whole turn can be streamed. This is the coach's path. The calendar
        // assistant carries tools and takes the loop.
        if tools.isEmpty {
            return try await streamed(
                messages: messages, token: token,
                instructions: instructions, invoker: invoker, onPartial: onPartial
            )
        }

        // Bounded by the invoker's own cap rather than a second number of
        // this file's invention. One extra round is allowed on top, for the
        // reply that comes after the last permitted tool call.
        for _ in 0...ToolInvoker.invocationLimit {
            let request = try ChatWire.request(
                baseURL: baseURL, anonKey: anonKey, accessToken: token,
                messages: messages, tools: tools, context: instructions
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
                    text: CoachPresentation.clean(text, instructions: instructions),
                    toolSummaries: await invoker.toolSummaries(),
                    tier: .cloud
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
            toolSummaries: await invoker.toolSummaries(),
            tier: .cloud
        )
    }

    /// The whole turn, delivered as it is written.
    ///
    /// The answer is assembled here rather than on the screen, and the screen
    /// is handed the whole of it so far on every frame. That is what makes a
    /// dropped chunk impossible to see: there is one string, and it only grows.
    ///
    /// Cleaning is applied to the accumulated text on every yield rather than
    /// once at the end. `ResponseStyle.clean` strips markdown the model emits
    /// mid-sentence, and a screen that shows the asterisks for a beat before
    /// they disappear reads as a rendering fault rather than as a model habit.
    private func streamed(
        messages: [ChatWire.Message],
        token: String,
        instructions: String,
        invoker: ToolInvoker,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> AssistantTurn.Reply {
        let request = try ChatWire.request(
            baseURL: baseURL, anonKey: anonKey, accessToken: token,
            messages: messages, tools: [], context: instructions, stream: true
        )

        let lines: LineStream
        let response: URLResponse
        do {
            (lines, response) = try await streamTransport(request)
        } catch {
            // Offline, DNS, timeout. Transient by nature.
            throw RemoteEngineError.unavailable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        // A refusal or a spent budget arrives as an ordinary JSON body with a
        // status on it, never as a stream, so the failure is read the same way
        // it is on the unstreamed path. The body has to be collected first:
        // it is being delivered down a byte stream either way.
        guard (200..<300).contains(status) else {
            var body = ""
            for try await line in lines { body += line }
            throw RemoteWire.failure(data: Data(body.utf8), status: status)
                ?? RemoteEngineError.unavailable
        }

        var text = ""
        do {
            for try await line in lines {
                guard let payload = ChatWire.payload(inLine: line),
                      let event = ChatWire.streamEvent(payload: payload)
                else { continue }
                switch event {
                case .delta(let piece):
                    text += piece
                    onPartial(CoachPresentation.clean(text, instructions: instructions))
                case .refused(let reason):
                    throw RemoteEngineError.refused(reason)
                case .done:
                    break
                }
            }
        } catch let error as RemoteEngineError {
            throw error
        } catch {
            // The connection dropped part way. Whatever arrived is a real
            // answer cut short, and handing back half a sentence as though it
            // were the whole one is worse than saying the line went.
            throw RemoteEngineError.unavailable
        }

        // A stream that carried no text at all is the server having gone wrong
        // in a way a retry might fix, which is exactly what `unavailable`
        // means. An empty bubble is not an answer.
        guard !text.isEmpty else { throw RemoteEngineError.unavailable }

        return AssistantTurn.Reply(
            text: CoachPresentation.clean(text, instructions: instructions),
            toolSummaries: await invoker.toolSummaries(),
            tier: .cloud
        )
    }
}

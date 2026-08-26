import Testing
import Foundation
import FoundationModels
@testable import Insights

/// Records calls; scriptable result. All access from the test's actor context.
private final class SpyTool: CoachTool, @unchecked Sendable {
    let name: String
    let description = "spy"
    let requiresConfirmation: Bool
    var result: Result<String, Error> = .success("done")
    private(set) var callCount = 0

    init(name: String, gated: Bool = false) {
        self.name = name
        self.requiresConfirmation = gated
    }

    var parameters: GenerationSchema { EmptyArguments.generationSchema }
    func summary(_ arguments: GeneratedContent) -> String { "ran \(name)" }
    func call(_ arguments: GeneratedContent) async throws -> String {
        callCount += 1
        return try result.get()
    }
}

@Generable
private struct EmptyArguments {}

private struct Boom: Error, LocalizedError {
    var errorDescription: String? { "boom" }
}

@Suite struct ToolInvokerTests {
    private var noArguments: GeneratedContent { "x".generatedContent }

    @Test func anUngatedToolExecutesAndRecordsItsSummary() async {
        let tool = SpyTool(name: "read")
        let invoker = ToolInvoker(tools: [tool], broker: ConfirmationBroker())

        let result = await invoker.invoke(name: "read", arguments: noArguments)

        #expect(result == "done")
        #expect(tool.callCount == 1)
        #expect(await invoker.toolSummaries() == ["ran read"])
    }

    @Test func theSeventhInvocationIsRefused() async {
        let tool = SpyTool(name: "read")
        let invoker = ToolInvoker(tools: [tool], broker: ConfirmationBroker())

        for _ in 0..<ToolInvoker.invocationLimit {
            _ = await invoker.invoke(name: "read", arguments: noArguments)
        }
        let refused = await invoker.invoke(name: "read", arguments: noArguments)

        #expect(refused.contains("could not be completed"))
        #expect(tool.callCount == ToolInvoker.invocationLimit)
    }

    @Test func aThrowingToolReturnsItsErrorAsTheResult() async {
        let tool = SpyTool(name: "read")
        tool.result = .failure(Boom())
        let invoker = ToolInvoker(tools: [tool], broker: ConfirmationBroker())

        let result = await invoker.invoke(name: "read", arguments: noArguments)

        #expect(result.contains("boom"))
        #expect(await invoker.toolSummaries().isEmpty)
    }

    @Test func anUnknownToolNameIsAnErrorResultNotACrash() async {
        let invoker = ToolInvoker(tools: [], broker: ConfirmationBroker())
        let result = await invoker.invoke(name: "ghost", arguments: noArguments)
        #expect(result.contains("ghost"))
    }

    @Test func aGatedToolDoesNotExecuteUntilConfirmed() async throws {
        let tool = SpyTool(name: "write", gated: true)
        let broker = ConfirmationBroker()
        let invoker = ToolInvoker(tools: [tool], broker: broker)

        let turn = Task { await invoker.invoke(name: "write", arguments: noArguments) }
        let pending = try await firstPendingWrite(on: broker)
        #expect(tool.callCount == 0)
        #expect(pending.toolName == "write")

        await broker.confirm(pending.id)
        let result = await turn.value

        #expect(result == "done")
        #expect(tool.callCount == 1)
    }

    @Test func cancellingAGatedToolYieldsTheDeclinedResult() async throws {
        let tool = SpyTool(name: "write", gated: true)
        let broker = ConfirmationBroker()
        let invoker = ToolInvoker(tools: [tool], broker: broker)

        let turn = Task { await invoker.invoke(name: "write", arguments: noArguments) }
        let pending = try await firstPendingWrite(on: broker)
        await broker.cancel(pending.id)
        let result = await turn.value

        #expect(result == "User declined this change.")
        #expect(tool.callCount == 0)
        #expect(await invoker.toolSummaries().isEmpty)
    }

    /// Polls until the broker holds a pending write. The suspension inside
    /// `decision(for:)` is the structural gate under test, so the test must
    /// meet it from the outside exactly as the UI would.
    private func firstPendingWrite(on broker: ConfirmationBroker) async throws -> PendingWrite {
        for _ in 0..<200 {
            if let pending = await broker.pendingWrites().first { return pending }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw Boom()
    }
}

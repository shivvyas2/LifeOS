import Foundation

/// A gated tool call waiting on the user. Carries what the card renders;
/// the call itself stays inside the invoker, where nothing the model emits
/// can reach it.
public struct PendingWrite: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let toolName: String
    public let preview: [String]

    public init(id: UUID = UUID(), toolName: String, preview: [String]) {
        self.id = id
        self.toolName = toolName
        self.preview = preview
    }
}

/// The structural confirmation gate. `decision(for:)` suspends the tool's
/// execution path until the UI resolves it; there is no other way a gated
/// call proceeds, which is what makes the gate a property of the code rather
/// than a request in the prompt.
public actor ConfirmationBroker {
    private var pending: [PendingWrite] = []
    private var continuations: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private let onPending: @Sendable (PendingWrite) -> Void

    public init(onPending: @escaping @Sendable (PendingWrite) -> Void = { _ in }) {
        self.onPending = onPending
    }

    public func pendingWrites() -> [PendingWrite] { pending }

    func decision(for write: PendingWrite) async -> Bool {
        pending.append(write)
        onPending(write)
        return await withCheckedContinuation { continuation in
            continuations[write.id] = continuation
        }
    }

    public func confirm(_ id: UUID) { resolve(id, allowed: true) }
    public func cancel(_ id: UUID) { resolve(id, allowed: false) }

    private func resolve(_ id: UUID, allowed: Bool) {
        pending.removeAll { $0.id == id }
        continuations.removeValue(forKey: id)?.resume(returning: allowed)
    }
}

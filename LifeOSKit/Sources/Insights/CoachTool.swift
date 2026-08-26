import Foundation
import FoundationModels

/// A capability the model can invoke. General, not calendar-specific: the
/// contract lives here so the coach can adopt tools later without a new seam.
///
/// `parameters` is a `GenerationSchema`, which is Codable: the same
/// declaration binds to `LanguageModelSession` on-device today and will
/// serialize into a remote `tools[]` payload when a remote engine exists.
public protocol CoachTool: Sendable {
    var name: String { get }
    var description: String { get }
    var parameters: GenerationSchema { get }
    /// True for tools the invoker must not execute without confirmation.
    var requiresConfirmation: Bool { get }
    /// One short line for the activity chip shown after execution.
    func summary(_ arguments: GeneratedContent) -> String
    /// Lines the confirmation card renders before a gated call may run.
    /// Async so an implementation can read current state for a before/after.
    func confirmationPreview(_ arguments: GeneratedContent) async -> [String]
    func call(_ arguments: GeneratedContent) async throws -> String
}

public extension CoachTool {
    var requiresConfirmation: Bool { false }
    func summary(_ arguments: GeneratedContent) -> String { name }
    func confirmationPreview(_ arguments: GeneratedContent) async -> [String] { [name] }
}

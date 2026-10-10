import Foundation
import Integrations

/// The calls sign-in makes, as a protocol so the model can be tested without
/// a network. `SupabaseAuth` is the only production conformer.
public protocol SignInBackend: Sendable {
    func availableChannels() async -> Set<SupabaseAuth.Channel>
    func sendCode(to destination: String, channel: SupabaseAuth.Channel) async throws
    func verify(code: String, destination: String, channel: SupabaseAuth.Channel) async throws -> AuthSession
    func handoff(accessToken: String) async throws -> AuthSession
    func restore(store: any AuthSessionStoring) async -> SessionRefresher.Outcome
}

extension SupabaseAuth: SignInBackend {
    public func restore(store: any AuthSessionStoring) async -> SessionRefresher.Outcome {
        await SessionRefresher(auth: self, store: store).restore()
    }
}

import Testing
import Foundation
import Integrations
@testable import AccountUI

final class FakeBackend: SignInBackend, @unchecked Sendable {
    var channels: Set<SupabaseAuth.Channel> = [.email, .phone]
    var sendError: Error?
    var verifyResult: Result<AuthSession, Error> = .failure(AuthError.transport)
    var handoffResult: Result<AuthSession, Error> = .failure(AuthError.transport)
    var sent: [(String, SupabaseAuth.Channel)] = []

    func availableChannels() async -> Set<SupabaseAuth.Channel> { channels }
    func sendCode(to destination: String, channel: SupabaseAuth.Channel) async throws {
        if let sendError { throw sendError }
        sent.append((destination, channel))
    }
    func verify(code: String, destination: String, channel: SupabaseAuth.Channel) async throws -> AuthSession {
        try verifyResult.get()
    }
    func handoff(accessToken: String) async throws -> AuthSession { try handoffResult.get() }
    func restore(store: any AuthSessionStoring) async -> SessionRefresher.Outcome { .signedOut }
}

extension AuthSession {
    static func sample(id: String = "u1") -> AuthSession {
        AuthSession(accessToken: "a", refreshToken: "r", expiresAt: .now.addingTimeInterval(3600),
                    userID: id, phone: nil, email: "s@example.com", hasProfile: true)
    }
}

@MainActor
struct SignInModelTests {
    @Test func sendingMovesToTheCodeStepAndStartsTheCountdown() async {
        let backend = FakeBackend()
        let model = SignInModel(backend: backend, store: InMemoryAuthSessionStore(), onSignedIn: { _ in })
        model.draft.email = "s@example.com"
        await model.sendCode()
        #expect(model.step == .code)
        #expect(model.resendIn == 60)
        #expect(backend.sent.first?.0 == "s@example.com")
    }

    @Test func aFailedSMSOffersEmail() async {
        let backend = FakeBackend()
        backend.sendError = AuthError.server(status: 400, message: "sms_failed")
        let model = SignInModel(backend: backend, store: InMemoryAuthSessionStore(), onSignedIn: { _ in })
        model.switchChannel(to: .phone)
        model.draft.dialCode = "+1"
        model.draft.phone = "4155550123"
        await model.sendCode()
        #expect(model.step == .identity)
        #expect(model.phoneSendFailed)
        model.useEmailInstead()
        #expect(model.draft.channel == .email)
        #expect(!model.phoneSendFailed)
    }

    @Test func verifyingSavesTheSessionAndHandsItOver() async {
        let backend = FakeBackend()
        backend.verifyResult = .success(.sample())
        let store = InMemoryAuthSessionStore()
        var handed: AuthSession?
        let model = SignInModel(backend: backend, store: store, onSignedIn: { handed = $0 })
        model.draft.code = "123456"
        await model.verifyCode()
        #expect(model.step == .done)
        #expect(handed?.userID == "u1")
    }

    @Test func aWrongCodeStaysOnTheCodeStepWithAMessage() async {
        let backend = FakeBackend()
        backend.verifyResult = .failure(AuthError.server(status: 403, message: "otp_expired"))
        let model = SignInModel(backend: backend, store: InMemoryAuthSessionStore(), onSignedIn: { _ in })
        model.draft.code = "123456"
        await model.sendCodeStepForTesting()
        await model.verifyCode()
        #expect(model.step == .code)
        #expect(model.errorMessage != nil)
    }

    @Test func emailFallsBackToPhoneWhenEmailIsNotConfigured() async {
        let backend = FakeBackend()
        backend.channels = [.phone]
        let model = SignInModel(backend: backend, store: InMemoryAuthSessionStore(), onSignedIn: { _ in })
        await model.loadChannels()
        #expect(model.draft.channel == .phone)
    }

    @Test func noBackendMeansNotConfigured() {
        let model = SignInModel(backend: nil, store: InMemoryAuthSessionStore(), onSignedIn: { _ in })
        #expect(!model.isConfigured)
    }

    @Test func aReportedMessageShowsUntilTheNextAction() {
        let model = SignInModel(backend: FakeBackend(), store: InMemoryAuthSessionStore(), onSignedIn: { _ in })
        model.report("Your session expired. Sign in again")
        #expect(model.errorMessage == "Your session expired. Sign in again")
        model.switchChannel(to: .phone)
        #expect(model.errorMessage == nil)
    }
}

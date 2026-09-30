import Foundation

// MARK: - Mock Token Stores for Testing

/// Mock implementation of `WhoopTokenStoring` for testing.
///
/// Stores tokens in memory rather than the keychain, making tests fast and
/// isolated. Tracks what was saved and cleared for assertions.
final class MockWhoopTokenStore: WhoopTokenStoring {
    private(set) var savedToken: WhoopToken?
    private(set) var savedPending: WhoopPendingAuth?
    private(set) var loadCallCount = 0
    private(set) var clearCallCount = 0
    
    func save(_ token: WhoopToken) throws {
        savedToken = token
    }
    
    func load() -> WhoopToken? {
        loadCallCount += 1
        return savedToken
    }
    
    func clear() {
        clearCallCount += 1
        savedToken = nil
        savedPending = nil
    }
    
    func savePending(_ pending: WhoopPendingAuth) throws {
        savedPending = pending
    }
    
    func loadPending() -> WhoopPendingAuth? {
        savedPending
    }
    
    func clearPending() {
        savedPending = nil
    }
}

/// Mock implementation of `FitbitAuthStoring` for testing.
final class MockFitbitAuthStore: FitbitAuthStoring {
    private(set) var savedPending: FitbitPendingAuth?
    
    func savePending(_ pending: FitbitPendingAuth) throws {
        savedPending = pending
    }
    
    func loadPending() -> FitbitPendingAuth? {
        savedPending
    }
    
    func clearPending() {
        savedPending = nil
    }
}

/// Mock implementation of `AuthSessionStoring` for testing.
final class MockAuthSessionStore: AuthSessionStoring {
    private(set) var savedSession: AuthSession?
    private(set) var loadCallCount = 0
    private(set) var clearCallCount = 0
    
    func save(_ session: AuthSession) throws {
        savedSession = session
    }
    
    func load() -> AuthSession? {
        loadCallCount += 1
        return savedSession
    }
    
    func clear() {
        clearCallCount += 1
        savedSession = nil
    }
}

// MARK: - Test Helpers

extension MockWhoopTokenStore {
    /// Convenience for setting up a connected state in tests.
    func simulateConnected(with token: WhoopToken = .fixture) {
        savedToken = token
    }
}

extension MockFitbitAuthStore {
    /// Convenience for setting up a pending auth state in tests.
    func simulatePending(with auth: FitbitPendingAuth = .fixture) {
        savedPending = auth
    }
}

// MARK: - Test Fixtures

extension WhoopToken {
    /// A valid token for testing. Matches the shape the real OAuth flow returns.
    static let fixture = WhoopToken(
        accessToken: "test_access_token",
        refreshToken: "test_refresh_token",
        expiresAt: Date().addingTimeInterval(3600)
    )
}

extension FitbitPendingAuth {
    /// A valid pending auth for testing.
    static let fixture = FitbitPendingAuth(
        state: "test_state",
        codeVerifier: "test_verifier"
    )
}

extension WhoopPendingAuth {
    /// A valid pending auth for testing.
    static let fixture = WhoopPendingAuth(
        verifier: "test_verifier",
        state: "test_state"
    )
}

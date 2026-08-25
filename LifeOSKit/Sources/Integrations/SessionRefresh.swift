import Foundation

/// Decides, on launch, whether the stored session still signs the user in.
///
/// The rule that shapes every branch below: signing someone out is destructive
/// and cannot be undone without a fresh code, so it happens only when the
/// server has definitively refused the credential. Everything else — no
/// network, an outage, a rate limit — keeps the session and tries again later.
public struct SessionRefresher: Sendable {
    public enum Outcome: Sendable, Equatable {
        /// Nothing stored. Show onboarding.
        case signedOut
        /// Usable session, either untouched or just refreshed.
        case active(AuthSession)
        /// The server refused the refresh token. The store has been cleared.
        case rejected
    }

    private let auth: SupabaseAuth
    private let store: any AuthSessionStoring

    public init(auth: SupabaseAuth, store: any AuthSessionStoring) {
        self.auth = auth
        self.store = store
    }

    public func restore() async -> Outcome {
        guard let stored = store.load() else { return .signedOut }
        guard stored.isExpired() else { return .active(stored) }

        guard let refreshToken = stored.refreshToken, !refreshToken.isEmpty else {
            // An expired access token with no way to renew it is dead weight;
            // keeping it would only fail the next authenticated request.
            store.clear()
            return .rejected
        }

        do {
            let refreshed = try await auth.refresh(refreshToken: refreshToken)
            let session = refreshed.carryingForward(stored)
            // A keychain write failure should not cost the user this launch;
            // the session in hand is still good.
            try? store.save(session)
            return .active(session)
        } catch let error as AuthError where Self.isRefusal(error) {
            store.clear()
            return .rejected
        } catch {
            return .active(stored)
        }
    }

    /// Whether the server refused the credential itself, as opposed to failing
    /// to answer. Only these statuses are permanent; 429 and 5xx are not, and a
    /// transport error is not an answer at all.
    private static func isRefusal(_ error: AuthError) -> Bool {
        guard case .server(let status, _) = error else { return false }
        return [400, 401, 403, 422].contains(status)
    }
}

extension AuthSession {
    /// Fills the gaps in a refreshed session from the one it replaces.
    ///
    /// A refresh response is allowed to be sparse, and the magic-link path
    /// starts life with no user id at all. Neither should erase what is already
    /// known about the account.
    func carryingForward(_ previous: AuthSession) -> AuthSession {
        AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken ?? previous.refreshToken,
            expiresAt: expiresAt,
            userID: userID.isEmpty ? previous.userID : userID,
            phone: phone ?? previous.phone,
            email: email ?? previous.email
        )
    }
}

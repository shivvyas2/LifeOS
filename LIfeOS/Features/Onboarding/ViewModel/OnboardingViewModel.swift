import Foundation
import OSLog
import Integrations
import Persistence
import AccountUI

private let authLog = Logger(subsystem: "com.shivvyas.lifeos", category: "auth")

@MainActor @Observable
final class OnboardingViewModel {
    private(set) var step: OnboardingStep = .intro
    var draft = ProfileDraft()
    /// Sign-in itself: channel, address, code. Shared with the companion
    /// apps through AccountUI; this model owns only what comes after.
    private(set) var signIn: SignInModel

    private(set) var isBusy = false
    /// The profile step's error. Sign-in errors live on `signIn`.
    private(set) var errorMessage: String?

    /// Stored rather than computed from the keychain on each read, so that
    /// SwiftUI is told when it changes. A computed `store.load() != nil` is
    /// invisible to `@Observable`, which left the shell showing the app after a
    /// sign-out until something else happened to redraw it.
    private(set) var isSignedIn: Bool
    /// The session just obtained, so the scene can record the account and open
    /// its store. Held rather than only written to the keychain, because which
    /// account is open is decided above this view model and it needs the id.
    private(set) var session: AuthSession?

    private var store: any AuthSessionStoring
    /// Nil when the project is not configured, which is a development state
    /// rather than a user one: signup still completes and the profile simply
    /// stays on the device until there is somewhere to put it.
    private var profiles: ProfileClient? {
        guard let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey else { return nil }
        return ProfileClient(baseURL: url, anonKey: key)
    }
    private var auth: SupabaseAuth?
    /// The in-flight restore, so two callers share one refresh. Supabase rotates
    /// the refresh token on use, so a second concurrent refresh would present
    /// the token the first one just retired and be refused — signing the user
    /// out for doing nothing but foregrounding the app during launch.
    private var restoreTask: Task<Bool, Never>?

    init(store: any AuthSessionStoring = KeychainAuthSessionStore()) {
        self.store = store
        let restored = store.load()
        self.isSignedIn = restored != nil
        self.session = restored
        let backend: SupabaseAuth? = {
            guard let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey else { return nil }
            return SupabaseAuth(baseURL: url, anonKey: key)
        }()
        self.auth = backend
        // A placeholder so every stored property is set before the real
        // model's closure captures `self`; replaced on the next line.
        self.signIn = SignInModel(backend: backend, store: store, onSignedIn: { _ in })
        self.signIn = makeSignIn()
        if let restored {
            if UserDefaults.currentAccount.string(forKey: "onboarding.step") == "connections" {
                step = .connections
            } else {
                step = restored.hasProfile ? .signedIn : .profile
            }
        }
    }

    private func makeSignIn() -> SignInModel {
        SignInModel(backend: auth, store: store) { [weak self] session in
            self?.didSignIn(session)
        }
    }

    /// The step the flow shows. Sign-in owns identity and code; this model
    /// owns everything after.
    var visibleStep: OnboardingStep {
        guard step == .identity || step == .code else { return step }
        return signIn.step == .code ? .code : .identity
    }

    // MARK: - Navigation

    func beginSignup() {
        signIn.begin(.signUp)
        step = .identity
    }

    func beginSignIn() {
        signIn.begin(.signIn)
        step = .identity
    }

    func back() {
        errorMessage = nil
        switch step {
        case .identity, .code:
            if !signIn.back() { step = .intro }
        case .profile:
            signIn.begin(.signUp)
            step = .identity
        case .connections:
            step = .profile
        case .intro, .signedIn:
            break
        }
    }

    // MARK: - Session

    /// Renews the stored session, on launch and on every return to the
    /// foreground. Returns whether the user is still signed in.
    ///
    /// Only a refusal from the server ends the session; being offline or
    /// hitting an outage keeps it. See `SessionRefresher`.
    @discardableResult
    func restoreSession() async -> Bool {
        if let restoreTask { return await restoreTask.value }
        guard let auth else { return isSignedIn }

        let task = Task { await performRestore(auth) }
        restoreTask = task
        let result = await task.value
        restoreTask = nil
        return result
    }

    private func performRestore(_ auth: SupabaseAuth) async -> Bool {
        switch await SessionRefresher(auth: auth, store: store).restore() {
        case .active(let refreshed):
            session = refreshed
            isSignedIn = true
        case .signedOut:
            isSignedIn = false
        case .rejected:
            authLog.info("stored session was refused; returning to signup")
            signOut()
            signIn.report("Your session expired. Sign in again")
        }
        return isSignedIn
    }

    // MARK: - Auth

    /// Called by `signIn` once a code is accepted. Recording the account and
    /// routing on `hasProfile` are LifeOS decisions, so they stay here.
    private func didSignIn(_ session: AuthSession) {
        do {
            try AccountStore().add(Account(userID: session.userID,
                label: session.email ?? session.phone ?? "Account"), session: session)
        } catch {
            authLog.error("account add failed: \(String(describing: error), privacy: .public)")
        }
        AccountStore().clearLegacySession()
        store = KeychainAuthSessionStore(account: session.userID)
        self.session = session
        isSignedIn = true
        // The only thing that separates a returning user from a new one,
        // and it is known only now. The door they came through does not
        // decide this; the account does.
        step = session.hasProfile ? .signedIn : .profile
    }

    func saveProfile() async {
        guard let auth, let session = store.load(), draft.canFinishProfile else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            var profile = RemoteProfile(
                firstName: draft.firstName.trimmingCharacters(in: .whitespaces),
                lastName: draft.lastName.trimmingCharacters(in: .whitespaces),
                country: draft.country,
                birthDate: draft.birthDate,
                heightCM: draft.heightCM,
                gender: draft.gender.stored
            )

            // The picture goes to storage before the row, so the row is never
            // saved pointing at an object that does not exist. A failed upload
            // costs the picture and not the profile.
            if let photo = draft.photo, let profiles {
                profile.avatarPath = try? await profiles.uploadAvatar(
                    photo, userID: session.userID, accessToken: session.accessToken
                )
            }

            if let profiles {
                try await profiles.save(
                    profile, userID: session.userID, accessToken: session.accessToken
                )
            }
            // Written from what the server accepted, so the local copy is a
            // cache of the row rather than a second opinion about it.
            ProfileStore.save(profile)
            ProfilePhotoStore.save(draft.photo)

            // Names still go to user_metadata, because `hasProfile` is derived
            // from it when a session is restored and that is what decides
            // whether a returning user is sent through signup again.
            try await auth.updateProfile(
                accessToken: session.accessToken,
                firstName: profile.firstName,
                lastName: profile.lastName,
                country: profile.country,
                birthDate: draft.birthDate,
                heightCM: draft.heightCM,
                gender: draft.gender.stored
            )
            UserDefaults.currentAccount.set("connections", forKey: "onboarding.step")
            step = .connections
        } catch let error as AuthError {
            authLog.error("profile update failed: \(String(describing: error), privacy: .public)")
            // The account exists either way; a failed profile write must not
            // strand the user at the last step of signup.
            errorMessage = error.readable
            UserDefaults.currentAccount.set("connections", forKey: "onboarding.step")
            step = .connections
        } catch {
            UserDefaults.currentAccount.set("connections", forKey: "onboarding.step")
            step = .connections
        }
    }

    func signOut() {
        restoreTask?.cancel()
        restoreTask = nil
        store.clear()
        session = nil
        isSignedIn = false
        draft = ProfileDraft()
        signIn = makeSignIn()
        step = .intro
    }
}

extension OnboardingViewModel {
    /// What the scene needs to record this account: a stable id, and something
    /// readable beside it in the switcher.
    var account: Account? {
        guard let session else { return nil }
        return Account(
            userID: session.userID,
            label: session.email ?? session.phone ?? "Account"
        )
    }
}

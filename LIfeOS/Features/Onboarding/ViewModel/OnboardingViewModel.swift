import Foundation
import OSLog
import Integrations

typealias SupabaseAuthChannel = SupabaseAuth.Channel

private let authLog = Logger(subsystem: "com.shivvyas.lifeos", category: "auth")

@MainActor @Observable
final class OnboardingViewModel {
    private(set) var step: OnboardingStep = .intro
    var draft = SignupDraft()

    private(set) var isBusy = false
    private(set) var errorMessage: String?
    /// Seconds until the code can be requested again; 0 means it can be now.
    private(set) var resendIn = 0
    /// Empty until checked; the identity screen waits rather than offering a
    /// channel that cannot deliver.
    private(set) var availableChannels: Set<SupabaseAuthChannel> = []

    /// Stored rather than computed from the keychain on each read, so that
    /// SwiftUI is told when it changes. A computed `store.load() != nil` is
    /// invisible to `@Observable`, which left the shell showing the app after a
    /// sign-out until something else happened to redraw it.
    private(set) var isSignedIn: Bool

    private let store: any AuthSessionStoring
    private var auth: SupabaseAuth?
    /// The in-flight restore, so two callers share one refresh. Supabase rotates
    /// the refresh token on use, so a second concurrent refresh would present
    /// the token the first one just retired and be refused — signing the user
    /// out for doing nothing but foregrounding the app during launch.
    private var restoreTask: Task<Bool, Never>?

    init(store: any AuthSessionStoring = KeychainAuthSessionStore()) {
        self.store = store
        self.isSignedIn = store.load() != nil
        if let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey {
            auth = SupabaseAuth(baseURL: url, anonKey: key)
        }
        draft.dialCode = DialCountries.dial(for: draft.country)
        if !DialCountries.otpRegions.contains(draft.country) {
            draft.country = "US"
            draft.dialCode = "+1"
        }
    }

    /// Picks a channel the project can actually deliver on. Phone stays the
    /// default when SMS is configured, and quietly falls back when it is not.
    func loadChannels() async {
        guard let auth else { return }
        let channels = await auth.availableChannels()
        availableChannels = channels
        if !channels.contains(.phone), channels.contains(.email) {
            draft.channel = .email
        }
    }

    var phoneUnavailableNote: String? {
        guard !availableChannels.isEmpty, !availableChannels.contains(.phone) else { return nil }
        return "SMS isn't enabled on this project yet. Use email for now."
    }

    /// Auth cannot work without the anon key; saying so beats a signup screen
    /// whose button silently fails.
    var isConfigured: Bool { auth != nil }

    var identitySubtitle: String {
        draft.channel == .phone
            ? "We'll text you a six-digit code."
            : "We'll email you a six-digit code."
    }

    var destinationLabel: String {
        draft.channel == .phone ? draft.e164 : draft.email
    }

    // MARK: - Navigation

    func beginSignup() { step = .identity }

    func back() {
        errorMessage = nil
        switch step {
        case .intro, .identity: step = .intro
        case .code:             step = .identity
        case .profile:          step = .code
        case .connections:      step = .profile
        }
    }

    func switchChannel(to channel: SupabaseAuthChannel) {
        draft.channel = channel
        errorMessage = nil
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
        case .active:
            isSignedIn = true
        case .signedOut:
            isSignedIn = false
        case .rejected:
            authLog.info("stored session was refused; returning to signup")
            signOut()
            errorMessage = "Your session expired. Sign in again"
        }
        return isSignedIn
    }

    // MARK: - Auth

    func sendCode() async {
        guard let auth, draft.canSendCode else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            try await auth.sendCode(to: draft.destination, channel: draft.channel)
            draft.code = ""
            step = .code
            startResendCountdown()
        } catch let error as AuthError {
            authLog.error("sendCode failed: \(error.readable, privacy: .public)")
            errorMessage = error.readable
        } catch {
            errorMessage = "Couldn't send the code"
        }
    }

    func verifyCode() async {
        guard let auth, draft.canVerify else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            let session = try await auth.verify(
                code: draft.code.filter(\.isNumber),
                destination: draft.destination,
                channel: draft.channel
            )
            try store.save(session)
            isSignedIn = true
            step = .profile
        } catch let error as AuthError {
            authLog.error("verify failed: \(String(describing: error), privacy: .public)")
            errorMessage = error.readable
        } catch {
            errorMessage = "That code didn't work"
        }
    }

    func saveProfile() async {
        guard let auth, let session = store.load(), draft.canFinishProfile else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            try await auth.updateProfile(
                accessToken: session.accessToken,
                firstName: draft.firstName.trimmingCharacters(in: .whitespaces),
                lastName: draft.lastName.trimmingCharacters(in: .whitespaces),
                country: draft.country
            )
            step = .connections
        } catch let error as AuthError {
            authLog.error("profile update failed: \(String(describing: error), privacy: .public)")
            // The account exists either way; a failed profile write must not
            // strand the user at the last step of signup.
            errorMessage = error.readable
            step = .connections
        } catch {
            step = .connections
        }
    }

    func signOut() {
        store.clear()
        isSignedIn = false
        draft = SignupDraft()
        step = .intro
    }

    private func startResendCountdown() {
        resendIn = 45
        Task {
            while resendIn > 0 {
                try? await Task.sleep(for: .seconds(1))
                resendIn -= 1
            }
        }
    }
}

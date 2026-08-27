import Foundation
import OSLog
import Integrations

typealias SupabaseAuthChannel = SupabaseAuth.Channel

private let authLog = Logger(subsystem: "com.shivvyas.lifeos", category: "auth")

@MainActor @Observable
final class OnboardingViewModel {
    private(set) var step: OnboardingStep = .intro
    private(set) var mode: AuthMode = .signUp
    var draft = SignupDraft()

    private(set) var isBusy = false
    private(set) var errorMessage: String?
    /// Set when a code could not be sent over SMS. Every Twilio failure the
    /// classifier knows about is one the user cannot fix from inside the app,
    /// so the only useful next move is the other channel.
    private(set) var phoneSendFailed = false
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

    /// Picks a channel the project can actually deliver on. Email stays the
    /// default when it is configured, and quietly falls back to phone when
    /// it is not.
    func loadChannels() async {
        guard let auth else { return }
        let channels = await auth.availableChannels()
        availableChannels = channels
        if !channels.contains(.email), channels.contains(.phone) {
            draft.channel = .phone
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

    var identityTitle: String {
        mode == .signUp ? "Create your account" : "Welcome back"
    }

    var modeSwitchTitle: String {
        mode == .signUp ? "Already have an account? Sign in" : "New here? Create an account"
    }

    var destinationLabel: String {
        draft.channel == .phone ? draft.e164 : draft.email
    }

    // MARK: - Navigation

    func beginSignup() {
        mode = .signUp
        step = .identity
    }

    func beginSignIn() {
        mode = .signIn
        step = .identity
    }

    func toggleMode() {
        mode = mode == .signUp ? .signIn : .signUp
        errorMessage = nil
        phoneSendFailed = false
    }

    func back() {
        errorMessage = nil
        switch step {
        case .intro, .identity:
            // Only cleared here: a failure surfaced on CodeScreen (e.g. a
            // "Resend code" retry) must survive the .code -> .identity leg so
            // IdentityScreen can still offer the email escape.
            phoneSendFailed = false
            step = .intro
        case .code:             step = .identity
        case .profile:          step = .code
        case .connections:      step = .profile
        case .signedIn:         break
        }
    }

    func switchChannel(to channel: SupabaseAuthChannel) {
        draft.channel = channel
        errorMessage = nil
        phoneSendFailed = false
    }

    /// The one move that gets a user past a Twilio failure. Nothing in the app
    /// can make SMS deliver, so the escape has to be the other channel.
    func useEmailInstead() {
        switchChannel(to: .email)
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
        phoneSendFailed = false
        defer { isBusy = false }

        do {
            try await auth.sendCode(to: draft.destination, channel: draft.channel)
            draft.code = ""
            step = .code
            startResendCountdown()
        } catch let error as AuthError {
            authLog.error("sendCode failed: \(error.readable, privacy: .public)")
            errorMessage = error.readable
            phoneSendFailed = draft.channel == .phone
        } catch {
            errorMessage = "Couldn't send the code"
            phoneSendFailed = draft.channel == .phone
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
            // The only thing that separates a returning user from a new one,
            // and it is known only now. The door they came through does not
            // decide this; the account does.
            step = session.hasProfile ? .signedIn : .profile
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
            // The photo is written first and locally. It is the one field that
            // does not belong in user_metadata: that payload rides inside the
            // JWT on every request, and a base64 avatar would bloat every call
            // the app makes. Syncing it across devices needs a storage bucket,
            // which is a bigger change than this step.
            ProfilePhotoStore.save(draft.photo)
            ProfileStore.save(LocalProfile(
                firstName: draft.firstName.trimmingCharacters(in: .whitespaces),
                lastName: draft.lastName.trimmingCharacters(in: .whitespaces),
                country: draft.country,
                heightCM: draft.heightCM,
                birthDate: draft.birthDate,
                gender: draft.gender.stored
            ))

            try await auth.updateProfile(
                accessToken: session.accessToken,
                firstName: draft.firstName.trimmingCharacters(in: .whitespaces),
                lastName: draft.lastName.trimmingCharacters(in: .whitespaces),
                country: draft.country,
                birthDate: draft.birthDate,
                heightCM: draft.heightCM,
                gender: draft.gender.stored
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
        mode = .signUp
        step = .intro
    }

    private func startResendCountdown() {
        // 60s, not 45: phone's Edge Function cooldown (otp_guard.ts) is 45s,
        // but email posts straight to /auth/v1/otp, governed by GoTrue's
        // auth.email.max_frequency, which is 60s. The countdown has to clear
        // the stricter of the two or "Resend code" invites a 429.
        resendIn = 60
        Task {
            while resendIn > 0 {
                try? await Task.sleep(for: .seconds(1))
                resendIn -= 1
            }
        }
    }
}

import Foundation
import OSLog
import Integrations

typealias SupabaseAuthChannel = SupabaseAuth.Channel

private let authLog = Logger(subsystem: "shivvyas.LIfeOS", category: "auth")

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

    private let store: any AuthSessionStoring
    private var auth: SupabaseAuth?

    init(store: any AuthSessionStoring = KeychainAuthSessionStore()) {
        self.store = store
        if let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey {
            auth = SupabaseAuth(baseURL: url, anonKey: key)
        }
        draft.dialCode = DialCountries.dial(for: draft.country)
    }

    var isSignedIn: Bool { store.load() != nil }

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
        return "SMS isn't enabled on this project yet — use email for now."
    }

    /// Auth cannot work without the anon key; saying so beats a signup screen
    /// whose button silently fails.
    var isConfigured: Bool { auth != nil }

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
            authLog.error("sendCode failed: \(String(describing: error), privacy: .public)")
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
        draft = SignupDraft()
        step = .intro
    }

    private func startResendCountdown() {
        resendIn = 30
        Task {
            while resendIn > 0 {
                try? await Task.sleep(for: .seconds(1))
                resendIn -= 1
            }
        }
    }
}

import Foundation
import Observation
import OSLog
import Integrations

private let log = Logger(subsystem: "com.shivvyas.lifeos", category: "signin")

public enum SignInMode: Equatable, Sendable { case signUp, signIn }
public enum SignInStep: Equatable, Sendable { case identity, code, done }

/// The code sign-in both apps use: pick a channel, receive a code, verify it.
///
/// It decides nothing about what happens after. The host is handed the
/// session through `onSignedIn` and records the account in its own way, which
/// is how LifeOS keeps its multi-account store while Focus stays simple.
@MainActor @Observable
public final class SignInModel {
    public private(set) var mode: SignInMode = .signUp
    public private(set) var step: SignInStep = .identity
    public var draft = SignInDraft()
    public private(set) var isBusy = false
    public private(set) var errorMessage: String?
    /// Set when a code could not be sent over SMS. Nothing in the app can make
    /// SMS deliver, so the only useful next move is the other channel.
    public private(set) var phoneSendFailed = false
    /// Seconds until the code can be requested again; 0 means it can be now.
    public private(set) var resendIn = 0
    /// Empty until checked; the identity screen waits rather than offering a
    /// channel that cannot deliver.
    public private(set) var availableChannels: Set<SupabaseAuth.Channel> = []

    private let backend: (any SignInBackend)?
    private let store: any AuthSessionStoring
    private let onSignedIn: @MainActor (AuthSession) -> Void

    public init(backend: (any SignInBackend)?, store: any AuthSessionStoring,
                onSignedIn: @escaping @MainActor (AuthSession) -> Void) {
        self.backend = backend
        self.store = store
        self.onSignedIn = onSignedIn
        draft.dialCode = DialCountries.dial(for: draft.country)
        if !DialCountries.otpRegions.contains(draft.country) {
            draft.country = "US"
            draft.dialCode = "+1"
        }
    }

    /// Auth cannot work without the anon key; saying so beats a signup screen
    /// whose button silently fails.
    public var isConfigured: Bool { backend != nil }

    public var identityTitle: String { mode == .signUp ? "Create your account" : "Welcome back" }
    public var identitySubtitle: String {
        draft.channel == .phone ? "We'll text you a six-digit code." : "We'll email you a six-digit code."
    }
    public var modeSwitchTitle: String {
        mode == .signUp ? "Already have an account? Sign in" : "New here? Create an account"
    }
    public var destinationLabel: String { draft.channel == .phone ? draft.e164 : draft.email }
    public var phoneUnavailableNote: String? {
        guard !availableChannels.isEmpty, !availableChannels.contains(.phone) else { return nil }
        return "SMS isn't enabled on this project yet. Use email for now."
    }

    /// Which door the user came through. With OTP there is no password, so
    /// this changes copy and nothing else: the account decides what follows.
    public func begin(_ mode: SignInMode) {
        self.mode = mode
        step = .identity
        errorMessage = nil
    }

    /// Picks a channel the project can actually deliver on. Email stays the
    /// default when it is configured, and quietly falls back to phone when
    /// it is not.
    public func loadChannels() async {
        guard let backend else { return }
        let channels = await backend.availableChannels()
        availableChannels = channels
        if !channels.contains(.email), channels.contains(.phone) { draft.channel = .phone }
    }

    /// A message from the host, such as a stored session the server refused,
    /// shown on the identity screen until the next action clears it.
    public func report(_ message: String) { errorMessage = message }

    public func switchChannel(to channel: SupabaseAuth.Channel) {
        draft.channel = channel
        errorMessage = nil
        phoneSendFailed = false
    }

    /// The one move that gets a user past a Twilio failure.
    public func useEmailInstead() { switchChannel(to: .email) }

    public func toggleMode() {
        mode = mode == .signUp ? .signIn : .signUp
        errorMessage = nil
        phoneSendFailed = false
    }

    /// One step back. Returns false at the first step, so the host can leave
    /// sign-in (LifeOS goes back to its intro).
    public func back() -> Bool {
        errorMessage = nil
        switch step {
        case .identity:
            // Only cleared here: a failure surfaced on the code step (a
            // "Resend code" retry) must survive the way back so the identity
            // screen can still offer the email escape.
            phoneSendFailed = false
            return false
        case .code:
            step = .identity
            return true
        case .done:
            return false
        }
    }

    public func sendCode() async {
        guard let backend, draft.canSendCode else { return }
        isBusy = true
        errorMessage = nil
        phoneSendFailed = false
        defer { isBusy = false }
        do {
            try await backend.sendCode(to: draft.destination, channel: draft.channel)
            draft.code = ""
            step = .code
            startResendCountdown()
        } catch let error as AuthError {
            log.error("sendCode failed: \(error.readable, privacy: .public)")
            errorMessage = error.readable
            phoneSendFailed = draft.channel == .phone
        } catch {
            errorMessage = "Couldn't send the code"
            phoneSendFailed = draft.channel == .phone
        }
    }

    public func verifyCode() async {
        guard let backend, draft.canVerify else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let session = try await backend.verify(code: draft.code.filter(\.isNumber),
                                                   destination: draft.destination, channel: draft.channel)
            finish(with: session)
        } catch let error as AuthError {
            log.error("verify failed: \(String(describing: error), privacy: .public)")
            errorMessage = error.readable
        } catch {
            errorMessage = "That code didn't work"
        }
    }

    /// The account a sibling app on this phone is signed in to, if its token
    /// is fresh enough to trade. Read when the identity screen appears.
    public var sharedAccount: SignInBeacon?

    public func refreshSharedAccount() { sharedAccount = SharedSignIn.current() }

    /// One tap instead of a code. A refusal just hides the offer: the code
    /// flow underneath still works, and an error for a shortcut nobody asked
    /// to fail would only confuse.
    public func continueAsShared() async {
        guard let backend, let beacon = sharedAccount else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            // Not saved here: the host persists every session in
            // `onSignedIn`, into the slot for that account. Saving through
            // `store` could overwrite whichever account is current.
            let session = try await backend.handoff(accessToken: beacon.accessToken)
            finish(with: session)
        } catch {
            log.info("handoff refused; offering the code flow")
            sharedAccount = nil
        }
    }

    func finish(with session: AuthSession) {
        step = .done
        onSignedIn(session)
    }

    func sendCodeStepForTesting() async { step = .code }

    private func startResendCountdown() {
        // 60s, not 45: the phone function's cooldown (otp_guard.ts) is 45s,
        // but email posts straight to /auth/v1/otp, which GoTrue limits to one
        // a minute. The countdown has to clear the stricter of the two.
        resendIn = 60
        Task {
            while resendIn > 0 {
                try? await Task.sleep(for: .seconds(1))
                resendIn -= 1
            }
        }
    }
}

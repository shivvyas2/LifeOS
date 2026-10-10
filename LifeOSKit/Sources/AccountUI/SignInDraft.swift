import Foundation
import Integrations

/// What the user types to sign in, before any of it is trusted. The profile
/// fields (name, birthday, height) belong to LifeOS's own onboarding and are
/// not here: a companion app signs people in without asking for them.
public struct SignInDraft: Equatable {
    /// Email first: it is free through Resend to 3,000 a month, needs no A2P
    /// registration, and carries none of the SMS failure modes. An SMS costs
    /// about $0.05 and can fail four different ways.
    public var channel: SupabaseAuth.Channel = .email
    public var phone = ""
    public var dialCode = "+1"
    public var email = ""
    public var code = ""
    public var country = Locale.current.region?.identifier ?? "US"

    public init() {}

    /// E.164, which is what Supabase expects for SMS.
    public var e164: String { dialCode + phone.filter(\.isNumber) }

    public var destination: String {
        channel == .phone ? e164 : email.trimmingCharacters(in: .whitespaces)
    }

    public var canSendCode: Bool {
        channel == .phone
            ? PhoneOTP.isAcceptable(e164)
            : email.contains("@") && email.contains(".")
    }

    public var canVerify: Bool { code.filter(\.isNumber).count >= 6 }
}

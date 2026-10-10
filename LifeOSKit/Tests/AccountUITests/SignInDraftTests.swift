import Testing
@testable import AccountUI

struct SignInDraftTests {
    @Test func emailIsTrimmedForTheDestination() {
        var draft = SignInDraft()
        draft.channel = .email
        draft.email = "  shiv@example.com "
        #expect(draft.destination == "shiv@example.com")
        #expect(draft.canSendCode)
    }

    @Test func phoneBuildsE164FromDialCodeAndDigits() {
        var draft = SignInDraft()
        draft.channel = .phone
        draft.dialCode = "+1"
        draft.phone = "(415) 555-0123"
        #expect(draft.e164 == "+14155550123")
        #expect(draft.destination == "+14155550123")
    }

    @Test func verifyNeedsSixDigits() {
        var draft = SignInDraft()
        draft.code = "12 34 5"
        #expect(!draft.canVerify)
        draft.code = "123456"
        #expect(draft.canVerify)
    }

    @Test func unknownRegionsFallBackToPlusOne() {
        #expect(DialCountries.dial(for: "ZZ") == "+1")
        #expect(DialCountries.otpRegions.contains("US"))
    }
}

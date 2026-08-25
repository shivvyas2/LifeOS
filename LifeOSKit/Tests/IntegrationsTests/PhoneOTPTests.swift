import Testing
import Integrations

@Suite
struct PhoneOTPTests {
    @Test func indianMobilesAreAccepted() {
        #expect(PhoneOTP.isAcceptable("+919876543210"))
        #expect(PhoneOTP.normalized("91 98765 43210") == "+919876543210")
        #expect(PhoneOTP.pumpingPrefix("+919876543210") == "919876")
    }

    @Test func indianLandlineLengthIsRejected() {
        #expect(!PhoneOTP.isAcceptable("+911123456789"))
        #expect(!PhoneOTP.isAcceptable("+915123456789"))
        #expect(!PhoneOTP.isAcceptable("+91987654321"))
    }

    @Test func usAndTheLocalTestNumberAreAccepted() {
        #expect(PhoneOTP.isAcceptable("+11234567890"))
        #expect(PhoneOTP.isAcceptable("+14155552671"))
        #expect(PhoneOTP.isAcceptable("1 (415) 555-2671"))
    }

    @Test func otherCountriesAreRejected() {
        #expect(!PhoneOTP.isAcceptable("+447911123456"))
        #expect(!PhoneOTP.isAcceptable("+61412345678"))
    }

    @Test func shortAndNonNumericValuesAreRejected() {
        #expect(PhoneOTP.normalized("123") == nil)
        #expect(!PhoneOTP.isAcceptable("not-a-number"))
        #expect(!PhoneOTP.isAcceptable("+123"))
    }
}

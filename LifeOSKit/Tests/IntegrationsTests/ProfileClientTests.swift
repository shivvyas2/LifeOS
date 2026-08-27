import Testing
import Foundation
@testable import Integrations

@Suite struct RemoteProfileTests {

    private func sample() -> RemoteProfile {
        RemoteProfile(
            firstName: "Ada", lastName: "Lovelace", country: "GB",
            birthDate: Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000)),
            heightCM: 168, gender: "woman", avatarPath: "user-1/avatar.jpg"
        )
    }

    @Test func aProfileSurvivesTheRoundTrip() {
        let decoded = RemoteProfile(json: sample().payload(userID: "user-1"))

        #expect(decoded.firstName == "Ada")
        #expect(decoded.lastName == "Lovelace")
        #expect(decoded.country == "GB")
        #expect(decoded.heightCM == 168)
        #expect(decoded.gender == "woman")
        #expect(decoded.avatarPath == "user-1/avatar.jpg")
    }

    /// A birthday has no clock, and a timestamp would move it by a day across
    /// time zones.
    @Test func aBirthdayComesBackOnTheSameCalendarDay() throws {
        let profile = sample()
        let decoded = RemoteProfile(json: profile.payload(userID: "user-1"))
        let original = try #require(profile.birthDate)
        let returned = try #require(decoded.birthDate)

        #expect(Calendar.current.isDate(returned, inSameDayAs: original))
    }

    /// The row is upserted whole, so a cleared field has to clear on the
    /// server. An omitted key would leave the old value standing and make
    /// deleting a birthday impossible.
    @Test func clearedFieldsAreSentAsNullsRatherThanOmitted() {
        let payload = RemoteProfile(firstName: "Ada").payload(userID: "user-1")

        #expect(payload["birth_date"] is NSNull)
        #expect(payload["height_cm"] is NSNull)
        #expect(payload["gender"] is NSNull)
        #expect(payload["avatar_path"] is NSNull)
    }

    /// The column is not nullable and search reads it, so a profile with no
    /// name still needs one.
    @Test func displayNameIsNeverEmpty() {
        #expect(RemoteProfile().displayName == "Someone")
        #expect(RemoteProfile(firstName: "Ada").displayName == "Ada")
        #expect(RemoteProfile(firstName: "Ada", lastName: "Lovelace").displayName == "Ada Lovelace")
        #expect(!RemoteProfile().payload(userID: "u")["display_name"].debugDescription.isEmpty)
    }

    /// One folder per account, named for the user id. That is what makes the
    /// storage policy a string comparison rather than a lookup, so it has to
    /// stay exactly this shape.
    @Test func theAvatarPathIsTheAccountsOwnFolder() {
        #expect(ProfileClient.avatarPath(userID: "abc-123") == "abc-123/avatar.jpg")
        #expect(ProfileClient.avatarPath(userID: "abc-123").hasPrefix("abc-123/"))
    }

    @Test func anEmptyRowDecodesToAnEmptyProfile() {
        let decoded = RemoteProfile(json: [:])
        #expect(decoded.firstName.isEmpty)
        #expect(decoded.birthDate == nil)
        #expect(decoded.avatarPath == nil)
    }
}

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

/// Its own stub rather than a shared one. The reply queue is static, and two
/// suites drawing from one queue answer each other's requests as soon as the
/// runner interleaves them.
final class AvatarStubURLProtocol: URLProtocol {
    struct Seen { let method: String; let url: URL; let headers: [String: String] }

    nonisolated(unsafe) static var replies: [(Int, Data)] = []
    nonisolated(unsafe) static var seen: [Seen] = []

    static func reset() { replies = []; seen = [] }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.seen.append(Seen(
            method: request.httpMethod ?? "GET",
            url: request.url!,
            headers: request.allHTTPHeaderFields ?? [:]
        ))

        let (status, body) = Self.replies.isEmpty ? (500, Data()) : Self.replies.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct AvatarTransferTests {
    private let baseURL = URL(string: "https://project.supabase.co")!

    private func makeClient(_ replies: [(Int, Data)]) -> ProfileClient {
        AvatarStubURLProtocol.reset()
        AvatarStubURLProtocol.replies = replies
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AvatarStubURLProtocol.self]
        return ProfileClient(
            baseURL: baseURL, anonKey: "anon-key",
            session: URLSession(configuration: configuration)
        )
    }

    // MARK: - Reading

    /// The bucket is private now, so the public route answers nothing and the
    /// read has to be the authenticated one, carrying a token.
    @Test func downloadingAnAvatarGoesThroughTheAuthenticatedRouteWithABearerToken() async throws {
        let client = makeClient([(200, Data("jpeg-bytes".utf8))])

        let data = try await client.downloadAvatar(path: "user-1/avatar.jpg", accessToken: "tok-1")

        #expect(data == Data("jpeg-bytes".utf8))
        let seen = try #require(AvatarStubURLProtocol.seen.first)
        #expect(seen.url.path == "/storage/v1/object/authenticated/avatars/user-1/avatar.jpg")
        #expect(!seen.url.path.contains("/object/public/"))
        #expect(seen.headers["Authorization"] == "Bearer tok-1")
        #expect(seen.headers["apikey"] == "anon-key")
    }

    // MARK: - Stamps

    @Test func aListingWithATimestampReportsIt() async throws {
        let body = Data(#"[{"name":"avatar.jpg","updated_at":"2026-08-27T10:00:00Z"}]"#.utf8)
        let client = makeClient([(200, body)])

        let stamp = try await client.avatarStamp(path: "user-1/avatar.jpg", accessToken: "tok-1")

        #expect(stamp == .at("2026-08-27T10:00:00Z"))
        let seen = try #require(AvatarStubURLProtocol.seen.first)
        #expect(seen.method == "POST")
        #expect(seen.url.path == "/storage/v1/object/list/avatars")
        #expect(seen.headers["Authorization"] == "Bearer tok-1")
    }

    @Test func aListingWithoutTheObjectReportsItMissing() async throws {
        let client = makeClient([(200, Data("[]".utf8))])

        let stamp = try await client.avatarStamp(path: "user-1/avatar.jpg", accessToken: "tok-1")

        #expect(stamp == .missing)
    }

    /// The case that has to stay distinct from `.missing`: the object is
    /// there, the listing just did not say when it changed.
    @Test func anObjectWithNoTimestampIsUnknownRatherThanMissing() async throws {
        let client = makeClient([(200, Data(#"[{"name":"avatar.jpg"}]"#.utf8))])

        let stamp = try await client.avatarStamp(path: "user-1/avatar.jpg", accessToken: "tok-1")

        #expect(stamp == .unknown)
    }

    // MARK: - Deciding

    /// The whole point of the stamp: the remote path never changes, so a
    /// replaced photo is only visible as a different timestamp.
    @Test func aChangedStampReDownloads() {
        #expect(ProfileClient.shouldDownloadAvatar(
            stamp: .at("2026-08-27T10:00:00Z"), recorded: "2026-08-01T09:00:00Z",
            hasLocalCopy: true
        ))
    }

    @Test func anUnchangedStampDoesNotReDownload() {
        #expect(!ProfileClient.shouldDownloadAvatar(
            stamp: .at("2026-08-27T10:00:00Z"), recorded: "2026-08-27T10:00:00Z",
            hasLocalCopy: true
        ))
    }

    @Test func aStampWithNothingCachedStillDownloads() {
        #expect(ProfileClient.shouldDownloadAvatar(
            stamp: .at("2026-08-27T10:00:00Z"), recorded: "2026-08-27T10:00:00Z",
            hasLocalCopy: false
        ))
    }

    /// A device with nothing cached must never be left downloading nothing
    /// because the stamp could not be read, which is what a bare optional
    /// conflating this with `.missing` would have caused.
    @Test func anUnknownStampDownloadsOnlyWhenThereIsNoLocalCopy() {
        #expect(ProfileClient.shouldDownloadAvatar(
            stamp: .unknown, recorded: nil, hasLocalCopy: false
        ))
        #expect(!ProfileClient.shouldDownloadAvatar(
            stamp: .unknown, recorded: "2026-08-01T09:00:00Z", hasLocalCopy: true
        ))
    }

    /// The row still points at a path, but the object behind it is gone, so a
    /// download would only earn a 404.
    @Test func aMissingObjectIsNeverDownloaded() {
        #expect(!ProfileClient.shouldDownloadAvatar(
            stamp: .missing, recorded: nil, hasLocalCopy: false
        ))
    }
}

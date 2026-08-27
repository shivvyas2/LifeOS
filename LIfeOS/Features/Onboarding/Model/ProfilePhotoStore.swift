import Foundation
import Persistence
import Integrations
import OSLog

/// A local copy of the avatar, cached per account.
///
/// The picture itself lives in Supabase Storage now, so it follows the account
/// to another device. This is the copy that means a profile screen draws
/// instantly instead of after a round trip, and still draws with no network.
///
/// Keyed by account. It was a single file at a fixed path, which was fine
/// while one person could be signed in and became a leak the moment two could:
/// the second account opened the first account's face.
enum ProfilePhotoStore {
    private static let log = Logger(subsystem: "com.shivvyas.lifeos", category: "profile")

    /// Inside the open account's own directory, beside its store, so it is
    /// removed with the account and can never be shown to another one.
    private static var url: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }

        guard let id = UserDefaults.standard.string(
            forKey: KeychainAuthSessionStore.currentAccountKey
        ) else { return nil }

        let directory = UserScope(id: id).directory(base: base)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("avatar.jpg")
    }

    /// When the object this copy came from last changed on the server.
    ///
    /// Per account, like the file itself. The remote path never changes: it is
    /// `{user_id}/avatar.jpg` for the life of the account. So without a stamp
    /// there is nothing to compare, and a photo replaced on one phone stayed
    /// invisible on the other, which was pinned to whatever it downloaded
    /// first.
    private static let stampKey = "avatarStamp"

    static func stamp() -> String? {
        UserDefaults.currentAccount.string(forKey: stampKey)
    }

    static func recordStamp(_ value: String) {
        UserDefaults.currentAccount.set(value, forKey: stampKey)
    }

    /// Passing nil clears it, so removing a photo is the same call as setting
    /// one and cannot leave a stale image behind.
    static func save(_ data: Data?) {
        guard let url else { return }
        // The stamp describes the bytes on disk, so it is dropped whenever
        // they change. A photo taken on this device has no server stamp yet,
        // and keeping the old one would make the next sync believe the copy it
        // holds is the one already up there.
        UserDefaults.currentAccount.removeObject(forKey: stampKey)
        do {
            if let data {
                try data.write(to: url, options: .atomic)
            } else if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            // A missing avatar is a cosmetic loss and never worth failing
            // signup over, which is why this is logged rather than thrown.
            log.error("could not store profile photo: \(String(describing: error), privacy: .public)")
        }
    }

    static func load() -> Data? {
        guard let url else { return nil }
        return try? Data(contentsOf: url)
    }
}

/// The profile fields the app shows back to the user.
///
/// Kept beside the photo rather than read from the session, because the
/// session does not carry them: `user_metadata` is written to Supabase during
/// signup and the decoded `AuthSession` only keeps what the app needs to stay
/// signed in. Rather than widen that type and re-fetch the user on every
/// launch to render a name, the same values are recorded locally when they are
/// saved.
///
/// The server copy stays the source of truth. This is a cache for display, and
/// it is written at exactly the moment the server write succeeds.
struct LocalProfile: Codable, Equatable {
    var firstName = ""
    var lastName = ""
    var country = ""
    var heightCM: Double?
    var birthDate: Date?
    var gender: String?

    var fullName: String {
        [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// A local copy of the profile row, per account.
///
/// The row on the server is the source of truth. This exists so the profile
/// screen has something to draw before the fetch returns and something to draw
/// when there is no network, and it is written from whatever the server last
/// confirmed rather than from what was typed.
///
/// Per account for the same reason the avatar is: in the shared suite, the
/// second account to sign in was shown the first one's name.
enum ProfileStore {
    private static let key = "localProfile"

    static func save(_ profile: LocalProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.currentAccount.set(data, forKey: key)
    }

    static func load() -> LocalProfile {
        guard let data = UserDefaults.currentAccount.data(forKey: key),
              let profile = try? JSONDecoder().decode(LocalProfile.self, from: data)
        else { return LocalProfile() }
        return profile
    }

    /// Mirrors what the server confirmed, so the two cannot drift.
    static func save(_ remote: RemoteProfile) {
        save(LocalProfile(
            firstName: remote.firstName,
            lastName: remote.lastName,
            country: remote.country,
            heightCM: remote.heightCM,
            birthDate: remote.birthDate,
            gender: remote.gender
        ))
    }

    static func remote() -> RemoteProfile {
        let local = load()
        return RemoteProfile(
            firstName: local.firstName,
            lastName: local.lastName,
            country: local.country,
            birthDate: local.birthDate,
            heightCM: local.heightCM,
            gender: local.gender
        )
    }
}

/// Brings the profile down from the server into the local caches.
///
/// The point of the whole change: signing in on a second phone, or as a second
/// account on this one, used to produce a profile with no name and no picture,
/// because both lived only on the device that typed them.
///
/// Runs on every launch that has a session. It is two small requests, the
/// second only when there is a picture and it has changed, and it is what
/// makes the server the source of truth rather than a place a copy was once
/// sent to.
enum ProfileSync {
    private static let log = Logger(subsystem: "com.shivvyas.lifeos", category: "profile")

    static func pull() async {
        guard let url = AppConfig.supabaseURL,
              let key = AppConfig.supabaseAnonKey,
              let session = KeychainAuthSessionStore().load()
        else { return }

        let client = ProfileClient(baseURL: url, anonKey: key)
        guard let remote = try? await client.load(
            userID: session.userID, accessToken: session.accessToken
        ) else { return }

        ProfileStore.save(remote)

        guard let path = remote.avatarPath else {
            // The server says there is no picture, so neither should the
            // device. Without this, removing a photo on one phone would leave
            // it in place on the other forever.
            ProfilePhotoStore.save(nil)
            return
        }

        // The avatar changes rarely, so re-downloading it on every launch
        // would spend bandwidth to learn nothing. But the path is constant, so
        // "have I got a copy" is not the question either: that pinned a phone
        // to the first picture it ever saw, and a photo replaced on another
        // device never arrived. The stamp is what tells the two apart.
        //
        // A failed lookup reads as `.unknown` rather than as an error, so a
        // flaky network costs at most a stale face and never a blank one.
        let stamp = (try? await client.avatarStamp(
            path: path, accessToken: session.accessToken
        )) ?? .unknown

        guard ProfileClient.shouldDownloadAvatar(
            stamp: stamp,
            recorded: ProfilePhotoStore.stamp(),
            hasLocalCopy: ProfilePhotoStore.load() != nil
        ) else { return }

        if let data = try? await client.downloadAvatar(
            path: path, accessToken: session.accessToken
        ) {
            // Saving clears the stamp, so it is recorded after, and only when
            // the listing actually gave one. Recording nothing here means the
            // next launch checks again rather than believing it is current.
            ProfilePhotoStore.save(data)
            if case .at(let current) = stamp { ProfilePhotoStore.recordStamp(current) }
        } else {
            log.error("avatar download failed")
        }
    }
}

import Foundation
import OSLog

/// Where the avatar lives.
///
/// On disk in the app's support directory, not in `user_metadata`: that
/// payload is carried inside the JWT on every authenticated request, so a
/// base64 image there would be paid for on every call the app makes. It is
/// also not in UserDefaults, which is loaded whole into memory and is the
/// wrong home for half a megabyte of JPEG.
///
/// The consequence, stated plainly because it will surprise someone: the photo
/// does not follow the account to a second device. Making it do so needs a
/// Supabase Storage bucket and its policies, which is a larger change than the
/// signup step it was added to.
enum ProfilePhotoStore {
    private static let log = Logger(subsystem: "com.shivvyas.lifeos", category: "profile")

    private static var url: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil,
                                     create: true)
            .appendingPathComponent("profile-photo.jpg")
    }

    /// Passing nil clears it, so removing a photo is the same call as setting
    /// one and cannot leave a stale image behind.
    static func save(_ data: Data?) {
        guard let url else { return }
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

enum ProfileStore {
    private static let key = "localProfile"

    static func save(_ profile: LocalProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> LocalProfile {
        guard let data = UserDefaults.standard.data(forKey: key),
              let profile = try? JSONDecoder().decode(LocalProfile.self, from: data)
        else { return LocalProfile() }
        return profile
    }
}

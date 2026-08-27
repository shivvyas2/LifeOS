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

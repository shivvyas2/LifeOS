import Foundation

/// Whose data is loaded.
///
/// There is no signed-out scope. Signing in is required, so there is always
/// exactly one account whose store is open, or no store open at all.
///
/// The app had no answer to this question, which meant it had one answer for
/// everybody: a single store file, no owning column on any model, and one
/// keychain slot. A second person signing in on the same device inherited the
/// first person's notes, journal, chat history, money and health data. The
/// server was never the problem, since Supabase issues each user a UUID and
/// Row Level Security scopes every row to `auth.uid()`; the device was.
///
/// Isolation is by store file rather than by an owner column on forty models.
/// A column means a predicate on every read, and a predicate forgotten once is
/// a leak that looks like working software. A separate file cannot leak: the
/// rows are not there to be read.
public struct UserScope: Hashable, Sendable, Codable {
    /// The Supabase user id, or `guest` for the signed-out store.
    public let id: String

    public init(id: String) {
        self.id = id
    }

    /// Where this account's store lives.
    ///
    /// Under Application Support, which is backed up and not user visible, in
    /// a directory named for the account. Creating the directory is the
    /// caller's job, since a failure there is a launch failure and belongs
    /// where it can be reported.
    public func storeURL(base: URL) -> URL {
        directory(base: base).appendingPathComponent("store.sqlite")
    }

    public func directory(base: URL) -> URL {
        base.appendingPathComponent("Accounts", isDirectory: true)
            .appendingPathComponent(safeDirectoryName, isDirectory: true)
    }

    /// A user id is a UUID and a directory name is a path component, so this
    /// is belt and braces rather than a real fear. It costs nothing and means
    /// a malformed id can never escape the accounts directory.
    private var safeDirectoryName: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = id.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return cleaned.isEmpty ? "unknown" : String(cleaned)
    }

    /// A defaults suite of this account's own.
    ///
    /// Sync cursors, connection tokens and "have they seen the tour" are all
    /// per account, and all of them were in the shared suite. A second account
    /// would have resumed a notes pull from the first account's cursor and
    /// silently missed every row written in between.
    ///
    /// Device preferences stay in `standard` on purpose: appearance, the
    /// assistant's voice and which engine answers belong to the phone, not to
    /// whoever is signed in on it.
    public var defaultsSuiteName: String { "account.\(safeDirectoryName)" }
}

public extension UserDefaults {
    /// The defaults belonging to whichever account is open.
    ///
    /// Sync cursors, connection tokens and "have they seen the tour" are all
    /// per account and were all in the shared suite. The worst of them was the
    /// notes cursor: a second account would have resumed its first pull from
    /// the first account's cursor and silently missed every row written before
    /// it, which looks like data loss and is unrecoverable without knowing to
    /// clear a key nobody can see.
    ///
    /// Device preferences stay in `standard` on purpose. Appearance, the
    /// assistant's voice and which engine answers belong to the phone, not to
    /// whoever is signed in on it.
    static var currentAccount: UserDefaults {
        guard let id = standard.string(forKey: "accounts.current"),
              let suite = UserDefaults(suiteName: UserScope(id: id).defaultsSuiteName)
        else { return standard }
        return suite
    }
}

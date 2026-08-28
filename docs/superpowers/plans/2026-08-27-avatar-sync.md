# Avatar Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Get profile photos off the device and into a private Supabase Storage bucket, so a photo follows the account to a second device and the admin dashboard can show it.

**Architecture:** A private `avatars` bucket keyed `{user_id}/avatar.jpg`, read through short-lived signed URLs. A `SupabaseStorage` client in `Integrations` mirrors the shape of `SupabaseAuth`. The existing on-disk photo becomes a per-account cache rather than the only copy.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing (`@Suite` / `@Test`), Supabase Storage REST v1, Postgres RLS.

**Spec:** `docs/superpowers/specs/2026-08-27-admin-dashboard-design.md` (sub-project A)

## Global Constraints

- Branch per logical change, never commit to `main`. Conventional commits: `type(scope): imperative summary`, with a body explaining what and why.
- No em dashes in commit messages.
- No Claude attribution of any kind in commits.
- RLS is enabled on every table without exception, and every policy scopes to `auth.uid()`. Storage policies follow the same rule.
- A failed avatar upload must never fail signup. The account exists either way, and nothing at the last step of signup may strand a user who already has a working account.
- Tests run with `cd LifeOSKit && swift test --filter <SuiteName>`.
- Work in a private worktree under `.claude/worktrees/`, since peer sessions move HEAD in the shared checkout.

---

## Why Task 1 exists

`df18113 feat(auth): give every account its own store` isolated the SwiftData store, the keychain session, sync cursors, Whoop straps and bank connections per account. It missed two stores, both living in `LIfeOS/Features/Onboarding/Model/ProfilePhotoStore.swift`:

- `ProfilePhotoStore` writes to a single fixed path, `profile-photo.jpg`.
- `ProfileStore` writes to a single `UserDefaults` key, `localProfile`.

On a device with two accounts, the second account sees the first account's face, name, height, birth date and gender. That is precisely the leak `df18113` set out to close.

It has to be fixed here regardless, because everything downstream keys by user id. Task 1 fixes it and moves both stores into `Integrations`, beside `KeychainAuthSessionStore`, which already does this exact per-account job and holds the account key these stores need.

---

### Task 1: Scope the profile caches per account

**Files:**
- Create: `LifeOSKit/Sources/Integrations/ProfileCache.swift`
- Delete: `LIfeOS/Features/Onboarding/Model/ProfilePhotoStore.swift`
- Modify: `LIfeOS/App/RootView.swift:78,126`
- Modify: `LIfeOS/Features/Settings/View/ProfileScreen.swift:29,68`
- Modify: `LIfeOS/Features/Onboarding/ViewModel/OnboardingViewModel.swift:239-247`
- Modify: `LIfeOS/Features/Settings/View/ProfileEditSheet.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/ProfileCacheTests.swift`

**Interfaces:**
- Consumes: `KeychainAuthSessionStore.currentAccountKey`, `KeychainAuthSessionStore.legacyAccount` (both already public in `Integrations`).
- Produces:
  - `ProfilePhotoStore.currentAccount() -> String`
  - `ProfilePhotoStore.filename(for account: String) -> String`
  - `ProfilePhotoStore.save(_ data: Data?, account: String = currentAccount())`
  - `ProfilePhotoStore.load(account: String = currentAccount()) -> Data?`
  - `ProfileStore.key(for account: String) -> String`
  - `ProfileStore.save(_ profile: LocalProfile, account: String = ..., defaults: UserDefaults = .standard)`
  - `ProfileStore.load(account: String = ..., defaults: UserDefaults = .standard) -> LocalProfile`
  - `struct LocalProfile: Codable, Equatable` with `firstName`, `lastName`, `country`, `heightCM`, `birthDate`, `gender`, `fullName`

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/IntegrationsTests/ProfileCacheTests.swift`:

```swift
import Testing
import Foundation
@testable import Integrations

/// `df18113` gave every account its own store and missed these two. A second
/// account on a shared device must not see the first account's face or name.
@Suite struct ProfileCacheTests {
    @Test func twoAccountsGetDifferentPhotoFiles() {
        let a = ProfilePhotoStore.filename(for: "user-a")
        let b = ProfilePhotoStore.filename(for: "user-b")
        #expect(a != b)
        #expect(a.contains("user-a"))
        #expect(a.hasSuffix(".jpg"))
    }

    @Test func twoAccountsGetDifferentProfileKeys() {
        #expect(ProfileStore.key(for: "user-a") != ProfileStore.key(for: "user-b"))
    }

    @Test func aProfileRoundTripsWithinOneAccount() {
        let defaults = UserDefaults(suiteName: "profile-cache-tests")!
        defaults.removePersistentDomain(forName: "profile-cache-tests")

        let profile = LocalProfile(
            firstName: "Ada", lastName: "Lovelace", country: "GB",
            heightCM: 170, birthDate: nil, gender: "female"
        )
        ProfileStore.save(profile, account: "user-a", defaults: defaults)

        #expect(ProfileStore.load(account: "user-a", defaults: defaults) == profile)
        #expect(ProfileStore.load(account: "user-b", defaults: defaults) == LocalProfile())
    }

    @Test func aMissingProfileIsEmptyRatherThanNil() {
        let defaults = UserDefaults(suiteName: "profile-cache-empty")!
        defaults.removePersistentDomain(forName: "profile-cache-empty")
        #expect(ProfileStore.load(account: "nobody", defaults: defaults).fullName.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd LifeOSKit && swift test --filter ProfileCacheTests`
Expected: FAIL to compile, "cannot find 'ProfilePhotoStore' in scope"

- [ ] **Step 3: Write the implementation**

Create `LifeOSKit/Sources/Integrations/ProfileCache.swift`. This is the existing file's content, moved, made `public`, and scoped by account:

```swift
import Foundation
import OSLog

/// Where the avatar lives on this device.
///
/// On disk in the app's support directory, not in `user_metadata`: that
/// payload is carried inside the JWT on every authenticated request, so a
/// base64 image there would be paid for on every call the app makes. It is
/// also not in UserDefaults, which is loaded whole into memory and is the
/// wrong home for half a megabyte of JPEG.
///
/// Scoped by account for the same reason `KeychainAuthSessionStore` is: one
/// device can hold several accounts, and an unscoped file shows the second
/// person the first person's face.
///
/// Since the `avatars` bucket exists this is a cache, not the only copy.
public enum ProfilePhotoStore {
    private static let log = Logger(subsystem: "com.shivvyas.lifeos", category: "profile")

    /// Mirrors `KeychainAuthSessionStore`'s default: whichever account is
    /// current, falling back to the pre-accounts name so an upgraded install
    /// finds what it already had.
    public static func currentAccount() -> String {
        UserDefaults.standard.string(forKey: KeychainAuthSessionStore.currentAccountKey)
            ?? KeychainAuthSessionStore.legacyAccount
    }

    /// Pure, so the per-account guarantee can be tested without touching disk.
    public static func filename(for account: String) -> String {
        "profile-photo-\(account).jpg"
    }

    private static func url(for account: String) -> URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil,
                                     create: true)
            .appendingPathComponent(filename(for: account))
    }

    /// Passing nil clears it, so removing a photo is the same call as setting
    /// one and cannot leave a stale image behind.
    public static func save(_ data: Data?, account: String = currentAccount()) {
        guard let url = url(for: account) else { return }
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

    public static func load(account: String = currentAccount()) -> Data? {
        guard let url = url(for: account) else { return nil }
        return try? Data(contentsOf: url)
    }
}

/// The profile fields the app shows back to the user.
///
/// The server copy stays the source of truth. This is a cache for display, and
/// it is written at exactly the moment the server write succeeds.
public struct LocalProfile: Codable, Equatable {
    public var firstName = ""
    public var lastName = ""
    public var country = ""
    public var heightCM: Double?
    public var birthDate: Date?
    public var gender: String?

    public init(firstName: String = "", lastName: String = "", country: String = "",
                heightCM: Double? = nil, birthDate: Date? = nil, gender: String? = nil) {
        self.firstName = firstName
        self.lastName = lastName
        self.country = country
        self.heightCM = heightCM
        self.birthDate = birthDate
        self.gender = gender
    }

    public var fullName: String {
        [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

public enum ProfileStore {
    /// Pure, for the same reason `ProfilePhotoStore.filename` is.
    public static func key(for account: String) -> String { "localProfile.\(account)" }

    public static func save(_ profile: LocalProfile,
                            account: String = ProfilePhotoStore.currentAccount(),
                            defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: key(for: account))
    }

    public static func load(account: String = ProfilePhotoStore.currentAccount(),
                            defaults: UserDefaults = .standard) -> LocalProfile {
        guard let data = defaults.data(forKey: key(for: account)),
              let profile = try? JSONDecoder().decode(LocalProfile.self, from: data)
        else { return LocalProfile() }
        return profile
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd LifeOSKit && swift test --filter ProfileCacheTests`
Expected: PASS, 4 tests

- [ ] **Step 5: Delete the old file and fix the call sites**

Delete `LIfeOS/Features/Onboarding/Model/ProfilePhotoStore.swift`.

Add `import Integrations` to any of these that lacks it, then build. The call sites do not change shape, because the new parameters are defaulted:

- `LIfeOS/App/RootView.swift:78` and `:126` call `ProfilePhotoStore.load()`
- `LIfeOS/Features/Settings/View/ProfileScreen.swift:29` calls `ProfilePhotoStore.load()`, `:68` calls `ProfilePhotoStore.save(newPhoto)`
- `LIfeOS/Features/Onboarding/ViewModel/OnboardingViewModel.swift:239` calls `ProfilePhotoStore.save(draft.photo)`, `:240` calls `ProfileStore.save(LocalProfile(...))`
- `LIfeOS/Features/Settings/View/ProfileEditSheet.swift` constructs `LocalProfile`

Also remove the now-stale sentence from the type comment, since the photo will follow the account after Task 5: the old text said "the photo does not follow the account to a second device".

- [ ] **Step 6: Build the app to confirm the move**

Run: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 7: Commit**

```bash
git add LifeOSKit/Sources/Integrations/ProfileCache.swift \
        LifeOSKit/Tests/IntegrationsTests/ProfileCacheTests.swift \
        LIfeOS/Features/Onboarding/Model/ProfilePhotoStore.swift \
        LIfeOS/App/RootView.swift \
        LIfeOS/Features/Settings/View/ProfileScreen.swift \
        LIfeOS/Features/Settings/View/ProfileEditSheet.swift \
        LIfeOS/Features/Onboarding/ViewModel/OnboardingViewModel.swift
git commit -F - <<'EOF'
fix(profile): give every account its own photo and profile cache

Accounts scoped the SwiftData store, the keychain session, sync cursors,
straps and bank connections. These two stores were missed: the photo went
to one fixed file and the profile to one UserDefaults key, so a second
account on a shared device saw the first account's face, name, height,
birth date and gender.

Moves both into Integrations beside KeychainAuthSessionStore, which
already does this per-account job and owns the account key they need.
EOF
```

---

### Task 2: The avatars bucket and its policies

**Files:**
- Create: `supabase/migrations/20260827160000_avatars_bucket.sql`

**Interfaces:**
- Consumes: nothing.
- Produces: a private bucket `avatars`, objects at `{user_id}/avatar.jpg`, readable and writable only by the owning user, and by the service role that the dashboard uses.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260827160000_avatars_bucket.sql`:

```sql
-- Profile photos.
--
-- Private, not public: a public bucket hands anyone who obtains a URL a
-- picture of someone's face with no auth check, and these sit beside health
-- data. Reads go through short-lived signed URLs instead.
--
-- The path is '{user_id}/avatar.jpg', deterministic, so nothing needs to
-- record where a photo lives and no migration is needed to find one later.

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', false)
on conflict (id) do nothing;

-- Every policy scopes to auth.uid(), the same rule the app's own tables
-- follow. storage.foldername(name) splits the object path, so element 1 is
-- the owning user's id.
create policy "own avatar read"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "own avatar insert"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "own avatar update"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "own avatar delete"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
```

- [ ] **Step 2: Apply it locally and verify the bucket exists**

Run: `supabase db reset`
Then: `supabase db diff --schema storage` and confirm no unexpected drift.

Verify the bucket landed:

Run: `psql "$(supabase status -o env | grep DB_URL | cut -d= -f2- | tr -d '"')" -c "select id, public from storage.buckets where id = 'avatars';"`
Expected: one row, `avatars | f`

- [ ] **Step 3: Verify the policies reject a foreign path**

Run:

```bash
psql "$(supabase status -o env | grep DB_URL | cut -d= -f2- | tr -d '"')" \
  -c "select policyname from pg_policies where tablename = 'objects' and policyname like 'own avatar%' order by policyname;"
```

Expected: four rows, `own avatar delete`, `own avatar insert`, `own avatar read`, `own avatar update`

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260827160000_avatars_bucket.sql
git commit -F - <<'EOF'
feat(storage): add a private avatars bucket scoped to its owner

Profile photos need a home the account can carry to a second device.
Private rather than public, because a public bucket hands anyone with a
URL a picture of someone's face with no auth check, and these sit beside
health data. Reads go through short-lived signed URLs.

Path is {user_id}/avatar.jpg, deterministic, so nothing has to record
where a photo lives.
EOF
```

---

### Task 3: The `SupabaseStorage` client

**Files:**
- Create: `LifeOSKit/Sources/Integrations/SupabaseStorage.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/SupabaseStorageTests.swift`

**Interfaces:**
- Consumes: `AuthError` (already in `Integrations`).
- Produces:
  - `SupabaseStorage(baseURL: URL, anonKey: String, session: URLSession = .shared)`
  - `func upload(_ data: Data, userID: String, accessToken: String) async throws`
  - `func signedURL(userID: String, accessToken: String, expiresIn: Int = 3600) async throws -> URL`
  - `func download(userID: String, accessToken: String) async throws -> Data?`
  - `static func path(for userID: String) -> String`

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/IntegrationsTests/SupabaseStorageTests.swift`:

```swift
import Testing
import Foundation
@testable import Integrations

/// This suite keeps its own stub for the same reason the OTP suite does: the
/// reply queue is a static, and two suites sharing one consume each other's
/// replies whenever they run at the same time.
final class StorageStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var replies: [AuthStubURLProtocol.Reply] = []
    nonisolated(unsafe) static var seen: [URLRequest] = []

    static func reset() { replies = []; seen = [] }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.seen.append(request)
        let reply = Self.replies.isEmpty ? AuthStubURLProtocol.Reply.status(500, "{}") : Self.replies.removeFirst()
        switch reply {
        case .offline:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case .ok(let body):
            send(status: 200, body: body)
        case .status(let code, let body):
            send(status: code, body: body)
        }
    }

    override func stopLoading() {}

    private func send(status: Int, body: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized) struct SupabaseStorageTests {
    private func makeStorage() -> SupabaseStorage {
        StorageStubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StorageStubURLProtocol.self]
        return SupabaseStorage(
            baseURL: URL(string: "https://project.supabase.co")!,
            anonKey: "anon",
            session: URLSession(configuration: configuration)
        )
    }

    @Test func thePathIsDeterministicAndOwnedByTheUser() {
        #expect(SupabaseStorage.path(for: "abc-123") == "abc-123/avatar.jpg")
    }

    @Test func uploadPutsTheJPEGAtTheOwnedPath() async throws {
        let storage = makeStorage()
        StorageStubURLProtocol.replies = [.ok("{}")]

        try await storage.upload(Data([0xFF, 0xD8]), userID: "abc-123", accessToken: "token")

        let request = try #require(StorageStubURLProtocol.seen.first)
        #expect(request.url?.path == "/storage/v1/object/avatars/abc-123/avatar.jpg")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "image/jpeg")
        // Replacing a photo must overwrite rather than 409.
        #expect(request.value(forHTTPHeaderField: "x-upsert") == "true")
    }

    @Test func aFailedUploadThrowsARealError() async {
        let storage = makeStorage()
        StorageStubURLProtocol.replies = [.status(403, "{}")]

        await #expect(throws: (any Error).self) {
            try await storage.upload(Data([0xFF]), userID: "abc-123", accessToken: "token")
        }
    }

    @Test func aSignedURLIsResolvedAgainstTheStorageHost() async throws {
        let storage = makeStorage()
        StorageStubURLProtocol.replies = [
            .ok(#"{"signedURL":"/object/sign/avatars/abc-123/avatar.jpg?token=xyz"}"#)
        ]

        let url = try await storage.signedURL(userID: "abc-123", accessToken: "token")

        #expect(url.absoluteString
            == "https://project.supabase.co/storage/v1/object/sign/avatars/abc-123/avatar.jpg?token=xyz")
    }

    @Test func aMissingPhotoDownloadsAsNilRatherThanThrowing() async throws {
        let storage = makeStorage()
        StorageStubURLProtocol.replies = [.status(404, "{}")]

        let data = try await storage.download(userID: "abc-123", accessToken: "token")

        #expect(data == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd LifeOSKit && swift test --filter SupabaseStorageTests`
Expected: FAIL to compile, "cannot find 'SupabaseStorage' in scope"

- [ ] **Step 3: Write the implementation**

Create `LifeOSKit/Sources/Integrations/SupabaseStorage.swift`:

```swift
import Foundation

/// Supabase Storage over REST, for the one bucket the app uses.
///
/// No SDK, for the same reason `SupabaseAuth` has none: three calls is a small
/// surface and a dependency would pull in far more than that for no benefit.
///
/// The bucket is private, so every read needs either the owner's access token
/// or a signed URL minted with it. Signed URLs are requested on demand and
/// never persisted: a stored signed URL is a URL that works until it silently
/// does not.
public struct SupabaseStorage: Sendable {
    private static let bucket = "avatars"

    private let baseURL: URL
    private let anonKey: String
    private let session: URLSession

    public init(baseURL: URL, anonKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.session = session
    }

    /// Deterministic, so nothing has to record where a photo lives. The first
    /// segment is what the bucket's policies compare against `auth.uid()`.
    public static func path(for userID: String) -> String { "\(userID)/avatar.jpg" }

    public func upload(_ data: Data, userID: String, accessToken: String) async throws {
        var request = URLRequest(url: objectURL("object", userID: userID))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        // Replacing a photo is the common case, not the exception.
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = data

        let (body, response) = try await session.data(for: request)
        try check(response, body)
    }

    /// Short lived by default. Long enough to render a screen, short enough
    /// that a leaked link is not a permanent one.
    public func signedURL(userID: String, accessToken: String,
                          expiresIn: Int = 3_600) async throws -> URL {
        var request = URLRequest(url: objectURL("object/sign", userID: userID))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["expiresIn": expiresIn])

        let (body, response) = try await session.data(for: request)
        try check(response, body)

        struct Signed: Decodable { let signedURL: String }
        let signed = try JSONDecoder().decode(Signed.self, from: body)

        // The API answers with a path relative to the storage root, not an
        // absolute URL, so it has to be resolved against the host.
        guard let url = URL(string: signed.signedURL,
                            relativeTo: baseURL.appendingPathComponent("storage/v1"))?.absoluteURL
        else { throw AuthError.transport }
        return url
    }

    /// `nil` means the user has no photo yet, which is an ordinary state and
    /// not an error worth surfacing.
    public func download(userID: String, accessToken: String) async throws -> Data? {
        var request = URLRequest(url: objectURL("object/authenticated", userID: userID))
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (body, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 { return nil }
        try check(response, body)
        return body
    }

    private func objectURL(_ prefix: String, userID: String) -> URL {
        baseURL
            .appendingPathComponent("storage/v1")
            .appendingPathComponent(prefix)
            .appendingPathComponent(Self.bucket)
            .appendingPathComponent(Self.path(for: userID))
    }

    private func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw AuthError.transport }
        guard (200..<300).contains(http.statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            throw AuthError.fromHTTP(status: http.statusCode, json: json)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd LifeOSKit && swift test --filter SupabaseStorageTests`
Expected: PASS, 5 tests

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Integrations/SupabaseStorage.swift \
        LifeOSKit/Tests/IntegrationsTests/SupabaseStorageTests.swift
git commit -F - <<'EOF'
feat(storage): add a Supabase Storage client for avatars

Three calls against the private avatars bucket: upload, mint a signed
URL, download. No SDK, for the same reason SupabaseAuth has none.

Signed URLs are requested on demand and never persisted, because a
stored signed URL is a URL that works until it silently does not. A 404
on download is nil rather than a throw: having no photo yet is an
ordinary state.
EOF
```

---

### Task 4: Upload on signup and on profile edit

**Files:**
- Modify: `LIfeOS/Features/Onboarding/ViewModel/OnboardingViewModel.swift:236-258`
- Modify: `LIfeOS/Features/Settings/View/ProfileEditSheet.swift:180-201`

**Interfaces:**
- Consumes: `SupabaseStorage.upload(_:userID:accessToken:)` from Task 3, `ProfilePhotoStore.save` from Task 1.
- Produces: nothing new. Behaviour only.

- [ ] **Step 1: Add the upload to `finishProfile`**

In `OnboardingViewModel.swift`, the existing `do` block writes the local caches, then calls `auth.updateProfile`. Add the upload after that call succeeds, wrapped so it cannot throw out of signup:

```swift
try await auth.updateProfile(
    accessToken: session.accessToken,
    firstName: draft.firstName.trimmingCharacters(in: .whitespaces),
    lastName: draft.lastName.trimmingCharacters(in: .whitespaces),
    country: draft.country,
    birthDate: draft.birthDate,
    heightCM: draft.heightCM,
    gender: draft.gender.stored
)

// Best effort, and deliberately not part of the throwing path above. The
// account exists either way, and a Storage outage must not strand someone
// at the last step of signup. The photo is already on disk; the next
// launch retries the upload.
if let photo = draft.photo,
   let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey {
    do {
        try await SupabaseStorage(baseURL: url, anonKey: key)
            .upload(photo, userID: session.userID, accessToken: session.accessToken)
    } catch {
        authLog.error("avatar upload failed: \(String(describing: error), privacy: .public)")
    }
}

step = .connections
```

- [ ] **Step 2: Add the upload to `ProfileEditSheet.save`**

In `ProfileEditSheet.swift`, after the existing `updateProfile` call:

```swift
try? await SupabaseAuth(baseURL: url, anonKey: key).updateProfile(
    accessToken: session.accessToken,
    firstName: draft.firstName.trimmingCharacters(in: .whitespaces),
    lastName: draft.lastName.trimmingCharacters(in: .whitespaces),
    country: draft.country,
    birthDate: draft.birthDate,
    heightCM: draft.heightCM,
    gender: draft.gender
)

// Same best-effort rule as signup: the local copy already landed above, so
// a failed upload costs sync, not the user's edit.
if let photo = draftPhoto {
    try? await SupabaseStorage(baseURL: url, anonKey: key)
        .upload(photo, userID: session.userID, accessToken: session.accessToken)
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Verify by hand against a real project**

Run the app on the simulator, complete a signup with a photo, then confirm the object exists:

```bash
psql "$(supabase status -o env | grep DB_URL | cut -d= -f2- | tr -d '"')" \
  -c "select name, bucket_id from storage.objects where bucket_id = 'avatars';"
```

Expected: one row, `name` ending `/avatar.jpg`

- [ ] **Step 5: Commit**

```bash
git add LIfeOS/Features/Onboarding/ViewModel/OnboardingViewModel.swift \
        LIfeOS/Features/Settings/View/ProfileEditSheet.swift
git commit -F - <<'EOF'
feat(profile): upload the avatar on signup and on edit

Both call sites write the local copy first and upload after, and both
swallow a Storage failure. The account exists either way, and a Storage
outage must not strand someone at the last step of signup or lose an
edit they already saw take effect.
EOF
```

---

### Task 5: Fetch the photo on launch

**Files:**
- Modify: `LifeOSKit/Sources/Integrations/ProfileCache.swift`
- Modify: `LIfeOS/App/RootView.swift:610-620`
- Test: `LifeOSKit/Tests/IntegrationsTests/ProfileCacheTests.swift`

**Interfaces:**
- Consumes: `SupabaseStorage.download(userID:accessToken:)` from Task 3.
- Produces: `ProfilePhotoStore.fetchIfMissing(storage:userID:accessToken:account:) async`

- [ ] **Step 1: Write the failing test**

Append to `LifeOSKit/Tests/IntegrationsTests/ProfileCacheTests.swift`:

```swift
@Suite(.serialized) struct ProfilePhotoFetchTests {
    private func makeStorage(replies: [AuthStubURLProtocol.Reply]) -> SupabaseStorage {
        StorageStubURLProtocol.reset()
        StorageStubURLProtocol.replies = replies
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StorageStubURLProtocol.self]
        return SupabaseStorage(
            baseURL: URL(string: "https://project.supabase.co")!,
            anonKey: "anon",
            session: URLSession(configuration: configuration)
        )
    }

    @Test func aMissingPhotoIsFetchedAndCached() async {
        let account = "fetch-test-\(UUID().uuidString)"
        let storage = makeStorage(replies: [.ok("JPEGBYTES")])

        await ProfilePhotoStore.fetchIfMissing(
            storage: storage, userID: "abc-123", accessToken: "token", account: account
        )

        #expect(ProfilePhotoStore.load(account: account) == Data("JPEGBYTES".utf8))
        ProfilePhotoStore.save(nil, account: account)
    }

    @Test func anExistingPhotoIsLeftAloneAndNoCallIsMade() async {
        let account = "fetch-test-\(UUID().uuidString)"
        ProfilePhotoStore.save(Data("LOCAL".utf8), account: account)
        let storage = makeStorage(replies: [.ok("REMOTE")])

        await ProfilePhotoStore.fetchIfMissing(
            storage: storage, userID: "abc-123", accessToken: "token", account: account
        )

        #expect(ProfilePhotoStore.load(account: account) == Data("LOCAL".utf8))
        #expect(StorageStubURLProtocol.seen.isEmpty)
        ProfilePhotoStore.save(nil, account: account)
    }

    @Test func aFailedFetchLeavesNoPhotoAndDoesNotThrow() async {
        let account = "fetch-test-\(UUID().uuidString)"
        let storage = makeStorage(replies: [.status(500, "{}")])

        await ProfilePhotoStore.fetchIfMissing(
            storage: storage, userID: "abc-123", accessToken: "token", account: account
        )

        #expect(ProfilePhotoStore.load(account: account) == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd LifeOSKit && swift test --filter ProfilePhotoFetchTests`
Expected: FAIL to compile, "type 'ProfilePhotoStore' has no member 'fetchIfMissing'"

- [ ] **Step 3: Write the implementation**

Add to `ProfilePhotoStore` in `LifeOSKit/Sources/Integrations/ProfileCache.swift`:

```swift
    /// Pulls the avatar down when this device has never seen it, which is what
    /// makes a photo follow an account onto a second device.
    ///
    /// Never throws. A missing avatar is cosmetic, and a launch is the wrong
    /// place to surface a Storage outage.
    public static func fetchIfMissing(storage: SupabaseStorage,
                                      userID: String,
                                      accessToken: String,
                                      account: String = currentAccount()) async {
        guard load(account: account) == nil else { return }
        do {
            guard let data = try await storage.download(userID: userID, accessToken: accessToken)
            else { return }
            save(data, account: account)
        } catch {
            log.error("avatar fetch failed: \(String(describing: error), privacy: .public)")
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd LifeOSKit && swift test --filter ProfilePhotoFetchTests`
Expected: PASS, 3 tests

- [ ] **Step 5: Call it on launch**

In `RootView.swift`, beside the existing `noteSync` setup which already reads config and the keychain, add:

```swift
// The photo is cached per account on disk, so this is a no-op on every
// launch after the first on a given device. It is what carries a photo to
// a second device.
if let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey,
   let session = KeychainAuthSessionStore().load() {
    let storage = SupabaseStorage(baseURL: url, anonKey: key)
    Task {
        await ProfilePhotoStore.fetchIfMissing(
            storage: storage, userID: session.userID, accessToken: session.accessToken
        )
        profilePhoto = ProfilePhotoStore.load()
    }
}
```

- [ ] **Step 6: Run the whole Integrations suite**

Run: `cd LifeOSKit && swift test --filter IntegrationsTests`
Expected: PASS, no regressions in the auth, session or Whoop suites

- [ ] **Step 7: Build**

Run: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 8: Commit**

```bash
git add LifeOSKit/Sources/Integrations/ProfileCache.swift \
        LifeOSKit/Tests/IntegrationsTests/ProfileCacheTests.swift \
        LIfeOS/App/RootView.swift
git commit -F - <<'EOF'
feat(profile): fetch the avatar on launch so it follows the account

ProfilePhotoStore's comment used to name the limitation out loud: the
photo did not follow the account to a second device. It does now. The
fetch is skipped whenever a local copy exists, so this costs one call on
a device that has never seen the photo and nothing thereafter.
EOF
```

---

## Verification

After Task 5, the whole sub-project is done when all of these hold:

- `cd LifeOSKit && swift test` passes with no failures
- `xcodebuild ... build` succeeds
- A signup with a photo on a fresh simulator produces one row in `storage.objects`
- Signing that account in on a second simulator shows the same photo
- Signing a second account in on one device shows no photo, not the first account's

The last item is the `df18113` leak, and it is the one worth checking by hand rather than trusting.

## Notes for the executor

- `AuthStubURLProtocol.Reply` already exists in the Integrations test target. Reuse it rather than defining a parallel enum.
- Suites that share a static reply queue must be `@Suite(.serialized)`, and each suite keeps its own stub class. The existing `OTPStubURLProtocol` comment explains why.
- `AppConfig.supabaseURL` and `AppConfig.supabaseAnonKey` are optionals throughout the app. Every call site here follows the existing `guard let` pattern rather than force unwrapping.
- The app will not build without the untracked `Config/Secrets.xcconfig`. Copy it into the worktree.

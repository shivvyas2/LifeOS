# Focus App Foundations (Slices 1 and 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give LifeOS a shared sign-in module and a server copy of every focus
session, so the LifeOS Focus app (slice 3) can be built on an account and data
that already work.

**Architecture:**
- **Slice 1** extracts the code sign-in (email or phone one-time code) from
  `LIfeOS/Features/Onboarding` into a new `AccountUI` module in `LifeOSKit`.
  `OnboardingViewModel` keeps only the LifeOS-specific steps.
- Slice 1 also adds a **handoff**: a signed-in app leaves a short-lived access
  token in a shared Keychain group. A sibling app exchanges that token, through
  a new `session-handoff` Edge Function, for a session of its own.
- **Slice 2** adds a `focus_sessions` table and a `FocusSync` module that
  uploads local `FocusSessionRecord`s, safe to repeat, and pulls the week's
  rows back into the local store. Today's existing local query then shows
  sessions from every device without changing.

**Tech Stack:**
- Swift 6, SwiftUI, SwiftData, Swift Testing (`import Testing`)
- `URLSession` over PostgREST and GoTrue (no Supabase SDK)
- Supabase Postgres migrations
- Deno Edge Functions with `deno test`

**Spec:** `docs/superpowers/specs/2026-10-10-lifeos-focus-app-design.md`

## Spec amendment made while planning

The spec said both apps share the auth session through a Keychain group.
Planning found that this is unsafe. Supabase rotates the refresh token on every
refresh and revokes the token family when a used token is presented again. Two
apps holding one refresh token would sign each other out.

**This plan shares only the access token.** It lives about an hour and is never
refreshed by the reader. The reader exchanges it for an independent session
through `session-handoff`, which uses the same `generate_link` and `verify`
steps `otp-check` already uses. Task 5 also updates the spec's "Shared sign-in
on one device" paragraph to match.

## Global Constraints

- Platforms: iOS, macOS and watchOS 26.0. Swift tools 6.0. `LifeOSKit/Package.swift` lists the targets explicitly.
- Team ID: `Z42YU5W6WY`. The LifeOS bundle is `com.shivvyas.lifeos`.
- Shared Keychain group: `$(AppIdentifierPrefix)com.shivvyas.lifeos.shared`.
  It is listed **second** in `keychain-access-groups`, after
  `$(AppIdentifierPrefix)com.shivvyas.lifeos`, so the default group, where
  every existing session lives, does not change.
- No Supabase SDK in Swift. Use `SupabaseAuth` and `SupabaseREST`.
- A field added to an existing `@Model` must be optional or defaulted.
- Every PostgREST call carries the user's access token, never the anon key
  alone.
- `focus_sessions.mood` is one of `focus`, `brainstorm`, `relax`, `sleep`.
  `source` is one of `soundscape`, `appleMusic`, `silence` (the raw values of
  `Mood` and `SoundSource`).
- Sessions are final: there is no update policy on `focus_sessions`.
- Commits:
  - one branch per slice, `feat/account-ui` and `feat/focus-sync`, both off
    `origin/main`
  - conventional commit messages
  - no em dashes
  - no AI attribution trailer
- Cost: stay within about $2 per user per month for the backend. One row is
  about 200 bytes per session.
- New worktree: copy `Config/Secrets.xcconfig` in before the first
  `xcodebuild`.

## Review Focus

1. **A signed-out app must never upload or pull.** The uploader runs with no
   session, or with an expired one. It must send nothing and must not mark
   records as synced. Test: Task 8, `skipsWhenSignedOut`. Account switches are
   handled by the driver's `reset()` in Task 9, which swaps to the new
   account's store and token together.
2. **The handoff token is expired, or belongs to another account.** "Continue
   as" must only be offered for a beacon whose token has more than 2 minutes
   left. A 401 from `session-handoff` must fall back to the code flow with no
   error banner. Tests: Task 4 `ignoresExpiredBeacon` and Task 5
   `handoffRefusedFallsBackQuietly`.
3. **A record re-sent after a lost response.** A 2xx response that never
   reached the device is sent again later, and that must not create a second
   row or fail. Test: Task 8 `resendUsesIgnoreDuplicates` (checks the `Prefer`
   header).
4. **Unfinished sessions.** A record with no `endedAt` (a session still
   running, or a crash) must never upload. Test: Task 7 `pendingExcludesUnfinished`.
5. **A pulled row for a session already in the local store.** The pull must
   not insert a duplicate or overwrite the local record. Test: Task 7
   `mergeSkipsKnownIDs`.

---

## File Structure

**Slice 1, sign-in (`feat/account-ui`)**

| File | Change | Responsibility |
|---|---|---|
| `LifeOSKit/Package.swift` | Modify | Add the `AccountUI` target and its tests, depending on `DesignSystem` and `Integrations` |
| `LifeOSKit/Sources/AccountUI/SignInDraft.swift` | Create | What the user types: channel, email, phone, dial code, country, code |
| `LifeOSKit/Sources/AccountUI/DialCountries.swift` | Create (moved) | `DialCountry`, `DialCountries` (from `OnboardingModels.swift`) |
| `LifeOSKit/Sources/AccountUI/SignInModel.swift` | Create | Code sign-in flow state: send, verify, resend countdown, restore, sign out, handoff |
| `LifeOSKit/Sources/AccountUI/SignInBackend.swift` | Create | Protocol over `SupabaseAuth` so the model is testable |
| `LifeOSKit/Sources/AccountUI/SignInScreens.swift` | Create (moved) | `SignupScaffold`, `OnboardingActionButton`, `IdentityScreen`, `CodeScreen`, `CountryPicker`, `FieldStyle` (from `SignupScreens.swift`) |
| `LifeOSKit/Sources/Integrations/SharedSignIn.swift` | Create | The beacon: write, read and clear an access token in the shared Keychain group |
| `LifeOSKit/Sources/Integrations/AuthSessionStore.swift` | Modify | `save` and `clear` also update the beacon when sharing is configured |
| `LifeOSKit/Sources/Integrations/SupabaseAuth.swift` | Modify | Add `handoff(accessToken:)` |
| `LifeOSKit/Tests/AccountUITests/*.swift` | Create | Tests for the draft and the model |
| `LifeOSKit/Tests/IntegrationsTests/SharedSignInTests.swift` | Create | Tests for beacon selection and encoding |
| `LIfeOS/Features/Onboarding/Model/OnboardingModels.swift` | Modify | Drop the moved types. Keep `OnboardingStep`, `IntroPage`, `Gender`, and the profile fields as `ProfileDraft` |
| `LIfeOS/Features/Onboarding/ViewModel/OnboardingViewModel.swift` | Modify | Compose `SignInModel`. Keep the profile and connections steps |
| `LIfeOS/Features/Onboarding/View/SignupScreens.swift` | Modify | Keep only `ProfileStepScreen` and its helpers |
| `LIfeOS/Features/Onboarding/View/ConnectionsScreen.swift` | Modify | Route `.identity` and `.code` to the `AccountUI` screens |
| `LIfeOS/LIfeOS.entitlements` | Modify | Add `keychain-access-groups` |
| `LIfeOS/App/LIfeOSApp.swift` | Modify | `SharedSignIn.accessGroup = …` at launch |
| `supabase/functions/session-handoff/index.ts` | Create | Exchange a valid access token for a new, independent session |
| `supabase/functions/_shared/otp_twilio.ts` | Modify | Pull `sessionForEmail` out of `mintSession` |
| `supabase/functions/_shared/handoff_test.ts` | Create | Deno test for the handler |

**Slice 2, focus sync (`feat/focus-sync`)**

| File | Change | Responsibility |
|---|---|---|
| `supabase/migrations/20261010120000_focus_sessions.sql` | Create | The table, its index and its row-level security |
| `supabase/tests/focus_sessions_rls.sql` | Create | Proves one user cannot see another user's rows |
| `LifeOSKit/Sources/Persistence/FocusSessionRecord.swift` | Modify | Add `syncedAt`, `pending()`, `markSynced`, `merge(remote:)` |
| `LifeOSKit/Package.swift` | Modify | Add the `FocusSync` target and its tests, depending on `Persistence` and `Integrations` |
| `LifeOSKit/Sources/FocusSync/FocusRow.swift` | Create | The wire format, converting to and from `FocusSessionRecord` |
| `LifeOSKit/Sources/FocusSync/FocusRemote.swift` | Create | The protocol over `SupabaseREST`, plus a `fetchSince` for focus rows |
| `LifeOSKit/Sources/FocusSync/FocusSync.swift` | Create | `uploadPending()`, `pullWeek()`, and one run in flight at a time |
| `LifeOSKit/Tests/FocusSyncTests/*.swift` | Create | Tests for the uploader and the pull |
| `LifeOSKit/Tests/PersistenceTests/FocusStoreTests.swift` | Modify | Tests for `pending`, `markSynced` and `merge` |
| `LifeOSKit/Sources/Persistence/AccountData.swift` | Modify | `DataCategory.focus`, server rows and local erase |
| `supabase/functions/_shared/account.ts`, `supabase/functions/account-data/index.ts` | Modify | The `focus` server category, which clears `focus_sessions` |
| `LIfeOS/Features/Settings/View/ClearDataScreen.swift` | Modify | The "where it lives" copy for `.focus` |
| `LIfeOS/App/FocusSyncDriver.swift` | Create | Runs the sync on launch and when the app becomes active, after a session is saved, and when the network returns |
| `LIfeOS/Features/Focus/ViewModel/FocusSessionModel.swift` | Modify | Ask the driver to run after `FocusStore.record` |

---

## Slice 1: AccountUI (branch `feat/account-ui`)

### Task 1: The AccountUI module, with the sign-in draft and dial countries

**Files:**
- Modify: `LifeOSKit/Package.swift`
- Create: `LifeOSKit/Sources/AccountUI/SignInDraft.swift`
- Create: `LifeOSKit/Sources/AccountUI/DialCountries.swift` (moved verbatim from `LIfeOS/Features/Onboarding/Model/OnboardingModels.swift`, lines 139 to 186 of the current file: `DialCountry` and `DialCountries`, made `public`)
- Test: `LifeOSKit/Tests/AccountUITests/SignInDraftTests.swift`

**Interfaces:**
- Produces:
  - `public struct SignInDraft: Equatable`, with:
    - fields `channel: SupabaseAuth.Channel`, `phone`, `dialCode`, `email`, `code`, `country: String`
    - computed `e164`, `destination`, `canSendCode`, `canVerify`
  - `public enum DialCountries` with `otpRegions`, `all`, and `dial(for:)`
  - `public struct DialCountry`

- [ ] **Step 1: Add the target to `Package.swift`**

In `products`, add:

```swift
        .library(name: "AccountUI", targets: ["AccountUI"]),
```

In `targets`, add:

```swift
        .target(name: "AccountUI", dependencies: ["DesignSystem", "Integrations"]),
        .testTarget(name: "AccountUITests", dependencies: ["AccountUI"]),
```

- [ ] **Step 2: Write the failing test**

```swift
// LifeOSKit/Tests/AccountUITests/SignInDraftTests.swift
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
```

- [ ] **Step 3: Run it and confirm it fails**

Run: `cd LifeOSKit && swift test --filter SignInDraftTests`
Expected: a compile failure, "cannot find 'SignInDraft' in scope".

- [ ] **Step 4: Implement**

```swift
// LifeOSKit/Sources/AccountUI/SignInDraft.swift
import Foundation
import Integrations

/// What the user types to sign in, before any of it is trusted. The profile
/// fields (name, birthday, height) belong to LifeOS's own onboarding and are
/// not here: a companion app signs people in without asking for them.
public struct SignInDraft: Equatable {
    /// Email first: it is free through Resend to 3,000 a month, needs no A2P
    /// registration, and carries none of the SMS failure modes.
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
```

Move `DialCountry` and `DialCountries` into `DialCountries.swift` unchanged,
except that you add `public` to the types, to `otpRegions`, to `all` and to
`dial(for:)`, and give `DialCountry` a public memberwise `init` if the app
constructs one. Run `grep -rn "DialCountry(" LIfeOS` to check. Delete them
from `OnboardingModels.swift`.

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `cd LifeOSKit && swift test --filter SignInDraftTests`
Expected: 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Package.swift LifeOSKit/Sources/AccountUI LifeOSKit/Tests/AccountUITests LIfeOS/Features/Onboarding/Model/OnboardingModels.swift
git commit -m "feat(account): start AccountUI with the sign-in draft and dial countries"
```

(The app does not build again until Task 3. That is expected inside this
branch. Do not push between Tasks 1 and 3.)

### Task 2: `SignInModel`, the code sign-in flow

**Files:**
- Create: `LifeOSKit/Sources/AccountUI/SignInBackend.swift`
- Create: `LifeOSKit/Sources/AccountUI/SignInModel.swift`
- Test: `LifeOSKit/Tests/AccountUITests/SignInModelTests.swift`

**Interfaces:**
- Consumes: `SignInDraft` (Task 1). From `Integrations`, the existing
  `SupabaseAuth`, `AuthSession`, `AuthError` (with `.readable`),
  `AuthSessionStoring`, `InMemoryAuthSessionStore`, `SessionRefresher`
  (`restore() -> Outcome` with `.active`, `.signedOut` and `.rejected`), and
  `AccountStore`.
- Produces:
  - `public protocol SignInBackend: Sendable`, with
    `availableChannels() async -> Set<SupabaseAuth.Channel>`,
    `sendCode(to:channel:) async throws`,
    `verify(code:destination:channel:) async throws -> AuthSession`,
    `handoff(accessToken:) async throws -> AuthSession` (implemented in
    Task 5; Task 2 declares it), and
    `restore(store:) async -> SessionRefresher.Outcome`.
  - `public enum SignInMode { case signUp, signIn }`
  - `public enum SignInStep: Equatable { case identity, code, done }`
  - `@MainActor @Observable public final class SignInModel`, with:
    - `public init(backend: (any SignInBackend)?, store: any AuthSessionStoring, onSignedIn: @escaping @MainActor (AuthSession) -> Void)`
    - `mode`, `step`, `draft`, `isBusy`, `errorMessage`, `phoneSendFailed`,
      `resendIn`, `availableChannels`, `isConfigured`
    - `loadChannels()`, `switchChannel(to:)`, `useEmailInstead()`,
      `toggleMode()`, `back() -> Bool` (returns false when it is already at
      the first step), `sendCode()`, `verifyCode()`
    - copy helpers: `identityTitle`, `identitySubtitle`, `modeSwitchTitle`,
      `destinationLabel`, `phoneUnavailableNote`

`SignInModel` does **not** persist anything itself. `onSignedIn` hands the
session to the host app, which knows its own account store. That keeps LifeOS's
`AccountStore().add(...)` and legacy-session clearing in LifeOS.

- [ ] **Step 1: Write the failing tests**

```swift
// LifeOSKit/Tests/AccountUITests/SignInModelTests.swift
import Testing
import Foundation
import Integrations
@testable import AccountUI

final class FakeBackend: SignInBackend, @unchecked Sendable {
    var channels: Set<SupabaseAuth.Channel> = [.email, .phone]
    var sendError: Error?
    var verifyResult: Result<AuthSession, Error> = .failure(AuthError.transport)
    var handoffResult: Result<AuthSession, Error> = .failure(AuthError.transport)
    var sent: [(String, SupabaseAuth.Channel)] = []

    func availableChannels() async -> Set<SupabaseAuth.Channel> { channels }
    func sendCode(to destination: String, channel: SupabaseAuth.Channel) async throws {
        if let sendError { throw sendError }
        sent.append((destination, channel))
    }
    func verify(code: String, destination: String, channel: SupabaseAuth.Channel) async throws -> AuthSession {
        try verifyResult.get()
    }
    func handoff(accessToken: String) async throws -> AuthSession { try handoffResult.get() }
    func restore(store: any AuthSessionStoring) async -> SessionRefresher.Outcome { .signedOut }
}

extension AuthSession {
    static func sample(id: String = "u1") -> AuthSession {
        AuthSession(accessToken: "a", refreshToken: "r", expiresAt: .now.addingTimeInterval(3600),
                    userID: id, phone: nil, email: "s@example.com", hasProfile: true)
    }
}

@MainActor
struct SignInModelTests {
    @Test func sendingMovesToTheCodeStepAndStartsTheCountdown() async {
        let backend = FakeBackend()
        let model = SignInModel(backend: backend, store: InMemoryAuthSessionStore(), onSignedIn: { _ in })
        model.draft.email = "s@example.com"
        await model.sendCode()
        #expect(model.step == .code)
        #expect(model.resendIn == 60)
        #expect(backend.sent.first?.0 == "s@example.com")
    }

    @Test func aFailedSMSOffersEmail() async {
        let backend = FakeBackend()
        backend.sendError = AuthError.server(status: 400, message: "sms_failed")
        let model = SignInModel(backend: backend, store: InMemoryAuthSessionStore(), onSignedIn: { _ in })
        model.switchChannel(to: .phone)
        model.draft.dialCode = "+1"
        model.draft.phone = "4155550123"
        await model.sendCode()
        #expect(model.step == .identity)
        #expect(model.phoneSendFailed)
        model.useEmailInstead()
        #expect(model.draft.channel == .email)
        #expect(!model.phoneSendFailed)
    }

    @Test func verifyingSavesTheSessionAndHandsItOver() async {
        let backend = FakeBackend()
        backend.verifyResult = .success(.sample())
        let store = InMemoryAuthSessionStore()
        var handed: AuthSession?
        let model = SignInModel(backend: backend, store: store, onSignedIn: { handed = $0 })
        model.draft.code = "123456"
        await model.verifyCode()
        #expect(model.step == .done)
        #expect(handed?.userID == "u1")
    }

    @Test func aWrongCodeStaysOnTheCodeStepWithAMessage() async {
        let backend = FakeBackend()
        backend.verifyResult = .failure(AuthError.server(status: 403, message: "otp_expired"))
        let model = SignInModel(backend: backend, store: InMemoryAuthSessionStore(), onSignedIn: { _ in })
        model.draft.code = "123456"
        await model.sendCodeStepForTesting()
        await model.verifyCode()
        #expect(model.step == .code)
        #expect(model.errorMessage != nil)
    }

    @Test func emailFallsBackToPhoneWhenEmailIsNotConfigured() async {
        let backend = FakeBackend()
        backend.channels = [.phone]
        let model = SignInModel(backend: backend, store: InMemoryAuthSessionStore(), onSignedIn: { _ in })
        await model.loadChannels()
        #expect(model.draft.channel == .phone)
    }

    @Test func noBackendMeansNotConfigured() {
        let model = SignInModel(backend: nil, store: InMemoryAuthSessionStore(), onSignedIn: { _ in })
        #expect(!model.isConfigured)
    }
}
```

`sendCodeStepForTesting()` is an `internal` helper that sets `step = .code`.
It exists so the test can start on the code step without a send.

- [ ] **Step 2: Run them and confirm they fail**

Run: `cd LifeOSKit && swift test --filter SignInModelTests`
Expected: a compile failure, "cannot find 'SignInModel'".

- [ ] **Step 3: Implement**

```swift
// LifeOSKit/Sources/AccountUI/SignInBackend.swift
import Foundation
import Integrations

/// The calls sign-in makes, as a protocol so the model can be tested without
/// a network. `SupabaseAuth` is the only production conformer.
public protocol SignInBackend: Sendable {
    func availableChannels() async -> Set<SupabaseAuth.Channel>
    func sendCode(to destination: String, channel: SupabaseAuth.Channel) async throws
    func verify(code: String, destination: String, channel: SupabaseAuth.Channel) async throws -> AuthSession
    func handoff(accessToken: String) async throws -> AuthSession
    func restore(store: any AuthSessionStoring) async -> SessionRefresher.Outcome
}

extension SupabaseAuth: SignInBackend {
    public func restore(store: any AuthSessionStoring) async -> SessionRefresher.Outcome {
        await SessionRefresher(auth: self, store: store).restore()
    }
}
```

`handoff(accessToken:)` does not exist on `SupabaseAuth` until Task 5. To keep
Task 2 compiling, add this stub to `SupabaseAuth.swift` now. Task 5 replaces
it.

```swift
    /// Exchanges another app's access token for a session of this app's own.
    public func handoff(accessToken: String) async throws -> AuthSession {
        throw AuthError.server(status: 501, message: "handoff_unavailable")
    }
```

```swift
// LifeOSKit/Sources/AccountUI/SignInModel.swift
import Foundation
import Observation
import OSLog
import Integrations

private let log = Logger(subsystem: "com.shivvyas.lifeos", category: "signin")

public enum SignInMode: Equatable, Sendable { case signUp, signIn }
public enum SignInStep: Equatable, Sendable { case identity, code, done }

/// The code sign-in both apps use: pick a channel, receive a code, verify it.
///
/// It decides nothing about what happens after. The host is handed the
/// session through `onSignedIn` and records the account in its own way, which
/// is how LifeOS keeps its multi-account store while Focus stays simple.
@MainActor @Observable
public final class SignInModel {
    public private(set) var mode: SignInMode = .signUp
    public private(set) var step: SignInStep = .identity
    public var draft = SignInDraft()
    public private(set) var isBusy = false
    public private(set) var errorMessage: String?
    /// Set when a code could not be sent over SMS. Nothing in the app can make
    /// SMS deliver, so the only useful next move is the other channel.
    public private(set) var phoneSendFailed = false
    public private(set) var resendIn = 0
    public private(set) var availableChannels: Set<SupabaseAuth.Channel> = []

    private let backend: (any SignInBackend)?
    private let store: any AuthSessionStoring
    private let onSignedIn: @MainActor (AuthSession) -> Void

    public init(backend: (any SignInBackend)?, store: any AuthSessionStoring,
                onSignedIn: @escaping @MainActor (AuthSession) -> Void) {
        self.backend = backend
        self.store = store
        self.onSignedIn = onSignedIn
        draft.dialCode = DialCountries.dial(for: draft.country)
        if !DialCountries.otpRegions.contains(draft.country) {
            draft.country = "US"
            draft.dialCode = "+1"
        }
    }

    public var isConfigured: Bool { backend != nil }

    public var identityTitle: String { mode == .signUp ? "Create your account" : "Welcome back" }
    public var identitySubtitle: String {
        draft.channel == .phone ? "We'll text you a six-digit code." : "We'll email you a six-digit code."
    }
    public var modeSwitchTitle: String {
        mode == .signUp ? "Already have an account? Sign in" : "New here? Create an account"
    }
    public var destinationLabel: String { draft.channel == .phone ? draft.e164 : draft.email }
    public var phoneUnavailableNote: String? {
        guard !availableChannels.isEmpty, !availableChannels.contains(.phone) else { return nil }
        return "SMS isn't enabled on this project yet. Use email for now."
    }

    public func begin(_ mode: SignInMode) {
        self.mode = mode
        step = .identity
        errorMessage = nil
    }

    public func loadChannels() async {
        guard let backend else { return }
        let channels = await backend.availableChannels()
        availableChannels = channels
        if !channels.contains(.email), channels.contains(.phone) { draft.channel = .phone }
    }

    public func switchChannel(to channel: SupabaseAuth.Channel) {
        draft.channel = channel
        errorMessage = nil
        phoneSendFailed = false
    }

    public func useEmailInstead() { switchChannel(to: .email) }

    public func toggleMode() {
        mode = mode == .signUp ? .signIn : .signUp
        errorMessage = nil
        phoneSendFailed = false
    }

    /// One step back. Returns false at the first step, so the host can leave
    /// sign-in (LifeOS goes back to its intro).
    public func back() -> Bool {
        errorMessage = nil
        switch step {
        case .identity:
            phoneSendFailed = false
            return false
        case .code:
            step = .identity
            return true
        case .done:
            return false
        }
    }

    public func sendCode() async {
        guard let backend, draft.canSendCode else { return }
        isBusy = true
        errorMessage = nil
        phoneSendFailed = false
        defer { isBusy = false }
        do {
            try await backend.sendCode(to: draft.destination, channel: draft.channel)
            draft.code = ""
            step = .code
            startResendCountdown()
        } catch let error as AuthError {
            log.error("sendCode failed: \(error.readable, privacy: .public)")
            errorMessage = error.readable
            phoneSendFailed = draft.channel == .phone
        } catch {
            errorMessage = "Couldn't send the code"
            phoneSendFailed = draft.channel == .phone
        }
    }

    public func verifyCode() async {
        guard let backend, draft.canVerify else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let session = try await backend.verify(code: draft.code.filter(\.isNumber),
                                                   destination: draft.destination, channel: draft.channel)
            finish(with: session)
        } catch let error as AuthError {
            log.error("verify failed: \(String(describing: error), privacy: .public)")
            errorMessage = error.readable
        } catch {
            errorMessage = "That code didn't work"
        }
    }

    func finish(with session: AuthSession) {
        step = .done
        onSignedIn(session)
    }

    func sendCodeStepForTesting() async { step = .code }

    private func startResendCountdown() {
        // 60s: email posts straight to /auth/v1/otp, which GoTrue limits to
        // one a minute; the phone function's 45s is the looser of the two.
        resendIn = 60
        Task {
            while resendIn > 0 {
                try? await Task.sleep(for: .seconds(1))
                resendIn -= 1
            }
        }
    }
}
```

The `store` is held for Task 5, where the handoff saves through it. If Swift
warns that it is unused, leave it; Task 5 uses it.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `cd LifeOSKit && swift test --filter SignInModelTests`
Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/AccountUI LifeOSKit/Tests/AccountUITests LifeOSKit/Sources/Integrations/SupabaseAuth.swift
git commit -m "feat(account): add SignInModel for the code sign-in flow"
```

### Task 3: Move the sign-in screens, and point LifeOS's onboarding at AccountUI

**Files:**
- Create: `LifeOSKit/Sources/AccountUI/SignInScreens.swift` (moved from `LIfeOS/Features/Onboarding/View/SignupScreens.swift`: `SignupScaffold`, `OnboardingActionButton`, `IdentityScreen`, `CodeScreen`, `CountryPicker`, `FieldStyle`)
- Modify: `LIfeOS/Features/Onboarding/View/SignupScreens.swift` (keep `ProfileStepScreen` only)
- Modify: `LIfeOS/Features/Onboarding/Model/OnboardingModels.swift`
- Modify: `LIfeOS/Features/Onboarding/ViewModel/OnboardingViewModel.swift`
- Modify: `LIfeOS/Features/Onboarding/View/ConnectionsScreen.swift:128-130`
- Modify: any other `import` of the moved types (find them with `grep -rn "SignupScaffold\|OnboardingActionButton\|CountryPicker" LIfeOS`)

**Interfaces:**
- Consumes: `SignInModel` and `SignInStep` (Task 2).
- Produces:
  - `public struct IdentityScreen: View`, `init(model: SignInModel, totalSteps: Int, onBack: @escaping () -> Void)`
  - `public struct CodeScreen: View`, with the same init
  - `public struct SignupScaffold`, `public struct OnboardingActionButton`, `public struct CountryPicker`
  - `OnboardingViewModel.signIn: SignInModel`

- [ ] **Step 1: Move the views**

Cut the six types into `SignInScreens.swift`, add `import Integrations` and
`import DesignSystem`, and make each type and its `init` `public`. Then make
two edits:

- `IdentityScreen` and `CodeScreen` change `@Bindable var model: OnboardingViewModel` to `@Bindable var model: SignInModel`, and take `totalSteps: Int` and `onBack: () -> Void`.
- Where they read `model.mode == .signIn ? 2 : 3`, use `totalSteps`. Where they call `model.back()`, call `onBack()`.

All other `model.` calls already exist on `SignInModel` with the same names.

```swift
public struct IdentityScreen: View {
    @Bindable var model: SignInModel
    let totalSteps: Int
    let onBack: () -> Void
    public init(model: SignInModel, totalSteps: Int, onBack: @escaping () -> Void) {
        self.model = model; self.totalSteps = totalSteps; self.onBack = onBack
    }
    // body unchanged except: totalSteps: totalSteps, onBack: onBack
}
```

`CodeScreen` follows the same shape.

- [ ] **Step 2: Shrink the app's draft**

In `OnboardingModels.swift`, rename `SignupDraft` to `ProfileDraft` and delete
the fields that moved to `SignInDraft` (`channel`, `phone`, `dialCode`,
`email`, `code`, `e164`, `destination`, `canSendCode`, `canVerify`). Keep
`firstName`, `lastName`, `country`, `photo`, `birthDate`, `heightCM`, `gender`
and `canFinishProfile`. Delete `AuthMode`; it is replaced by `SignInMode`.

- [ ] **Step 3: Compose the model in `OnboardingViewModel`**

Replace the auth state and methods with one `SignInModel`, and forward the
step:

```swift
    let signIn: SignInModel
    var draft = ProfileDraft()

    init(store: any AuthSessionStoring = KeychainAuthSessionStore()) {
        self.store = store
        let restored = store.load()
        self.isSignedIn = restored != nil
        self.session = restored
        let backend: SupabaseAuth? = {
            guard let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey else { return nil }
            return SupabaseAuth(baseURL: url, anonKey: key)
        }()
        self.auth = backend
        // A placeholder so `self` is fully initialised before the closure
        // captures it; replaced on the next line.
        self.signIn = SignInModel(backend: backend, store: store, onSignedIn: { _ in })
        self.signIn = SignInModel(backend: backend, store: store) { [weak self] session in
            self?.didSignIn(session)
        }
        if let restored { /* unchanged: step = .connections / .signedIn / .profile */ }
    }

    private func didSignIn(_ session: AuthSession) {
        do {
            try AccountStore().add(Account(userID: session.userID,
                label: session.email ?? session.phone ?? "Account"), session: session)
        } catch {
            authLog.error("account add failed: \(String(describing: error), privacy: .public)")
        }
        AccountStore().clearLegacySession()
        store = KeychainAuthSessionStore(account: session.userID)
        self.session = session
        isSignedIn = true
        step = session.hasProfile ? .signedIn : .profile
    }

    func beginSignup() { signIn.begin(.signUp); step = .identity }
    func beginSignIn() { signIn.begin(.signIn); step = .identity }
```

`signIn` must be `var` for the two-step assignment. Declare it as
`private(set) var signIn: SignInModel`.

Keep `.identity` and `.code` in `OnboardingStep`, and mirror `signIn.step` into
them where the view routes:

```swift
    /// The step the flow shows. Sign-in owns identity/code; this model owns
    /// everything after.
    var visibleStep: OnboardingStep {
        guard step == .identity || step == .code else { return step }
        return signIn.step == .code ? .code : .identity
    }

    func back() {
        switch step {
        case .identity, .code:
            if !signIn.back() { step = .intro }
        case .profile: step = .identity; signIn.begin(.signUp)
        case .connections: step = .profile
        case .intro, .signedIn: break
        }
    }
```

Delete from `OnboardingViewModel`: `mode`, `errorMessage` (except the profile
error, which stays under that name), `phoneSendFailed`, `resendIn`,
`availableChannels`, `loadChannels`, `phoneUnavailableNote`, `isConfigured`,
`identitySubtitle`, `identityTitle`, `modeSwitchTitle`, `destinationLabel`,
`toggleMode`, `switchChannel`, `useEmailInstead`, `sendCode`, `verifyCode` and
`startResendCountdown`.

Keep `restoreSession`, `performRestore`, `saveProfile`, `signOut` and
`account`.

In `signOut()`, replace `draft = SignupDraft(); mode = .signUp` with:

```swift
draft = ProfileDraft()
signIn = SignInModel(backend: auth, store: store) { [weak self] in self?.didSignIn($0) }
```

In `saveProfile()`, replace `draft.country` and the profile fields to read
from `ProfileDraft`. They have the same names.

- [ ] **Step 4: Route the screens**

In `ConnectionsScreen.swift`, replace the switch over `model.step` with a
switch over `model.visibleStep`, and change the two cases:

```swift
            case .identity:
                IdentityScreen(model: model.signIn,
                               totalSteps: model.signIn.mode == .signIn ? 2 : 3,
                               onBack: { model.back() })
            case .code:
                CodeScreen(model: model.signIn,
                           totalSteps: model.signIn.mode == .signIn ? 2 : 3,
                           onBack: { model.back() })
```

Add `import AccountUI` to every file that now needs it. Add the `AccountUI`
package product to the `LIfeOS` target. The project uses synchronized root
groups, but package products are listed explicitly: in Xcode, open target
LIfeOS, then General, then Frameworks, then `+`, then AccountUI. To do it in
the pbxproj, copy an existing `XCSwiftPackageProductDependency` entry, such as
`Soundscape`, and its `PBXBuildFile` line, and rename both.

- [ ] **Step 5: Build, and run the existing auth tests**

Run:

```bash
cd LifeOSKit && swift test --filter "AccountUITests|SessionRefreshTests|AuthSessionProfileTests"
```

Then:

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' -quiet
```

Expected: the tests pass, and the build shows no `error:` line.

- [ ] **Step 6: Check on the simulator by hand**

Delete the app from a private simulator, launch it, tap "Get started", enter
an email, check that "Send code" enables, and tap Back twice to reach the
intro. With the test phone number from `otp_guard.ts` (`TEST_PHONE` /
`TEST_CODE`), finish a phone sign-in and land on the profile step.

- [ ] **Step 7: Commit**

```bash
git add -A LifeOSKit LIfeOS LIfeOS.xcodeproj/project.pbxproj
git commit -m "refactor(onboarding): sign in through AccountUI"
```

### Task 4: The shared sign-in beacon

**Files:**
- Create: `LifeOSKit/Sources/Integrations/SharedSignIn.swift`
- Modify: `LifeOSKit/Sources/Integrations/AuthSessionStore.swift` (`save` and `clear`)
- Modify: `LIfeOS/LIfeOS.entitlements`
- Modify: `LIfeOS/App/LIfeOSApp.swift` (set the group at launch)
- Test: `LifeOSKit/Tests/IntegrationsTests/SharedSignInTests.swift`

**Interfaces:**
- Produces:
  - `public struct SignInBeacon: Codable, Equatable, Sendable { userID, label, accessToken, expiresAt }`
  - `public protocol BeaconKeychain: Sendable { read() -> Data?; write(Data); delete() }`
  - `public enum SharedSignIn`, with:
    - `nonisolated(unsafe) public static var accessGroup: String?`
    - `public static func publish(_ session: AuthSession, keychain: (any BeaconKeychain)? = nil)`
    - `public static func current(now: Date = .now, keychain: (any BeaconKeychain)? = nil) -> SignInBeacon?`
    - `public static func withdraw(userID: String, keychain: (any BeaconKeychain)? = nil)`

  A nil `keychain` means the real Keychain in `accessGroup`. With no
  `accessGroup` set, all three calls do nothing.

- [ ] **Step 1: Write the failing tests**

```swift
// LifeOSKit/Tests/IntegrationsTests/SharedSignInTests.swift
import Testing
import Foundation
@testable import Integrations

final class MemoryBeaconKeychain: BeaconKeychain, @unchecked Sendable {
    var data: Data?
    func read() -> Data? { data }
    func write(_ data: Data) { self.data = data }
    func delete() { data = nil }
}

@Suite(.serialized)
struct SharedSignInTests {
    init() { SharedSignIn.accessGroup = "test.group" }

    private func session(_ id: String, expiresIn: TimeInterval) -> AuthSession {
        AuthSession(accessToken: "tok-\(id)", refreshToken: "never-shared", expiresAt: .now.addingTimeInterval(expiresIn),
                    userID: id, phone: nil, email: "\(id)@example.com", hasProfile: true)
    }

    @Test func publishesTheAccessTokenAndNeverTheRefreshToken() throws {
        let keychain = MemoryBeaconKeychain()
        SharedSignIn.publish(session("u1", expiresIn: 3600), keychain: keychain)
        let raw = String(decoding: try #require(keychain.data), as: UTF8.self)
        #expect(raw.contains("tok-u1"))
        #expect(!raw.contains("never-shared"))
    }

    @Test func ignoresExpiredBeacon() {
        let keychain = MemoryBeaconKeychain()
        SharedSignIn.publish(session("u1", expiresIn: 90), keychain: keychain)
        // Less than the two minutes a handoff round trip needs.
        #expect(SharedSignIn.current(keychain: keychain) == nil)
    }

    @Test func returnsAFreshBeacon() {
        let keychain = MemoryBeaconKeychain()
        SharedSignIn.publish(session("u1", expiresIn: 3600), keychain: keychain)
        #expect(SharedSignIn.current(keychain: keychain)?.userID == "u1")
        #expect(SharedSignIn.current(keychain: keychain)?.label == "u1@example.com")
    }

    @Test func withdrawOnlyClearsItsOwnAccount() {
        let keychain = MemoryBeaconKeychain()
        SharedSignIn.publish(session("u1", expiresIn: 3600), keychain: keychain)
        SharedSignIn.withdraw(userID: "u2", keychain: keychain)
        #expect(SharedSignIn.current(keychain: keychain) != nil)
        SharedSignIn.withdraw(userID: "u1", keychain: keychain)
        #expect(SharedSignIn.current(keychain: keychain) == nil)
    }

    @Test func doesNothingWithoutAGroup() {
        SharedSignIn.accessGroup = nil
        defer { SharedSignIn.accessGroup = "test.group" }
        let keychain = MemoryBeaconKeychain()
        SharedSignIn.publish(session("u1", expiresIn: 3600), keychain: keychain)
        #expect(keychain.data == nil)
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `cd LifeOSKit && swift test --filter SharedSignInTests`
Expected: a compile failure, "cannot find 'SharedSignIn'".

- [ ] **Step 3: Implement**

```swift
// LifeOSKit/Sources/Integrations/SharedSignIn.swift
import Foundation
import Security

/// What a signed-in LifeOS app leaves for its siblings: an access token, never
/// the refresh token.
///
/// Supabase rotates the refresh token on every refresh and revokes the family
/// when a used one is presented again, so two apps holding one refresh token
/// would sign each other out. A sibling instead trades this short-lived access
/// token at `session-handoff` for a session entirely its own.
public struct SignInBeacon: Codable, Equatable, Sendable {
    public let userID: String
    public let label: String
    public let accessToken: String
    public let expiresAt: Date
}

public protocol BeaconKeychain: Sendable {
    func read() -> Data?
    func write(_ data: Data)
    func delete()
}

public enum SharedSignIn {
    /// Set once at launch by an app whose entitlements include the shared
    /// group. Nil (tests, extensions) turns every call into a no-op.
    nonisolated(unsafe) public static var accessGroup: String?

    /// A handoff is a network round trip; a token about to lapse would be
    /// refused on arrival.
    static let minimumRemaining: TimeInterval = 120

    public static func publish(_ session: AuthSession, keychain: (any BeaconKeychain)? = nil) {
        guard let store = keychain ?? defaultKeychain else { return }
        let beacon = SignInBeacon(userID: session.userID,
                                  label: session.email ?? session.phone ?? "your account",
                                  accessToken: session.accessToken, expiresAt: session.expiresAt)
        guard let data = try? JSONEncoder().encode(beacon) else { return }
        store.write(data)
    }

    public static func current(now: Date = .now, keychain: (any BeaconKeychain)? = nil) -> SignInBeacon? {
        guard let store = keychain ?? defaultKeychain, let data = store.read(),
              let beacon = try? JSONDecoder().decode(SignInBeacon.self, from: data),
              beacon.expiresAt.timeIntervalSince(now) > minimumRemaining else { return nil }
        return beacon
    }

    public static func withdraw(userID: String, keychain: (any BeaconKeychain)? = nil) {
        guard let store = keychain ?? defaultKeychain, let data = store.read(),
              let beacon = try? JSONDecoder().decode(SignInBeacon.self, from: data),
              beacon.userID == userID else { return }
        store.delete()
    }

    private static var defaultKeychain: (any BeaconKeychain)? {
        accessGroup.map(GroupKeychain.init(group:))
    }
}

/// The real store: one generic password in the shared access group.
struct GroupKeychain: BeaconKeychain {
    let group: String
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "ai.lifeos.signin-beacon",
         kSecAttrAccount as String: "beacon",
         kSecAttrAccessGroup as String: group]
    }
    func read() -> Data? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }
    func write(_ data: Data) {
        let attributes: [String: Any] = [kSecValueData as String: data,
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { current, _ in current }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }
    func delete() { SecItemDelete(query as CFDictionary) }
}
```

Note that the beacon test above uses `withdraw(userID:keychain:)`, with
`keychain` as the second label. Keep that signature.

Hook it into `KeychainAuthSessionStore`. At the end of `save(_:)`, after a
successful write:

```swift
        SharedSignIn.publish(session)
```

At the start of `clear()`, before `SecItemDelete`:

```swift
        if let current = load() { SharedSignIn.withdraw(userID: current.userID) }
```

- [ ] **Step 4: Turn sharing on in LifeOS**

Add to `LIfeOS/LIfeOS.entitlements`, inside the top-level `<dict>`, in this
order:

```xml
	<key>keychain-access-groups</key>
	<array>
		<string>$(AppIdentifierPrefix)com.shivvyas.lifeos</string>
		<string>$(AppIdentifierPrefix)com.shivvyas.lifeos.shared</string>
	</array>
```

The first entry has to be the app's own identifier, so the default group,
which is where every existing session item lives, stays the same.

In `LIfeOSApp.init()`, before anything reads the session:

```swift
        SharedSignIn.accessGroup = "Z42YU5W6WY.com.shivvyas.lifeos.shared"
```

- [ ] **Step 5: Run the tests, then confirm on the simulator that existing sign-ins survive**

Run: `cd LifeOSKit && swift test --filter "SharedSignInTests|SessionRefreshTests"`
Expected: they pass.

Then confirm on the simulator:
1. Install the build from `origin/main`, sign in, and quit.
2. Install this branch's build over it and launch.
3. Expected: still signed in. If this fails, the entitlement order is wrong.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Integrations LifeOSKit/Tests/IntegrationsTests/SharedSignInTests.swift LIfeOS/LIfeOS.entitlements LIfeOS/App/LIfeOSApp.swift
git commit -m "feat(account): leave a short-lived sign-in beacon for sibling apps"
```

### Task 5: `session-handoff`, and "Continue as"

**Files:**
- Modify: `supabase/functions/_shared/otp_twilio.ts` (extract `sessionForEmail`)
- Create: `supabase/functions/_shared/handoff.ts`
- Create: `supabase/functions/session-handoff/index.ts`
- Create: `supabase/functions/_shared/handoff_test.ts`
- Modify: `LifeOSKit/Sources/Integrations/SupabaseAuth.swift` (replace the `handoff` stub)
- Modify: `LifeOSKit/Sources/AccountUI/SignInModel.swift` (add `sharedAccount`, `continueAsShared()`)
- Modify: `LifeOSKit/Sources/AccountUI/SignInScreens.swift` (a "Continue as" button on `IdentityScreen`)
- Modify: `docs/superpowers/specs/2026-10-10-lifeos-focus-app-design.md` (the amendment)
- Test: `LifeOSKit/Tests/IntegrationsTests/HandoffTests.swift`, plus additions to `SignInModelTests.swift`

**Interfaces:**
- Consumes: `SignInBeacon` and `SharedSignIn.current()` (Task 4), and
  `SignInModel.finish(with:)` (Task 2).
- Produces:
  - `POST /functions/v1/session-handoff`, with header
    `Authorization: Bearer <access token>` and no body. It returns
    200 with the GoTrue session JSON (the same shape `/auth/v1/verify`
    returns), or 401 `{"error":"unauthorized"}`.
  - `SupabaseAuth.handoff(accessToken:) async throws -> AuthSession`
  - `SignInModel.sharedAccount: SignInBeacon?`, `refreshSharedAccount()` and
    `continueAsShared() async`

- [ ] **Step 1: Extract the session minting on the server**

In `otp_twilio.ts`, split off the part of `mintSession` that runs from
`generate_link` through the final `Response`, as:

```ts
export async function sessionForEmail(args: {
  supabaseURL: string;
  serviceKey: string;
  anonKey: string;
  email: string;
  fetchImpl?: typeof fetch;
}): Promise<Response> {
  const f = args.fetchImpl ?? fetch;
  // body: the existing generate_link + verify code, with `fetch` replaced by `f`
  // and `email` taken from args.
}
```

`mintSession` then ends with
`return sessionForEmail({ ...args, email });`.

Run `deno test supabase/functions/_shared/otp_session_test.ts`. Expected: it
still passes.

- [ ] **Step 2: Write the failing Deno test**

```ts
// supabase/functions/_shared/handoff_test.ts
import { assertEquals } from "jsr:@std/assert";
import { handleHandoff } from "./handoff.ts";

const env = { supabaseURL: "https://x.supabase.co", serviceKey: "svc", anonKey: "anon" };

Deno.test("refuses a request with no user", async () => {
  const res = await handleHandoff(new Request("https://f/", { method: "POST" }), {
    ...env,
    resolveEmail: () => Promise.resolve(null),
    mint: () => Promise.resolve(new Response("{}")),
  });
  assertEquals(res.status, 401);
});

Deno.test("mints a session for the caller's own email", async () => {
  let minted = "";
  const res = await handleHandoff(
    new Request("https://f/", { method: "POST", headers: { Authorization: "Bearer t" } }),
    {
      ...env,
      resolveEmail: () => Promise.resolve("s@example.com"),
      mint: (email) => { minted = email; return Promise.resolve(new Response('{"access_token":"new"}')); },
    },
  );
  assertEquals(res.status, 200);
  assertEquals(minted, "s@example.com");
});

Deno.test("rejects anything but POST", async () => {
  const res = await handleHandoff(new Request("https://f/", { method: "GET" }), {
    ...env,
    resolveEmail: () => Promise.resolve("s@example.com"),
    mint: () => Promise.resolve(new Response("{}")),
  });
  assertEquals(res.status, 405);
});
```

Run: `deno test supabase/functions/_shared/handoff_test.ts`
Expected: FAIL, "Module not found ./handoff.ts".

- [ ] **Step 3: Implement the handler and the function**

```ts
// supabase/functions/_shared/handoff.ts
// Trades a signed-in app's access token for a new, independent session, so a
// sibling app on the same phone can sign in without a code and without ever
// holding the other app's refresh token.
import { json } from "./otp_guard.ts";

export async function handleHandoff(req: Request, deps: {
  supabaseURL: string;
  serviceKey: string;
  anonKey: string;
  resolveEmail: (req: Request) => Promise<string | null>;
  mint: (email: string) => Promise<Response>;
}): Promise<Response> {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const email = await deps.resolveEmail(req);
  if (!email) return json({ error: "unauthorized" }, 401);
  return deps.mint(email);
}
```

```ts
// supabase/functions/session-handoff/index.ts
import { createClient } from "jsr:@supabase/supabase-js@2";
import { handleHandoff } from "../_shared/handoff.ts";
import { sessionForEmail } from "../_shared/otp_twilio.ts";

Deno.serve((req) => {
  const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  return handleHandoff(req, {
    supabaseURL, serviceKey, anonKey,
    // The caller is whoever their own token says. Never an id from the body.
    resolveEmail: async (r) => {
      const authorization = r.headers.get("Authorization");
      if (!authorization) return null;
      const client = createClient(supabaseURL, anonKey, { global: { headers: { Authorization: authorization } } });
      const { data, error } = await client.auth.getUser();
      return error || !data.user?.email ? null : data.user.email;
    },
    mint: (email) => sessionForEmail({ supabaseURL, serviceKey, anonKey, email }),
  });
});
```

Phone accounts already have the synthetic email `otp_twilio.ts` assigns, so
`data.user.email` is present for them too.

Run: `deno test supabase/functions/_shared/handoff_test.ts`
Expected: 3 tests pass.

- [ ] **Step 4: Write the failing Swift tests**

The client side goes in `HandoffTests.swift`. It reuses `AuthStubURLProtocol`
from `SessionRefreshTests.swift` and follows that file's
`URLSessionConfiguration.ephemeral` + `protocolClasses` setup.

```swift
import Testing
import Foundation
@testable import Integrations

@Suite(.serialized)
struct HandoffTests {
    private func auth() -> SupabaseAuth {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AuthStubURLProtocol.self]
        return SupabaseAuth(baseURL: URL(string: "https://x.supabase.co")!, anonKey: "anon",
                            session: URLSession(configuration: config))
    }

    @Test func decodesTheNewSession() async throws {
        AuthStubURLProtocol.reset()
        AuthStubURLProtocol.replies = [.ok(#"{"access_token":"new","refresh_token":"r2","expires_in":3600,"user":{"id":"u1","email":"s@example.com","user_metadata":{"first_name":"Shiv"}}}"#)]
        let session = try await auth().handoff(accessToken: "old")
        #expect(session.accessToken == "new")
        #expect(session.refreshToken == "r2")
        #expect(session.userID == "u1")
    }

    @Test func aRefusalThrowsAServerError() async {
        AuthStubURLProtocol.reset()
        AuthStubURLProtocol.replies = [.status(401, #"{"error":"unauthorized"}"#)]
        await #expect(throws: AuthError.self) { try await auth().handoff(accessToken: "old") }
    }
}
```

Copy the success body's shape from the fixture `SessionRefreshTests` already
uses. If `decode` expects other keys, use the keys it expects.

Add to `SignInModelTests`:

```swift
    @Test func continueAsSignsInWithTheHandedOverSession() async {
        let backend = FakeBackend()
        backend.handoffResult = .success(.sample(id: "u1"))
        var handed: AuthSession?
        let model = SignInModel(backend: backend, store: InMemoryAuthSessionStore(), onSignedIn: { handed = $0 })
        model.sharedAccount = SignInBeacon(userID: "u1", label: "s@example.com", accessToken: "t",
                                           expiresAt: .now.addingTimeInterval(3600))
        await model.continueAsShared()
        #expect(handed?.userID == "u1")
        #expect(model.step == .done)
    }

    @Test func handoffRefusedFallsBackQuietly() async {
        let backend = FakeBackend()
        backend.handoffResult = .failure(AuthError.server(status: 401, message: "unauthorized"))
        let model = SignInModel(backend: backend, store: InMemoryAuthSessionStore(), onSignedIn: { _ in })
        model.sharedAccount = SignInBeacon(userID: "u1", label: "s@example.com", accessToken: "t",
                                           expiresAt: .now.addingTimeInterval(3600))
        await model.continueAsShared()
        #expect(model.sharedAccount == nil)
        #expect(model.errorMessage == nil)
        #expect(model.step == .identity)
    }
```

Run: `cd LifeOSKit && swift test --filter "HandoffTests|SignInModelTests"`
Expected: FAIL, because `handoff` throws 501 and `continueAsShared` is not
defined.

- [ ] **Step 5: Implement the Swift side**

In `SupabaseAuth.swift`, replace the stub:

```swift
    /// Exchanges another app's access token for a session of this app's own.
    /// See `SharedSignIn` for why the refresh token is never shared instead.
    public func handoff(accessToken: String) async throws -> AuthSession {
        var request = URLRequest(url: baseURL.appendingPathComponent("functions/v1/session-handoff"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch { throw AuthError.transport }
        try check(response, data)
        return try decode(data)
    }
```

In `SignInModel.swift`, add:

```swift
    /// The account a sibling app on this phone is signed in to, if its token
    /// is fresh enough to trade. Read when the identity screen appears.
    public var sharedAccount: SignInBeacon?

    public func refreshSharedAccount() { sharedAccount = SharedSignIn.current() }

    /// One tap instead of a code. A refusal just hides the offer: the code
    /// flow underneath still works, and an error for a shortcut nobody
    /// asked to fail would only confuse.
    public func continueAsShared() async {
        guard let backend, let beacon = sharedAccount else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let session = try await backend.handoff(accessToken: beacon.accessToken)
            try? store.save(session)
            finish(with: session)
        } catch {
            log.info("handoff refused; offering the code flow")
            sharedAccount = nil
        }
    }
```

In `IdentityScreen`, above the channel picker:

```swift
                if let shared = model.sharedAccount {
                    OnboardingActionButton("Continue as \(shared.label)", isLoading: model.isBusy) {
                        Task { await model.continueAsShared() }
                    }
                    Text("or use a code").font(LifeOSType.caption)
                        .foregroundStyle(Editorial.quietInk(scheme))
                }
```

In its existing `.task`, call `model.refreshSharedAccount()` before
`await model.loadChannels()`.

LifeOS hands the session to `didSignIn`, which already saves it to the
account's Keychain slot, so `try? store.save` in the model is a harmless
second write there. Focus relies on it.

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `cd LifeOSKit && swift test --filter "HandoffTests|SignInModelTests|SharedSignInTests"`
Then run: `deno test supabase/functions/_shared/`
Expected: all pass.

- [ ] **Step 7: Amend the spec**

In the spec, replace the paragraph under "Shared sign-in on one device" with:

> Both apps leave a **sign-in beacon** in the shared Keychain access group
> (`$(AppIdentifierPrefix)com.shivvyas.lifeos.shared`). The beacon holds the
> user id, a label and the current **access token only**. A sibling app that
> finds a beacon with more than two minutes left offers **"Continue as
> <label>"**. On a tap, it trades the token at the `session-handoff` Edge
> Function for a new session of its own, with its own refresh token. Refresh
> tokens are never shared: Supabase rotates them, and a reused one revokes the
> whole family, which would sign both apps out. Signing out of one app
> withdraws its beacon but leaves the other app signed in.

- [ ] **Step 8: Commit**

```bash
git add supabase/functions LifeOSKit docs/superpowers/specs/2026-10-10-lifeos-focus-app-design.md
git commit -m "feat(account): continue as the account a sibling app is signed in to"
```

- [ ] **Step 9: Open the slice 1 PR**

Push `feat/account-ui`. Open a PR titled
"feat(account): AccountUI and sign-in handoff". The body lists the owner step
`supabase functions deploy session-handoff`. Don't merge it.

---

## Slice 2: Focus sync (branch `feat/focus-sync`, off `origin/main` after slice 1 merges, or stacked on `feat/account-ui`)

### Task 6: The `focus_sessions` table

**Files:**
- Create: `supabase/migrations/20261010120000_focus_sessions.sql`
- Create: `supabase/tests/focus_sessions_rls.sql`

- [ ] **Step 1: Write the access check first**

```sql
-- supabase/tests/focus_sessions_rls.sql
-- Run against a local stack: supabase db reset && psql "$DB_URL" -f supabase/tests/focus_sessions_rls.sql
begin;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'a@example.com'),
  ('00000000-0000-0000-0000-0000000000b2', 'b@example.com');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1"}';
insert into public.focus_sessions (id, mood, source, started_at, ended_at, focused_seconds)
values ('11111111-1111-1111-1111-111111111111', 'focus', 'soundscape', now() - interval '30 min', now(), 1500);

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000b2"}';
do $$ begin
  if (select count(*) from public.focus_sessions) <> 0 then
    raise exception 'user b can read user a''s focus sessions';
  end if;
end $$;

do $$ begin
  begin
    insert into public.focus_sessions (id, user_id, mood, source, started_at, focused_seconds)
    values (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a1', 'focus', 'soundscape', now(), 1);
    raise exception 'user b inserted a row as user a';
  exception when insufficient_privilege or check_violation then null;
  end;
end $$;

do $$ declare n int; begin
  update public.focus_sessions set focused_seconds = 1;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'sessions are final but an update changed % rows', n; end if;
end $$;
rollback;
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `supabase db reset && psql "$(supabase status -o env | sed -n 's/^DB_URL=//p' | tr -d '"')" -f supabase/tests/focus_sessions_rls.sql`
Expected: ERROR, relation "public.focus_sessions" does not exist.

- [ ] **Step 3: Write the migration**

```sql
-- supabase/migrations/20261010120000_focus_sessions.sql
-- One row per finished focus session, written by LifeOS or LifeOS Focus and
-- read by both. The id is the device's own record id, so a resend after a
-- lost response is a duplicate the insert ignores, never a second row.
create table public.focus_sessions (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  mood text not null check (mood in ('focus', 'brainstorm', 'relax', 'sleep')),
  source text not null check (source in ('soundscape', 'appleMusic', 'silence')),
  started_at timestamptz not null,
  ended_at timestamptz,
  focused_seconds integer not null check (focused_seconds >= 0),
  blocks_completed integer not null default 0 check (blocks_completed >= 0),
  project_task_id uuid references public.project_tasks (id) on delete set null,
  created_at timestamptz not null default now()
);

create index focus_sessions_user_started on public.focus_sessions (user_id, started_at desc);

alter table public.focus_sessions enable row level security;

create policy "own focus sessions are readable" on public.focus_sessions
  for select to authenticated using (user_id = auth.uid());
create policy "own focus sessions can be added" on public.focus_sessions
  for insert to authenticated with check (user_id = auth.uid());
create policy "own focus sessions can be deleted" on public.focus_sessions
  for delete to authenticated using (user_id = auth.uid());
-- No update policy: a session is final once it ends.
```

- [ ] **Step 4: Run the check and confirm it passes**

Run the same command as Step 2.
Expected: `ROLLBACK`, with no `ERROR` line.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20261010120000_focus_sessions.sql supabase/tests/focus_sessions_rls.sql
git commit -m "feat(focus): add the focus_sessions table with per-user access"
```

### Task 7: Local record bookkeeping (`syncedAt`, pending, merge)

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/FocusSessionRecord.swift`
- Test: `LifeOSKit/Tests/PersistenceTests/FocusStoreTests.swift`

**Interfaces:**
- Produces:
  - `FocusSessionRecord.syncedAt: Date?`, defaulting to nil
  - `FocusStore.pending(limit: Int = 200) throws -> [FocusSessionRecord]`
    returns records with `syncedAt == nil` and `endedAt != nil`, oldest
    first
  - `FocusStore.markSynced(ids: [UUID], at: Date = .now) throws`
  - `FocusStore.merge(remote: [FocusSessionSnapshot]) throws -> Int` inserts
    unknown ids with `syncedAt` set, and returns how many it inserted
  - `public struct FocusSessionSnapshot: Sendable, Equatable`, holding `id`,
    `mood`, `source`, `startedAt`, `endedAt`, `focusedSeconds`,
    `blocksCompleted` and `projectTaskID`. It is the plain value both sides
    use.

- [ ] **Step 1: Write the failing tests**

Add these to `FocusStoreTests.swift`. Use the existing in-memory container
setup in that file, and follow its helper names.

```swift
    @Test func pendingExcludesUnfinished() throws {
        let context = try makeContext()
        let store = FocusStore(context: context)
        try store.record(mood: "focus", source: "soundscape", startedAt: .now.addingTimeInterval(-600),
                         endedAt: .now, focusedSeconds: 600, blocksCompleted: 1, projectTaskID: nil)
        context.insert(FocusSessionRecord(mood: "focus", source: "soundscape", startedAt: .now,
                                          endedAt: nil, focusedSeconds: 0, blocksCompleted: 0, projectTaskID: nil))
        try context.save()
        #expect(try store.pending().count == 1)
    }

    @Test func markSyncedRemovesFromPending() throws {
        let context = try makeContext()
        let store = FocusStore(context: context)
        try store.record(mood: "focus", source: "soundscape", startedAt: .now.addingTimeInterval(-600),
                         endedAt: .now, focusedSeconds: 600, blocksCompleted: 1, projectTaskID: nil)
        let ids = try store.pending().map(\.id)
        try store.markSynced(ids: ids)
        #expect(try store.pending().isEmpty)
    }

    @Test func mergeSkipsKnownIDs() throws {
        let context = try makeContext()
        let store = FocusStore(context: context)
        try store.record(mood: "focus", source: "soundscape", startedAt: .now.addingTimeInterval(-600),
                         endedAt: .now, focusedSeconds: 600, blocksCompleted: 1, projectTaskID: nil)
        let local = try #require(try store.pending().first)
        let known = FocusSessionSnapshot(id: local.id, mood: "relax", source: "silence", startedAt: local.startedAt,
                                         endedAt: local.endedAt, focusedSeconds: 1, blocksCompleted: 0, projectTaskID: nil)
        let fresh = FocusSessionSnapshot(id: UUID(), mood: "focus", source: "appleMusic", startedAt: .now.addingTimeInterval(-300),
                                         endedAt: .now, focusedSeconds: 300, blocksCompleted: 1, projectTaskID: nil)
        #expect(try store.merge(remote: [known, fresh]) == 1)
        #expect(local.mood == "focus")
        #expect(try store.focusedSeconds(on: .now) == 900)
        #expect(try store.pending().count == 1)
    }
```

The last expectation holds because the merged row arrives already synced, and
the local record is still pending.

- [ ] **Step 2: Run them and confirm they fail**

Run: `cd LifeOSKit && swift test --filter FocusStoreTests`
Expected: compile failures, "no member 'pending'" and "cannot find 'FocusSessionSnapshot'".

- [ ] **Step 3: Implement**

In `FocusSessionRecord`, add:

```swift
    /// When the server confirmed this session. Nil means it still has to go.
    /// Optional, so stores written before sync open unchanged.
    public var syncedAt: Date?
```

Add to `FocusSessionRecord.swift`:

```swift
/// A session as plain values: what crosses to and from the server, so the
/// sync layer never holds a model object off its context.
public struct FocusSessionSnapshot: Sendable, Equatable {
    public let id: UUID
    public let mood: String
    public let source: String
    public let startedAt: Date
    public let endedAt: Date?
    public let focusedSeconds: Double
    public let blocksCompleted: Int
    public let projectTaskID: UUID?

    public init(id: UUID, mood: String, source: String, startedAt: Date, endedAt: Date?,
                focusedSeconds: Double, blocksCompleted: Int, projectTaskID: UUID?) {
        self.id = id; self.mood = mood; self.source = source; self.startedAt = startedAt
        self.endedAt = endedAt; self.focusedSeconds = focusedSeconds
        self.blocksCompleted = blocksCompleted; self.projectTaskID = projectTaskID
    }
}

extension FocusSessionRecord {
    public var snapshot: FocusSessionSnapshot {
        FocusSessionSnapshot(id: id, mood: mood, source: source, startedAt: startedAt, endedAt: endedAt,
                             focusedSeconds: focusedSeconds, blocksCompleted: blocksCompleted,
                             projectTaskID: projectTaskID)
    }
}
```

Add to `FocusStore`:

```swift
    /// Finished sessions the server has not confirmed, oldest first. A
    /// session still running (no end) never goes.
    public func pending(limit: Int = 200) throws -> [FocusSessionRecord] {
        var descriptor = FetchDescriptor<FocusSessionRecord>(
            predicate: #Predicate { $0.syncedAt == nil && $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt)])
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    public func markSynced(ids: [UUID], at date: Date = .now) throws {
        guard !ids.isEmpty else { return }
        let wanted = Set(ids)
        for record in try context.fetch(FetchDescriptor<FocusSessionRecord>()) where wanted.contains(record.id) {
            record.syncedAt = date
        }
        try context.save()
    }

    /// Adds sessions recorded elsewhere. A known id is left alone: this
    /// device's copy is the one it wrote, and sessions never change after.
    @discardableResult
    public func merge(remote: [FocusSessionSnapshot], at date: Date = .now) throws -> Int {
        let known = Set(try context.fetch(FetchDescriptor<FocusSessionRecord>()).map(\.id))
        var inserted = 0
        for row in remote where !known.contains(row.id) {
            let record = FocusSessionRecord(mood: row.mood, source: row.source, startedAt: row.startedAt,
                                            endedAt: row.endedAt, focusedSeconds: row.focusedSeconds,
                                            blocksCompleted: row.blocksCompleted, projectTaskID: row.projectTaskID)
            record.id = row.id
            record.syncedAt = date
            context.insert(record)
            inserted += 1
        }
        if inserted > 0 { try context.save() }
        return inserted
    }
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `cd LifeOSKit && swift test --filter FocusStoreTests`
Expected: all pass, the old tests included.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Persistence/FocusSessionRecord.swift LifeOSKit/Tests/PersistenceTests/FocusStoreTests.swift
git commit -m "feat(focus): track which sessions the server has, and merge ones from elsewhere"
```

### Task 8: The `FocusSync` module

**Files:**
- Modify: `LifeOSKit/Package.swift`
- Create: `LifeOSKit/Sources/FocusSync/FocusRow.swift`
- Create: `LifeOSKit/Sources/FocusSync/FocusRemote.swift`
- Create: `LifeOSKit/Sources/FocusSync/FocusSync.swift`
- Test: `LifeOSKit/Tests/FocusSyncTests/FocusSyncTests.swift`

**Interfaces:**
- Consumes: `FocusStore.pending`, `markSynced`, `merge` and
  `FocusSessionSnapshot` (Task 7). From `Integrations`, `SupabaseREST` with
  `insertIgnoringDuplicates(table:body:accessToken:)`, `AuthSession`, and
  `AuthSessionStoring`.
- Produces:
  - `public protocol FocusRemote: Sendable`, with
    `insertIgnoringDuplicates(table:body:accessToken:) async throws` and
    `focusRows(since: Date, accessToken: String) async throws -> Data`
  - `@MainActor public final class FocusSync`, with:
    - `public init(context: ModelContext, remote: any FocusRemote, session: @escaping @MainActor () -> AuthSession?)`
    - `public func run() async`, which uploads and then pulls, with at most
      one run in flight
    - `public func uploadPending() async -> Int`, returning how many it marked
      as synced
    - `public func pullWeek(now: Date = .now, calendar: Calendar = .current) async -> Int`
    - `public var pendingCount: Int`

- [ ] **Step 1: Add the target**

In `Package.swift`, in `products`, add:

```swift
        .library(name: "FocusSync", targets: ["FocusSync"]),
```

In `targets`, add:

```swift
        .target(name: "FocusSync", dependencies: ["Persistence", "Integrations"]),
        .testTarget(name: "FocusSyncTests", dependencies: ["FocusSync"]),
```

- [ ] **Step 2: Write the failing tests**

```swift
// LifeOSKit/Tests/FocusSyncTests/FocusSyncTests.swift
import Testing
import Foundation
import SwiftData
import Integrations
@testable import Persistence
@testable import FocusSync

final class FakeRemote: FocusRemote, @unchecked Sendable {
    var inserted: [Data] = []
    var insertError: Error?
    var rows = Data("[]".utf8)
    func insertIgnoringDuplicates(table: String, body: Data, accessToken: String) async throws {
        if let insertError { throw insertError }
        inserted.append(body)
    }
    func focusRows(since: Date, accessToken: String) async throws -> Data { rows }
}

@MainActor
struct FocusSyncTests {
    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: FocusSessionRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
    private let signedIn = AuthSession(accessToken: "t", refreshToken: "r", expiresAt: .now.addingTimeInterval(3600),
                                       userID: "u1", phone: nil, email: nil)

    private func finished(_ context: ModelContext) throws {
        try FocusStore(context: context).record(mood: "focus", source: "soundscape",
            startedAt: .now.addingTimeInterval(-900), endedAt: .now, focusedSeconds: 900,
            blocksCompleted: 1, projectTaskID: nil)
    }

    @Test func uploadsPendingAndMarksThem() async throws {
        let ctx = try context(); try finished(ctx)
        let remote = FakeRemote()
        let sync = FocusSync(context: ctx, remote: remote, session: { self.signedIn })
        #expect(await sync.uploadPending() == 1)
        #expect(sync.pendingCount == 0)
        let body = String(decoding: try #require(remote.inserted.first), as: UTF8.self)
        #expect(body.contains("\"focused_seconds\":900"))
        #expect(!body.contains("user_id"))   // the server fills it from the token
    }

    @Test func skipsWhenSignedOut() async throws {
        let ctx = try context(); try finished(ctx)
        let remote = FakeRemote()
        let sync = FocusSync(context: ctx, remote: remote, session: { nil })
        #expect(await sync.uploadPending() == 0)
        #expect(remote.inserted.isEmpty)
        #expect(sync.pendingCount == 1)
    }

    @Test func aFailedUploadLeavesRecordsPending() async throws {
        let ctx = try context(); try finished(ctx)
        let remote = FakeRemote()
        remote.insertError = SupabaseREST.RESTError.transport
        let sync = FocusSync(context: ctx, remote: remote, session: { self.signedIn })
        #expect(await sync.uploadPending() == 0)
        #expect(sync.pendingCount == 1)
    }

    @Test func pullMergesRowsFromElsewhere() async throws {
        let ctx = try context()
        let remote = FakeRemote()
        let id = UUID()
        remote.rows = Data("""
        [{"id":"\(id)","mood":"relax","source":"silence","started_at":"2026-10-10T09:00:00Z",
          "ended_at":"2026-10-10T09:25:00Z","focused_seconds":1500,"blocks_completed":1,"project_task_id":null}]
        """.utf8)
        let sync = FocusSync(context: ctx, remote: remote, session: { self.signedIn })
        #expect(await sync.pullWeek(now: ISO8601DateFormatter().date(from: "2026-10-10T12:00:00Z")!) == 1)
        #expect(await sync.pullWeek(now: ISO8601DateFormatter().date(from: "2026-10-10T12:00:00Z")!) == 0)
    }
}
```

The fourth Review Focus item, re-sends without duplicates, is covered by
`SupabaseREST.insertIgnoringDuplicates`, which sets
`Prefer: resolution=ignore-duplicates`. Add this test to the existing
`IntegrationsTests`, in a new file `SupabaseRESTPreferTests.swift`. Give it its
own `URLProtocol` subclass that records the last request:

```swift
import Testing
import Foundation
@testable import Integrations

final class RecordingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var last: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.last = request
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 201,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct SupabaseRESTPreferTests {
    @Test func resendUsesIgnoreDuplicates() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingURLProtocol.self]
        let rest = SupabaseREST(baseURL: URL(string: "https://x.supabase.co")!, anonKey: "anon",
                                session: URLSession(configuration: config))
        try await rest.insertIgnoringDuplicates(table: "focus_sessions", body: Data("[{}]".utf8), accessToken: "t")
        #expect(RecordingURLProtocol.last?.value(forHTTPHeaderField: "Prefer")?
            .contains("resolution=ignore-duplicates") == true)
        #expect(RecordingURLProtocol.last?.value(forHTTPHeaderField: "Authorization") == "Bearer t")
    }
}
```

- [ ] **Step 3: Run them and confirm they fail**

Run: `cd LifeOSKit && swift test --filter "FocusSyncTests|SupabaseRESTPreferTests"`
Expected: `FocusSyncTests` fails to compile ("no such module 'FocusSync'"
until the sources exist). `SupabaseRESTPreferTests` should already pass,
because the behaviour exists, which shows the guarantee holds.

- [ ] **Step 4: Implement**

```swift
// LifeOSKit/Sources/FocusSync/FocusRow.swift
import Foundation
import Persistence

/// `focus_sessions` on the wire. No user_id going up: the column defaults to
/// auth.uid(), so a client can never write a row as someone else.
struct FocusRow: Codable {
    let id: UUID
    let mood: String
    let source: String
    let started_at: Date
    let ended_at: Date?
    let focused_seconds: Int
    let blocks_completed: Int
    let project_task_id: UUID?

    init(_ s: FocusSessionSnapshot) {
        id = s.id; mood = s.mood; source = s.source; started_at = s.startedAt; ended_at = s.endedAt
        focused_seconds = Int(s.focusedSeconds.rounded()); blocks_completed = s.blocksCompleted
        project_task_id = s.projectTaskID
    }

    var snapshot: FocusSessionSnapshot {
        FocusSessionSnapshot(id: id, mood: mood, source: source, startedAt: started_at, endedAt: ended_at,
                             focusedSeconds: Double(focused_seconds), blocksCompleted: blocks_completed,
                             projectTaskID: project_task_id)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = .sortedKeys; return e
    }()

    /// PostgREST returns fractional seconds and an offset; accept both forms.
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        d.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = fractional.date(from: text) ?? plain.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: text))
        }
        return d
    }()
}
```

The upload test checks for `"focused_seconds":900`. With `.sortedKeys` and no
pretty printing, that is the exact substring.

```swift
// LifeOSKit/Sources/FocusSync/FocusRemote.swift
import Foundation
import Integrations

public protocol FocusRemote: Sendable {
    func insertIgnoringDuplicates(table: String, body: Data, accessToken: String) async throws
    func focusRows(since: Date, accessToken: String) async throws -> Data
}

extension SupabaseREST: FocusRemote {
    /// This user's sessions that started at or after `since`, newest first.
    /// Row Level Security limits it to the caller; no user filter is needed.
    public func focusRows(since: Date, accessToken: String) async throws -> Data {
        try await select(table: "focus_sessions",
                         query: [URLQueryItem(name: "select", value: "*"),
                                 URLQueryItem(name: "started_at", value: "gte.\(SupabaseREST.timestamp(since))"),
                                 URLQueryItem(name: "order", value: "started_at.desc"),
                                 URLQueryItem(name: "limit", value: "500")],
                         accessToken: accessToken)
    }
}
```

`SupabaseREST` has no generic `select(table:query:accessToken:)` yet. Add one
next to `fetch(table:column:equals:)` in `SupabaseREST.swift`. It is the same
body as that function, with the query items passed in:

```swift
    /// A select with caller-supplied PostgREST query items.
    public func select(table: String, query: [URLQueryItem], accessToken: String) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/\(table)"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = query
        guard let url = components?.url else { throw RESTError.encoding }
        var request = URLRequest(url: url)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }
```

Check that `SupabaseREST.timestamp(_:)` is at least `internal`, since it is
used from `fetch(table:since:)`. If it is `private`, make it `public static`.

```swift
// LifeOSKit/Sources/FocusSync/FocusSync.swift
import Foundation
import SwiftData
import OSLog
import Integrations
import Persistence

private let log = Logger(subsystem: "com.shivvyas.lifeos", category: "focus-sync")

/// Sends finished sessions up and brings the week's sessions down.
///
/// Every failure leaves state as it was: an unsent record stays pending and
/// goes on the next run. A run is never retried in a loop; the next trigger
/// (a save, the app becoming active, the network returning) is the retry.
@MainActor
public final class FocusSync {
    private let store: FocusStore
    private let remote: any FocusRemote
    private let session: @MainActor () -> AuthSession?
    private var running: Task<Void, Never>?

    public init(context: ModelContext, remote: any FocusRemote,
                session: @escaping @MainActor () -> AuthSession?) {
        self.store = FocusStore(context: context)
        self.remote = remote
        self.session = session
    }

    public var pendingCount: Int { (try? store.pending().count) ?? 0 }

    /// Upload, then pull. A call while a run is in flight joins that run.
    public func run() async {
        if let running { return await running.value }
        let task = Task { _ = await uploadPending(); _ = await pullWeek() }
        running = task
        await task.value
        running = nil
    }

    public func uploadPending() async -> Int {
        guard let token = usableToken() else { return 0 }
        guard let records = try? store.pending(), !records.isEmpty else { return 0 }
        let snapshots = records.map(\.snapshot)
        do {
            let body = try FocusRow.encoder.encode(snapshots.map(FocusRow.init))
            try await remote.insertIgnoringDuplicates(table: "focus_sessions", body: body, accessToken: token)
            try store.markSynced(ids: snapshots.map(\.id))
            return snapshots.count
        } catch {
            log.info("upload deferred: \(String(describing: error), privacy: .public)")
            return 0
        }
    }

    public func pullWeek(now: Date = .now, calendar: Calendar = .current) async -> Int {
        guard let token = usableToken(),
              let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        do {
            let data = try await remote.focusRows(since: start, accessToken: token)
            let rows = try FocusRow.decoder.decode([FocusRow].self, from: data)
            return try store.merge(remote: rows.map(\.snapshot))
        } catch {
            log.info("pull deferred: \(String(describing: error), privacy: .public)")
            return 0
        }
    }

    /// A token only while signed in and unexpired. Refreshing is the auth
    /// layer's job, done on foreground; this never refreshes on its own.
    private func usableToken() -> String? {
        guard let current = session(), !current.isExpired() else { return nil }
        return current.accessToken
    }
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `cd LifeOSKit && swift test --filter "FocusSyncTests|SupabaseRESTPreferTests|FocusStoreTests"`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Package.swift LifeOSKit/Sources/FocusSync LifeOSKit/Sources/Integrations/SupabaseREST.swift LifeOSKit/Tests/FocusSyncTests LifeOSKit/Tests/IntegrationsTests/SupabaseRESTPreferTests.swift
git commit -m "feat(focus): sync sessions with focus_sessions, safely on resend"
```

### Task 9: Run the sync from LifeOS

**Files:**
- Create: `LIfeOS/App/FocusSyncDriver.swift`
- Modify: `LIfeOS/App/RootView.swift` (create the driver, and run it on launch and when the app becomes active)
- Modify: `LIfeOS/Features/Focus/ViewModel/FocusSessionModel.swift` (run after a session is saved)
- Modify: the `LIfeOS` target's package products (add `FocusSync`, in the same way as `AccountUI` in Task 3)

**Interfaces:**
- Consumes: `FocusSync` (Task 8), `SupabaseREST`,
  `KeychainAuthSessionStore().load()`, and `AppConfig`.
- Produces: `@MainActor final class FocusSyncDriver`, with
  `static let shared`, `attach(_ context: ModelContext)`, and
  `request()`, which runs `FocusSync.run()` on a detached `Task`. It does
  nothing until it is attached and configured.

- [ ] **Step 1: Implement the driver**

```swift
// LIfeOS/App/FocusSyncDriver.swift
import Foundation
import Network
import SwiftData
import FocusSync
import Integrations

/// Decides when focus sessions sync: on launch, on becoming active, after a
/// session is saved, and when the network comes back. `FocusSync` decides
/// what; this only pulls the trigger. History from before sync existed goes
/// up on the first run, because every old record is still pending.
@MainActor
final class FocusSyncDriver {
    static let shared = FocusSyncDriver()
    private var sync: FocusSync?
    private let monitor = NWPathMonitor()
    private var wasOffline = false

    func attach(_ context: ModelContext) {
        guard sync == nil, let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey else { return }
        sync = FocusSync(context: context, remote: SupabaseREST(baseURL: url, anonKey: key),
                         session: { KeychainAuthSessionStore().load() })
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                if path.status == .satisfied, self.wasOffline { self.request() }
                self.wasOffline = path.status != .satisfied
            }
        }
        monitor.start(queue: .global(qos: .utility))
    }

    func request() {
        guard let sync else { return }
        Task { await sync.run() }
    }
}
```

- [ ] **Step 2: Wire the triggers**

In `RootView`, where the scene's `ModelContext` is first available (next to
the other launch work in `.task`), add:

```swift
FocusSyncDriver.shared.attach(context)
FocusSyncDriver.shared.request()
```

In the existing `onChange(of: scenePhase)`, in the `.active` branch, after
the session restore, add:

```swift
FocusSyncDriver.shared.request()
```

In `FocusSessionModel`, directly after the
`try FocusStore(context:).record(...)` call succeeds, add:

```swift
FocusSyncDriver.shared.request()
```

On an account switch, the driver's `session` closure already reads the current
account's Keychain slot, and its `context` is the scene's store for that
account. If `RootView` swaps the model container on a switch, call
`FocusSyncDriver.shared.reset()` there. `reset()` sets `sync = nil` and stops
the monitor; add it to the driver. Then `attach` the new context.

- [ ] **Step 3: Build, then check on the simulator**

Run:

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' -quiet
```

Expected: no `error:`.

Then, against the dev project with the migration applied:
1. Sign in and run a one-minute focus session.
2. In the Supabase table editor, confirm `focus_sessions` has one row with
   your `user_id`.
3. Delete the app, reinstall it, and sign in again.
4. Today's "min today" should show the session again, pulled from the server.

- [ ] **Step 4: Commit**

```bash
git add LIfeOS/App/FocusSyncDriver.swift LIfeOS/App/RootView.swift LIfeOS/Features/Focus/ViewModel/FocusSessionModel.swift LIfeOS.xcodeproj/project.pbxproj
git commit -m "feat(focus): sync sessions on launch, on save and when the network returns"
```

### Task 10: Clear data and account deletion include focus sessions

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/AccountData.swift`
- Modify: `LifeOSKit/Tests/PersistenceTests/AccountDataTests.swift:46`
- Modify: `supabase/functions/_shared/account.ts:8-9`
- Modify: `supabase/functions/account-data/index.ts:4-9`
- Modify: `supabase/functions/_shared/account_test.ts` (the server category list, if it is asserted there)
- Modify: `LIfeOS/Features/Settings/View/ClearDataScreen.swift` (`whereItLives`)

- [ ] **Step 1: Update the failing expectation first**

In `AccountDataTests.swift`, change line 46 to:

```swift
        #expect(DataCategory.allCases.filter(\.hasServerRows) == [.notes, .health, .focus, .messages])
```

Add:

```swift
    @Test @MainActor func erasingFocusRemovesSessions() throws {
        let container = try ModelContainer(for: FocusSessionRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        try FocusStore(context: context).record(mood: "focus", source: "soundscape", startedAt: .now,
            endedAt: .now, focusedSeconds: 60, blocksCompleted: 1, projectTaskID: nil)
        try LocalDataEraser(context: context, defaults: UserDefaults(suiteName: "erase-focus")!).erase([.focus])
        #expect(try context.fetchCount(FetchDescriptor<FocusSessionRecord>()) == 0)
    }
```

Run: `cd LifeOSKit && swift test --filter AccountDataTests`
Expected: FAIL, "type 'DataCategory' has no member 'focus'".

- [ ] **Step 2: Implement**

In `AccountData.swift`:
- `case notes, habits, health, focus, money, chats, messages`
- the title: `case .focus: "Focus sessions"`
- `hasServerRows`: `[.notes, .health, .focus, .messages].contains(self)`
- `LocalDataEraser`: `case .focus: try context.delete(model: FocusSessionRecord.self)`

In `ClearDataScreen.whereItLives`:

```swift
        case .focus: "On this phone and on our server, for LifeOS and LifeOS Focus."
```

In `account.ts`:

```ts
export type ServerCategory = "notes" | "health" | "focus" | "messages";
const SERVER: readonly string[] = ["notes", "health", "focus", "messages"];
```

In `account-data/index.ts`, `TABLES`, add:

```ts
  focus: ["focus_sessions"],
```

Account deletion is covered by `on delete cascade` from `auth.users`. Check
that `account-purge` deletes the auth user rather than individual tables, with
`grep -n "deleteUser\|admin" supabase/functions/account-purge/index.ts`. If
it deletes tables one by one, add `focus_sessions` to its list.

- [ ] **Step 3: Run the tests and confirm they pass**

Run: `cd LifeOSKit && swift test --filter AccountDataTests`
Then run: `deno test supabase/functions/_shared/account_test.ts`
Expected: all pass.

- [ ] **Step 4: Commit and open the slice 2 PR**

```bash
git add LifeOSKit/Sources/Persistence/AccountData.swift LifeOSKit/Tests/PersistenceTests/AccountDataTests.swift supabase/functions LIfeOS/Features/Settings/View/ClearDataScreen.swift
git commit -m "feat(focus): clear focus sessions from Clear data and on deletion"
```

Push `feat/focus-sync`. Open a PR titled
"feat(focus): sync focus sessions through Supabase". The owner steps in the
body are `supabase db push` and `supabase functions deploy account-data`.
Don't merge it.

---

## After this plan

Slices 3 to 5 (the Focus app targets, the Live Activity and Shortcuts, and
the LifeOS link-outs) get their own plan once these two slices are merged, so
it is written against the real `AccountUI` and `FocusSync` APIs. Before
slice 3, Shiv has to complete the App Store Connect and App ID owner steps
listed in the spec.

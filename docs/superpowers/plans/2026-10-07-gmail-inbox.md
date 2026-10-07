# Gmail inbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect Gmail (test users), read the last two days of important Primary mail on the phone, sort it into NEEDS YOU and FYI with Apple's on-device model, and show it as an Inbox module on Today.

**Architecture:** `Integrations` holds the tested pieces: `GoogleOAuth` (authorize URL, callback, token request bodies, expiry), `GoogleTokenStore` (Keychain per account), `GmailAPI` (URLs and decoding into `MailItem`), `MailVerdictCache`, `InboxDigest` (what Today shows) and `MailFallback` (snippet trimming). The app holds `GmailConnectionViewModel` (sign-in, refresh, disconnect, the mail fetch), `MailSorter` (FoundationModels guided generation), the Connections card and the Today `inbox` module. No server.

**Tech Stack:** AuthenticationServices, FoundationModels (`SystemLanguageModel`, `@Generable`), Keychain, Swift Testing, XCUITest.

**Spec:** `docs/superpowers/specs/2026-10-07-gmail-inbox-design.md`

## Global Constraints

- Scopes exactly `openid email https://www.googleapis.com/auth/gmail.readonly`; PKCE S256; `access_type=offline`, `prompt=consent`; redirect `<reversed client id>:/oauth2redirect`.
- Query exactly `in:inbox category:primary is:important newer_than:2d`, `maxResults=25`; metadata headers From, Subject, Date only; bodies never fetched.
- Refresh when the access token is within 60 s of expiry; `invalid_grant` means reconnect.
- Fetch at most every 10 minutes when Today appears; pull to refresh forces.
- Verdict cache key `gmail.verdicts`, at most 200 entries; snippet fallback ≤ 90 characters cut on a word.
- Digest: NEEDS YOU first, then FYI, newest first within each, at most five, NEEDS YOU never cut for FYI.
- Copy: `Gmail`, `Connected as <email>`, `INBOX`, `<n> need you`, `1 needs you`, `Nothing needs you`, `NEEDS YOU`, `FYI`, `Gmail needs reconnecting`, `No important mail in the last two days.`, `Connect Gmail`.
- Nothing about mail leaves the phone. Fonts from `LifeOSType`; typography reports nothing new. `LifeOSKit` builds for macOS.
- Commits conventional, no em dashes, no attribution. Worktree `.claude/worktrees/gmail-inbox` on `feat/gmail-inbox`; simulator `B192EA65-BAA2-4814-A298-94A2F0C8FC87`; DerivedData `~/Library/Developer/Xcode/DerivedData/gmail-inbox`.

## Review Focus

1. A token close to expiry must be refreshed before a call, and a refused refresh must read as reconnect, never as an empty inbox: `GoogleOAuthTests.expiryAndRefusal`.
2. A `From` header with a quoted name, an encoded name, or a bare address must give a readable sender: `GmailAPITests.senders`.
3. When three mails need you and four are FYI, Today shows three NEEDS YOU and two FYI; with six NEEDS YOU, all five slots are NEEDS YOU: `InboxDigestTests.capAndOrder`.
4. A snippet with HTML entities (`&#39;`, `&amp;`) must read as text: `MailFallbackTests.entities`.
5. A message classified once is never sent to the model again: `MailVerdictCacheTests.remembersAndCaps`.

---

### Task 0: Baselines and the plan commit.

### Task 1: The tested pieces (`Integrations`)

**Files:** Create `GoogleOAuth.swift`, `GoogleTokenStore.swift`, `GmailAPI.swift`, `InboxDigest.swift` in `LifeOSKit/Sources/Integrations`; tests `GoogleOAuthTests.swift`, `GmailAPITests.swift`, `InboxDigestTests.swift` (with `MailFallbackTests`, `MailVerdictCacheTests`).

**Produces:**
- `GoogleOAuth.session(clientID:redirectURI:state:verifier:) -> (url, state, verifier)`; `code(from:expectedState:) throws -> String` (`GoogleAuthError.denied/stateMismatch/missingCode`); `tokenRequestBody(code:verifier:clientID:redirectURI:) -> Data` and `refreshRequestBody(refreshToken:clientID:) -> Data` (form-encoded); `static func reversed(clientID:) -> String` (`123-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.123-abc`); `GoogleTokenResponse` decoding `access_token`, `refresh_token?`, `expires_in`, `id_token?`; `email(fromIDToken:) -> String?` (JWT payload `email`); `GoogleRefreshOutcome { case refreshed(...), reconnect, unavailable }` from a status and body (`invalid_grant` → reconnect).
- `GoogleConnection: Codable { accessToken, refreshToken, expiresAt, email }` with `needsRefresh(now:) -> Bool` (within 60 s); `GoogleTokenStoring` + `KeychainGoogleTokenStore` (service `ai.lifeos.google`, per account, pending auth item) + `InMemoryGoogleTokenStore`.
- `GmailAPI.listURL() -> URL`, `messageURL(id:) -> URL`; `GmailAPI.messageIDs(from: Data) -> [String]`; `GmailAPI.item(from: Data) -> MailItem?`; `MailItem: Codable, Equatable { id, threadId, sender, senderEmail, subject, snippet, receivedAt, isUnread }`.
- `MailBucket: String, Codable { needsYou, fyi }`; `MailVerdict: Codable, Equatable { bucket, summary }`; `MailFallback.verdict(for: MailItem) -> MailVerdict` (FYI, snippet cleaned of HTML entities and cut to ≤ 90 on a word with `…`); `MailVerdictCache(defaults:)` with `verdict(for id:)`, `store(_:for:)` (keeps the newest 200); `InboxDigest.make(items:verdicts:) -> InboxDigest { needsYou: [Row], fyi: [Row], needsYouCount: Int }` with `Row { item, summary }`.

- [ ] Tests first for every line of the Review Focus plus: the authorize URL's parameters; the reversed client id; token response decoding; email from a sample id token; list and message decoding from recorded Gmail JSON (`internalDate` in ms as a string, `UNREAD` in `labelIds`, headers by name case-insensitively). Watch them fail; implement; pass; commit `feat(integrations): Gmail's pieces, tested`.

### Task 2: Connecting and fetching (app)

**Files:** Modify `AppConfig.swift` (`googleClientID`, `isGoogleConfigured`), `Config/App-Info.plist` (`GoogleClientID` = `$(GOOGLE_CLIENT_ID)`; `LSApplicationQueriesSchemes` with `googlegmail`), `Secrets.example.xcconfig`, `IntegrationContainer.swift` (owns `gmail`), `RootView.swift` (`.environment(\.gmail, …)`), `ConnectionsSettingsScreen.swift` (the card); Create `LIfeOS/Features/Settings/ViewModel/GmailConnectionViewModel.swift`, `LIfeOS/Features/Today/Model/MailSorter.swift`.

- [ ] `GmailConnectionViewModel`: states like GitHub's (`unconfigured`, `disconnected`, `connecting`, `connected(email)`, `failed`), `needsReconnect`, `changeCount`; `connect()` through `ASWebAuthenticationSession(callbackURLScheme: GoogleOAuth.reversed(...))`; `handle(_:)` exchanges at `https://oauth2.googleapis.com/token` (no secret), reads the email from the id token, saves the connection; `validToken() async -> String?` refreshing when `needsRefresh`; `disconnect()` revokes (best effort) and clears; `inbox(force:) async -> InboxState` (`.notConnected`, `.reconnect`, `.ready(InboxDigest, fetchedAt)`) fetching the list then each message's metadata (concurrently, at most 6 at a time), sorting new ids through `MailSorter`, caching the last digest for 10 minutes.
- [ ] `MailSorter`: when `SystemLanguageModel.default.availability == .available`, one `LanguageModelSession` per batch, `respond(to:generating: MailVerdictModel.self)` per message with only sender, subject, snippet; any failure or unavailability → `MailFallback.verdict`.
- [ ] Build; commit `feat(gmail): connect Gmail and read the important mail on the phone`.

### Task 3: The Today module

**Files:** `LifeOSKit/Sources/DesignSystem/TodayLayout.swift` (`inbox` module, hidden), its tests; `TodayModules.swift` (the module); `TodayScreen.swift` (load the inbox when the module is shown, offer it once on connect via `TodayLayoutStore.offerOnce(_:key:)`); `TodayDesignPreview.swift` (`today-inbox` with a stub source); `LIfeOSUITests/InboxUITests.swift`.

- [ ] Layout test first (a saved layout keeps `inbox` hidden; title `Inbox`). Module rows, groups, states per the spec; a tap opens `googlegmail:///cv=<threadId>` or the web URL. UI test on `today-inbox`: NEEDS YOU above FYI, the count line, and a row is a button. Captures light and dark. Commit `feat(today): the important mail, sorted, on Today`.

### Task 4: Verification, review, finishing

- [ ] Full suites; fresh review on the most capable model; one fix pass; finishing options.

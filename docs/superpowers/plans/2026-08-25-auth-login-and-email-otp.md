# Login Door, Email OTP, and the Twilio Failure Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a returning user a way to sign in, replace the undeliverable email magic link with a six-digit code, and split the one SMS failure bucket into causes a user can act on.

**Architecture:** With OTP there is no login screen, only a login door — signing in and signing up run the identical `identity → code` machinery and are told apart only *after* the code is accepted, by a new `AuthSession.hasProfile` flag decoded from `user_metadata.first_name`. `AuthMode` drives copy and nothing else. The magic link goes away by deletion, not replacement: `sendCode`/`verify` already implement email OTP, and the real blocker is server-side SMTP configuration in `config.toml`. Twilio's `sms_unverified` bucket splits into four named kinds carried verbatim from the Edge Function to the Swift error mapper.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, `@Observable`, Swift Testing (`import Testing`, `@Suite`/`@Test`/`#expect`), Deno (Supabase Edge Functions), Supabase CLI.

**Spec:** `docs/superpowers/specs/2026-08-25-auth-login-and-email-otp-design.md`

## Global Constraints

- **Work in the worktree** `/Users/shivvyas/LIfeOS/.claude/worktrees/auth-login-email-otp` on branch `feat/auth-login-and-email-otp`. Never commit to `main`. Other sessions share the primary checkout and move `HEAD` there.
- **There is no test target for the `LIfeOS` app.** Only `LifeOSKit` has tests. Everything in `LIfeOS/Features/...` and `LIfeOS/App/...` is verified by `xcodebuild` plus the manual simulator pass in Task 7 — do not invent an app test target to satisfy a step.
- **Run Swift tests with:** `swift test --package-path LifeOSKit` (add `--filter` to narrow).
- **Build the app with:** `xcodebuild -project ./LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build`, run from the worktree root. **Every path in this plan is relative to the worktree.** Never pass an absolute path under `/Users/shivvyas/LIfeOS/` that is not inside `.claude/worktrees/auth-login-email-otp/`, and never edit, build, or test the primary checkout at `/Users/shivvyas/LIfeOS`. It sits at a different commit, other sessions share it, and edits made there both break its build and are invisible to this branch. An earlier run of this plan did exactly that and left the primary checkout uncompilable.
- **Run Deno tests with:** `deno test supabase/functions/_shared/otp_twilio_test.ts`
- **Test naming follows the existing codebase:** full sentences, e.g. `@Test func anEmptyGateway502IsStillASentence()`. See `LifeOSKit/Tests/IntegrationsTests/AuthErrorMappingTests.swift`.
- **Commit style:** lowercase `type(scope): imperative summary`. No `Co-Authored-By` trailer. No em dashes in commit messages.
- **Never add an endpoint that reports whether a phone or email is registered.** That is user enumeration, and the spec rejects it explicitly. `create_user: true` stays set in both auth modes.
- **Error copy names the cause, never the status code.** `AuthError.readable` must never fall through to `Something went wrong (502)` for a known Twilio kind.
- **Cost ceiling:** backend and AI stay under roughly $2/user/month. Resend's free tier (3,000 emails/month) is what keeps email OTP inside it; SMS at ~$0.05 a send is what pushes phone to second place.

---

## File Structure

| File | Responsibility |
|---|---|
| `supabase/functions/_shared/otp_twilio.ts` | `classifyTwilioFailure` maps a Twilio code to a kind; `SEND_FAILURE_STATUS` maps a kind to an HTTP status |
| `supabase/functions/_shared/otp_twilio_test.ts` | **New.** First Deno test in the repo; covers `classifyTwilioFailure` |
| `supabase/functions/otp-start/index.ts` | Forwards the kind verbatim instead of an if-chain that drops unknown kinds |
| `supabase/config.toml` | Enables Resend SMTP, both email templates, and raises the email rate limit |
| `LifeOSKit/Sources/Integrations/SupabaseAuth.swift` | `AuthError.fromHTTP` copy for each kind; `AuthSession.hasProfile`; magic-link code deleted |
| `LifeOSKit/Sources/Integrations/SessionRefresh.swift` | `carryingForward` preserves `hasProfile` |
| `LifeOSKit/Tests/IntegrationsTests/AuthErrorMappingTests.swift` | Cases for the four split kinds and the legacy alias |
| `LifeOSKit/Tests/IntegrationsTests/AuthSessionProfileTests.swift` | **New.** `hasProfile` decoding, keychain back-compat, `carryingForward` |
| `LIfeOS/Features/Onboarding/Model/OnboardingModels.swift` | `OnboardingStep` loses `.linkSent`, gains `.signedIn`; `AuthMode`; `SignupDraft` defaults to email |
| `LIfeOS/Features/Onboarding/ViewModel/OnboardingViewModel.swift` | `mode`, `beginSignIn`, mode-driven copy, the post-verify branch, `useEmailInstead` |
| `LIfeOS/Features/Onboarding/View/IntroScreen.swift` | The second door: "I already have an account" |
| `LIfeOS/Features/Onboarding/View/SignupScreens.swift` | `IdentityScreen` mode copy, footer switch, email-first picker, the escape button; `LinkSentScreen` deleted |
| `LIfeOS/Features/Onboarding/View/ConnectionsScreen.swift` | `OnboardingFlow` routes `.signedIn` and calls `onFinish` from `.onChange` |
| `LIfeOS/App/AppShell.swift` | The `auth-callback` branch of `onOpenURL` deleted |

---

## Task 1: Split the Twilio failure bucket

**Files:**
- Modify: `supabase/functions/_shared/otp_twilio.ts`
- Modify: `supabase/functions/otp-start/index.ts`
- Modify: `LifeOSKit/Sources/Integrations/SupabaseAuth.swift` (`AuthError.fromHTTP`)
- Create: `supabase/functions/_shared/otp_twilio_test.ts`
- Test: `LifeOSKit/Tests/IntegrationsTests/AuthErrorMappingTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: the error kind strings `"sms_trial_unverified"`, `"sms_opted_out"`, `"sms_unregistered_campaign"`, `"sms_blocked"`. Task 6 keys the "Use email instead" escape off *any* phone-channel send failure, not off these strings, so it does not need to import them. Exported from `otp_twilio.ts`: `classifyTwilioFailure(status: number, body: string): string` (unchanged signature) and the new `SEND_FAILURE_STATUS: Record<string, number>`.

- [ ] **Step 1: Install Deno if it is missing**

There is no Deno test in the repo yet and `deno` is not on this machine. Check, and install only if absent:

```bash
command -v deno || brew install deno
deno --version
```

- [ ] **Step 2: Write the failing Deno test**

Create `supabase/functions/_shared/otp_twilio_test.ts`:

```ts
import { assertEquals } from "jsr:@std/assert@1";
import { SEND_FAILURE_STATUS, classifyTwilioFailure } from "./otp_twilio.ts";

// 21608 and 21610 shared one bucket whose copy explained neither. One is a
// developer misconfiguration that cannot happen on a paid account; the other is
// a user action with a user remedy.
Deno.test("a trial account sending to an unverified number is its own kind", () => {
  assertEquals(
    classifyTwilioFailure(400, JSON.stringify({ code: 21608 })),
    "sms_trial_unverified",
  );
});

Deno.test("an opted-out recipient is its own kind", () => {
  assertEquals(
    classifyTwilioFailure(400, JSON.stringify({ code: 21610 })),
    "sms_opted_out",
  );
});

Deno.test("an unregistered A2P campaign is named rather than generic", () => {
  assertEquals(
    classifyTwilioFailure(400, JSON.stringify({ code: 30034 })),
    "sms_unregistered_campaign",
  );
});

Deno.test("a blocked Verify delivery is named rather than generic", () => {
  assertEquals(
    classifyTwilioFailure(400, JSON.stringify({ code: 60410 })),
    "sms_blocked",
  );
});

Deno.test("a 429 is rate limiting whatever the body says", () => {
  assertEquals(classifyTwilioFailure(429, "{}"), "rate_limited");
});

Deno.test("an HTML body falls back to a generic send failure", () => {
  assertEquals(
    classifyTwilioFailure(500, "<html>Bad Gateway</html>"),
    "send_failed",
  );
});

Deno.test("every kind the classifier can return has a status", () => {
  const kinds = [
    "rate_limited",
    "sms_region",
    "sms_trial_unverified",
    "sms_opted_out",
    "sms_unregistered_campaign",
    "sms_blocked",
    "invalid_phone",
    "server_not_configured",
  ];
  for (const kind of kinds) {
    assertEquals(typeof SEND_FAILURE_STATUS[kind], "number", kind);
  }
});
```

- [ ] **Step 3: Run the Deno test to verify it fails**

Run: `deno test supabase/functions/_shared/otp_twilio_test.ts`
Expected: FAIL. `SEND_FAILURE_STATUS` does not exist, and the 21608/21610/30034/60410 cases return `sms_unverified` or `send_failed`.

- [ ] **Step 4: Split the classifier and add the status map**

In `supabase/functions/_shared/otp_twilio.ts`, replace the body of `classifyTwilioFailure`'s code chain and add the exported map above it:

```ts
/// The HTTP status each failure kind is reported with. A map rather than an
/// if-chain in the function, so a new kind cannot be added in one place and
/// silently dropped to `send_failed` in the other.
export const SEND_FAILURE_STATUS: Record<string, number> = {
  rate_limited: 429,
  invalid_phone: 400,
  server_not_configured: 500,
  sms_region: 502,
  sms_trial_unverified: 502,
  sms_opted_out: 502,
  sms_unregistered_campaign: 502,
  sms_blocked: 502,
  send_failed: 502,
};

export function classifyTwilioFailure(status: number, body: string): string {
  let code: number | undefined;
  try {
    const parsed = JSON.parse(body) as { code?: number };
    if (typeof parsed.code === "number") code = parsed.code;
  } catch {
    // Twilio sometimes returns HTML. Treat it as a generic send failure.
  }

  if (status === 429 || code === 60203 || code === 20429) return "rate_limited";
  if (code === 21408 || code === 21612) return "sms_region";
  // 21608 cannot fire on a paid account, so it is a credentials problem the
  // user cannot fix. 21610 is per number and the user can undo it themselves.
  if (code === 21608) return "sms_trial_unverified";
  if (code === 21610) return "sms_opted_out";
  if (code === 30034) return "sms_unregistered_campaign";
  if (code === 60410) return "sms_blocked";
  if (code === 21211 || code === 21614 || code === 60200) return "invalid_phone";
  if (code === 20003 || code === 20404) return "server_not_configured";
  return "send_failed";
}
```

- [ ] **Step 5: Run the Deno test to verify it passes**

Run: `deno test supabase/functions/_shared/otp_twilio_test.ts`
Expected: PASS, 7 tests.

- [ ] **Step 6: Forward the kind verbatim from otp-start**

In `supabase/functions/otp-start/index.ts`, change the import line to bring in the map:

```ts
import { SEND_FAILURE_STATUS, twilioStart } from "../_shared/otp_twilio.ts";
```

and replace the whole `if (!sent.ok) { ... }` block with:

```ts
  if (!sent.ok) {
    return json({ error: sent.kind }, SEND_FAILURE_STATUS[sent.kind] ?? 502);
  }
```

- [ ] **Step 7: Type-check the Edge Function**

Run: `deno check supabase/functions/otp-start/index.ts`
Expected: no errors.

- [ ] **Step 8: Write the failing Swift tests**

Append these to the `AuthErrorMappingTests` suite in `LifeOSKit/Tests/IntegrationsTests/AuthErrorMappingTests.swift`, and **replace** the existing `anUnverifiedTwilioTrialNumberIsNamedAsSuch` test, whose `sms_unverified` copy this task supersedes:

```swift
    /// The deployed Edge Function is upgraded separately from the app, so an
    /// old server still sending `sms_unverified` must not regress to a bare
    /// status code in a new build.
    @Test func theLegacyUnverifiedKindStillReads() async {
        let auth = makeAuth()
        OTPStubURLProtocol.replies = [
            .status(502, #"{"error":"sms_unverified"}"#)
        ]

        do {
            try await auth.sendCode(to: "+14155552671", channel: .phone)
            Issue.record("expected sendCode to throw")
        } catch let error as AuthError {
            #expect(error.readable == "We can't text this number yet. The SMS account is still in trial mode")
        } catch {
            Issue.record("expected AuthError, got \(error)")
        }
    }

    @Test func aTrialAccountFailureBlamesTheAccountNotTheNumber() async {
        let auth = makeAuth()
        OTPStubURLProtocol.replies = [
            .status(502, #"{"error":"sms_trial_unverified"}"#)
        ]

        do {
            try await auth.sendCode(to: "+14155552671", channel: .phone)
            Issue.record("expected sendCode to throw")
        } catch let error as AuthError {
            #expect(error.readable == "We can't text this number yet. The SMS account is still in trial mode")
        } catch {
            Issue.record("expected AuthError, got \(error)")
        }
    }

    @Test func anOptedOutNumberIsGivenTheRemedy() async {
        let auth = makeAuth()
        OTPStubURLProtocol.replies = [
            .status(502, #"{"error":"sms_opted_out"}"#)
        ]

        do {
            try await auth.sendCode(to: "+14155552671", channel: .phone)
            Issue.record("expected sendCode to throw")
        } catch let error as AuthError {
            #expect(error.readable == "That number opted out of our texts. Text START to our number to opt back in")
        } catch {
            Issue.record("expected AuthError, got \(error)")
        }
    }

    @Test func anUnregisteredCampaignIsNamedRatherThanGeneric() async {
        let auth = makeAuth()
        OTPStubURLProtocol.replies = [
            .status(502, #"{"error":"sms_unregistered_campaign"}"#)
        ]

        do {
            try await auth.sendCode(to: "+14155552671", channel: .phone)
            Issue.record("expected sendCode to throw")
        } catch let error as AuthError {
            #expect(error.readable == "Our SMS sender isn't registered with that carrier yet")
        } catch {
            Issue.record("expected AuthError, got \(error)")
        }
    }

    @Test func aCarrierBlockIsNamedRatherThanGeneric() async {
        let auth = makeAuth()
        OTPStubURLProtocol.replies = [
            .status(502, #"{"error":"sms_blocked"}"#)
        ]

        do {
            try await auth.sendCode(to: "+14155552671", channel: .phone)
            Issue.record("expected sendCode to throw")
        } catch let error as AuthError {
            #expect(error.readable == "The carrier blocked that text")
        } catch {
            Issue.record("expected AuthError, got \(error)")
        }
    }
```

- [ ] **Step 9: Run the Swift tests to verify they fail**

Run: `swift test --package-path LifeOSKit --filter AuthErrorMappingTests`
Expected: FAIL. The four new kinds fall through to `Something went wrong (502)`, and `sms_unverified` still reads "That number isn't verified for SMS yet. Add it in Twilio, then try again".

- [ ] **Step 10: Rewrite the Swift error copy**

In `LifeOSKit/Sources/Integrations/SupabaseAuth.swift`, replace the single `case "sms_unverified":` arm inside `AuthError.fromHTTP` with:

```swift
        // Twilio 21608. Cannot happen on a paid account, so the reader can do
        // nothing about it and the copy must not send them off to fix a number
        // that is not the problem.
        case "sms_trial_unverified", "sms_unverified":
            return .server(
                status: 502,
                message: "We can't text this number yet. The SMS account is still in trial mode"
            )
        // Twilio 21610. Per number, and the user is the only one who can undo it.
        case "sms_opted_out":
            return .server(
                status: 502,
                message: "That number opted out of our texts. Text START to our number to opt back in"
            )
        // Twilio 30034.
        case "sms_unregistered_campaign":
            return .server(
                status: 502,
                message: "Our SMS sender isn't registered with that carrier yet"
            )
        // Twilio 60410.
        case "sms_blocked":
            return .server(status: 502, message: "The carrier blocked that text")
```

`"sms_unverified"` shares the trial arm on purpose: the Edge Function deploys separately from the app, so a new build talking to an old function must still read as a sentence.

- [ ] **Step 11: Run the Swift tests to verify they pass**

Run: `swift test --package-path LifeOSKit --filter AuthErrorMappingTests`
Expected: PASS, 8 tests.

- [ ] **Step 12: Commit**

```bash
git add supabase/functions/_shared/otp_twilio.ts \
        supabase/functions/_shared/otp_twilio_test.ts \
        supabase/functions/otp-start/index.ts \
        LifeOSKit/Sources/Integrations/SupabaseAuth.swift \
        LifeOSKit/Tests/IntegrationsTests/AuthErrorMappingTests.swift
git commit -m "fix(otp): split the Twilio failure bucket into causes a user can act on"
```

---

## Task 2: Replace the email magic link with a six-digit code

**Files:**
- Modify: `LifeOSKit/Sources/Integrations/SupabaseAuth.swift` (delete `sendMagicLink` and the whole `public extension AuthSession` block)
- Modify: `LIfeOS/Features/Onboarding/Model/OnboardingModels.swift` (delete `.linkSent`)
- Modify: `LIfeOS/Features/Onboarding/ViewModel/OnboardingViewModel.swift`
- Modify: `LIfeOS/Features/Onboarding/View/SignupScreens.swift` (delete `LinkSentScreen`, use a literal button title)
- Modify: `LIfeOS/Features/Onboarding/View/ConnectionsScreen.swift` (`OnboardingFlow`)
- Modify: `LIfeOS/App/AppShell.swift`
- Modify: `supabase/config.toml`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `OnboardingStep` no longer has `.linkSent` — Task 5 adds `.signedIn` to the same enum. `OnboardingViewModel.identitySubtitle` survives as a computed property and Task 4 leaves it alone. `sendButtonTitle` is **gone**; `IdentityScreen` uses the literal `"Send code"`.

- [ ] **Step 1: Delete the magic-link code from SupabaseAuth**

In `LifeOSKit/Sources/Integrations/SupabaseAuth.swift`:

1. Delete the whole `sendMagicLink` function together with its doc comment (the block beginning `/// Sends a magic link that returns to `redirectTo`.`).
2. Delete the entire `public extension AuthSession { ... }` block — both `init?(callback url: URL)` and `static func errorDescription(in url: URL) -> String?`. It starts at `public extension AuthSession {` and ends at the closing brace before `public enum AuthError`.

Leave `sendCode` and `verify` untouched; they already implement email OTP.

- [ ] **Step 2: Drop `.linkSent` from the step enum**

In `LIfeOS/Features/Onboarding/Model/OnboardingModels.swift`, delete this line from `OnboardingStep`:

```swift
    case linkSent            // magic link (email)
```

- [ ] **Step 3: Strip the magic link out of the view model**

In `LIfeOS/Features/Onboarding/ViewModel/OnboardingViewModel.swift`:

1. Delete the `emailUsesMagicLink` property and its three-line doc comment.
2. Delete the whole `sendButtonTitle` computed property.
3. Replace `identitySubtitle` with:

```swift
    var identitySubtitle: String {
        draft.channel == .phone
            ? "We'll text you a six-digit code."
            : "We'll email you a six-digit code."
    }
```

4. In `back()`, change `case .code, .linkSent:  step = .identity` to:

```swift
        case .code:             step = .identity
```

5. In `sendCode()`, replace the whole `if draft.channel == .email && emailUsesMagicLink { ... } else { ... }` block with the else branch alone:

```swift
            try await auth.sendCode(to: draft.destination, channel: draft.channel)
            draft.code = ""
            step = .code
```

6. Delete `static let authCallback` and its doc comment, and delete the entire `handleAuthCallback(_ url: URL)` function and its doc comment.

- [ ] **Step 4: Delete LinkSentScreen and use a literal button title**

In `LIfeOS/Features/Onboarding/View/SignupScreens.swift`:

1. Delete the whole `struct LinkSentScreen: View { ... }` at the end of the file, together with its doc comment.
2. In `IdentityScreen`, change `PrimaryButton(model.sendButtonTitle, isLoading: model.isBusy) {` to:

```swift
                PrimaryButton("Send code", isLoading: model.isBusy) {
```

- [ ] **Step 5: Drop the route**

In `LIfeOS/Features/Onboarding/View/ConnectionsScreen.swift`, delete this line from `OnboardingFlow`'s switch:

```swift
            case .linkSent:    LinkSentScreen(model: model)
```

- [ ] **Step 6: Drop the callback branch from the shell**

In `LIfeOS/App/AppShell.swift`, replace the body of `.onOpenURL` with:

```swift
        .onOpenURL { url in
            // Logged at the door: if nothing appears here, the redirect never
            // reached the app at all and the problem is upstream of our code.
            // Only Whoop uses the scheme now that email is a code, not a link.
            shellLog.info("opened url host=\(url.host ?? "?", privacy: .public)")
            whoop.handleCallback(url)
        }
```

Leave `lifeos://auth-callback` in `additional_redirect_urls` in `config.toml`. It is unused and harmless, and removing it would disturb the Whoop callback's neighbour in the same change.

- [ ] **Step 7: Configure SMTP and the templates**

In `supabase/config.toml`:

1. Raise the email rate limit. Replace `email_sent = 2` with:

```toml
# Raised from 2, which was a limit of Supabase's built-in sender. Resend has no
# such cap; its free tier is 3,000 emails a month.
email_sent = 30
```

2. Replace the commented-out SendGrid block (from `# Use a production-ready SMTP server` through `# sender_name = "Admin"`) with:

```toml
# The built-in sender delivers only to project team members and caps at two
# emails an hour, which is why email signup never worked for anyone else.
[auth.email.smtp]
enabled = true
host = "smtp.resend.com"
port = 465
user = "resend"
pass = "env(RESEND_API_KEY)"
sender_name = "Life OS"
```

3. Replace the parked template block (the comment beginning `# Supabase's stock templates send a magic LINK.` through the commented `# content_path = "./supabase/templates/confirmation.html"`) with:

```toml
# Supabase's stock templates send a magic LINK. A link cannot be typed into an
# app, so signup dead-ended at "confirm your email address" with no code to
# enter. Including {{ .Token }} is what makes Supabase send a six-digit OTP.
# Both are needed: GoTrue sends confirmation.html to an address it has not seen
# and magic_link.html to one it has.
[auth.email.template.magic_link]
subject = "Your Life OS code"
content_path = "./supabase/templates/magic_link.html"

[auth.email.template.confirmation]
subject = "Confirm your email"
content_path = "./supabase/templates/confirmation.html"
```

- [ ] **Step 8: Verify no magic-link reference survives**

Run:

```bash
grep -rn "emailUsesMagicLink\|LinkSentScreen\|sendMagicLink\|linkSent\|handleAuthCallback\|sendButtonTitle\|errorDescription(in\|AuthSession(callback" \
  --include="*.swift" --include="*.toml" . | grep -v "^./.claude/worktrees"
```

Expected: **only** the `additional_redirect_urls` line in `supabase/config.toml`, which mentions `lifeos://auth-callback` and is deliberately left. No Swift hits at all.

- [ ] **Step 9: Build and test**

Run: `swift test --package-path LifeOSKit`
Expected: PASS, whole suite.

Run: `xcodebuild -project ./LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 10: Commit**

```bash
git add LifeOSKit/Sources/Integrations/SupabaseAuth.swift \
        LIfeOS/Features/Onboarding LIfeOS/App/AppShell.swift \
        supabase/config.toml
git commit -m "feat(auth): send an email code instead of a magic link"
```

---

## Task 3: Teach a session whether it already has a profile

**Files:**
- Modify: `LifeOSKit/Sources/Integrations/SupabaseAuth.swift` (`AuthSession`, `SupabaseAuth.decode`)
- Modify: `LifeOSKit/Sources/Integrations/SessionRefresh.swift` (`carryingForward`)
- Create: `LifeOSKit/Tests/IntegrationsTests/AuthSessionProfileTests.swift`

**Interfaces:**
- Consumes: nothing from Tasks 1–2.
- Produces: `AuthSession.hasProfile: Bool`, and `AuthSession.init(accessToken:refreshToken:expiresAt:userID:phone:email:hasProfile:)` where `hasProfile` **defaults to `false`** so every existing call site keeps compiling. Task 5 reads `session.hasProfile` to pick the step after verify.

- [ ] **Step 1: Write the failing tests**

Create `LifeOSKit/Tests/IntegrationsTests/AuthSessionProfileTests.swift`:

```swift
import Testing
import Foundation
@testable import Integrations

/// This suite's own stub, for the same reason `AuthErrorMappingTests` keeps one
/// apart from the Whoop suite: the reply queue is a static, and `.serialized`
/// orders tests only *within* a suite. Two suites sharing one queue would
/// consume each other's replies whenever they run at the same time.
final class ProfileStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var replies: [AuthStubURLProtocol.Reply] = []

    static func reset() { replies = [] }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
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

/// Whether an account has been through the profile step is the only thing that
/// tells a returning user apart from a new one, since with OTP there is no
/// password and both took the identical path to get here.
@Suite(.serialized) struct AuthSessionProfileTests {
    private func makeAuth(replies: [AuthStubURLProtocol.Reply]) -> SupabaseAuth {
        ProfileStubURLProtocol.reset()
        ProfileStubURLProtocol.replies = replies
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileStubURLProtocol.self]
        return SupabaseAuth(
            baseURL: URL(string: "https://project.supabase.co")!,
            anonKey: "anon",
            session: URLSession(configuration: configuration)
        )
    }

    @Test func aVerifiedUserWithAFirstNameHasAProfile() async throws {
        let auth = makeAuth(replies: [.ok(#"""
        {"access_token":"a","refresh_token":"r","expires_in":3600,
         "user":{"id":"u1","phone":"+14155552671","email":null,
                 "user_metadata":{"first_name":"Shiv","last_name":"Vyas"}}}
        """#)])

        let session = try await auth.verify(code: "123456", destination: "+14155552671", channel: .phone)
        #expect(session.hasProfile)
    }

    @Test func aBrandNewUserHasNoProfile() async throws {
        let auth = makeAuth(replies: [.ok(#"""
        {"access_token":"a","refresh_token":"r","expires_in":3600,
         "user":{"id":"u1","phone":"+14155552671","email":null,"user_metadata":{}}}
        """#)])

        let session = try await auth.verify(code: "123456", destination: "+14155552671", channel: .phone)
        #expect(session.hasProfile == false)
    }

    @Test func aWhitespaceOnlyFirstNameIsNotAProfile() async throws {
        let auth = makeAuth(replies: [.ok(#"""
        {"access_token":"a","refresh_token":"r","expires_in":3600,
         "user":{"id":"u1","phone":"+14155552671","email":null,
                 "user_metadata":{"first_name":"   "}}}
        """#)])

        let session = try await auth.verify(code: "123456", destination: "+14155552671", channel: .phone)
        #expect(session.hasProfile == false)
    }

    /// Sessions already in the keychain predate the key. A synthesised
    /// `init(from:)` would throw on them and sign every existing user out on
    /// upgrade, which is the worst possible cost for a new boolean.
    @Test func aStoredSessionWithoutTheKeyStillDecodes() throws {
        let blob = Data(#"""
        {"accessToken":"a","refreshToken":"r","expiresAt":800000000,
         "userID":"u1","phone":"+14155552671"}
        """#.utf8)

        let session = try JSONDecoder().decode(AuthSession.self, from: blob)
        #expect(session.accessToken == "a")
        #expect(session.userID == "u1")
        #expect(session.hasProfile == false)
    }

    /// A refresh response is allowed to be sparse. It must not erase what is
    /// already known, for the same reason `userID` and `phone` are carried.
    @Test func aRefreshDoesNotForgetTheProfile() {
        let previous = AuthSession(
            accessToken: "old", refreshToken: "r", expiresAt: .now,
            userID: "u1", phone: "+14155552671", email: nil, hasProfile: true
        )
        let refreshed = AuthSession(
            accessToken: "new", refreshToken: nil, expiresAt: .now.addingTimeInterval(3600),
            userID: "", phone: nil, email: nil, hasProfile: false
        )

        #expect(refreshed.carryingForward(previous).hasProfile)
    }

    @Test func aProfileSavedSinceTheLastRefreshSurvives() {
        let previous = AuthSession(
            accessToken: "old", refreshToken: "r", expiresAt: .now,
            userID: "u1", phone: nil, email: nil, hasProfile: false
        )
        let refreshed = AuthSession(
            accessToken: "new", refreshToken: "r2", expiresAt: .now.addingTimeInterval(3600),
            userID: "u1", phone: nil, email: nil, hasProfile: true
        )

        #expect(refreshed.carryingForward(previous).hasProfile)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path LifeOSKit --filter AuthSessionProfileTests`
Expected: FAIL to **compile** — `AuthSession` has no member `hasProfile`. That is the correct red state here.

- [ ] **Step 3: Add the field with a hand-written decoder**

In `LifeOSKit/Sources/Integrations/SupabaseAuth.swift`, replace the `AuthSession` struct's stored properties and `init` with:

```swift
public struct AuthSession: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date
    public let userID: String
    public let phone: String?
    public let email: String?
    /// Whether this account has already been through the profile step. With OTP
    /// there is no password, so this is the only thing that tells a returning
    /// user apart from a new one after the code is accepted.
    public let hasProfile: Bool

    public init(accessToken: String, refreshToken: String?, expiresAt: Date,
                userID: String, phone: String?, email: String?, hasProfile: Bool = false) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userID = userID
        self.phone = phone
        self.email = email
        self.hasProfile = hasProfile
    }

    /// Written by hand rather than synthesised: sessions already in the keychain
    /// have no `hasProfile` key, and a synthesised decoder would throw on them
    /// and sign every existing user out on upgrade. Defaulting to false is safe
    /// because the flag is only read immediately after `verify`; a restored
    /// session goes straight to the app on `hasFinishedOnboarding`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        userID = try container.decode(String.self, forKey: .userID)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        hasProfile = try container.decodeIfPresent(Bool.self, forKey: .hasProfile) ?? false
    }

    public func isExpired(now: Date = .now) -> Bool {
        expiresAt.addingTimeInterval(-60) <= now
    }
}
```

- [ ] **Step 4: Decode it off the verify response**

In `LifeOSKit/Sources/Integrations/SupabaseAuth.swift`, replace the private `decode(_:)` function with:

```swift
    private func decode(_ data: Data) throws -> AuthSession {
        struct Response: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double?
            let user: User?
            struct User: Decodable {
                let id: String
                let phone: String?
                let email: String?
                let user_metadata: Metadata?
                struct Metadata: Decodable { let first_name: String? }
            }
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let firstName = decoded.user?.user_metadata?.first_name ?? ""
        return AuthSession(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token,
            expiresAt: .now.addingTimeInterval(decoded.expires_in ?? 3_600),
            userID: decoded.user?.id ?? "",
            phone: decoded.user?.phone,
            email: decoded.user?.email,
            hasProfile: !firstName.trimmingCharacters(in: .whitespaces).isEmpty
        )
    }
```

Both channels reach this: the email path decodes `/auth/v1/verify` directly, and the phone path decodes the same body, which `mintSession` returns verbatim from its own `/auth/v1/verify` call.

- [ ] **Step 5: Carry it across a refresh**

In `LifeOSKit/Sources/Integrations/SessionRefresh.swift`, add the flag to `carryingForward`:

```swift
    func carryingForward(_ previous: AuthSession) -> AuthSession {
        AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken ?? previous.refreshToken,
            expiresAt: expiresAt,
            userID: userID.isEmpty ? previous.userID : userID,
            phone: phone ?? previous.phone,
            email: email ?? previous.email,
            hasProfile: hasProfile || previous.hasProfile
        )
    }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --package-path LifeOSKit`
Expected: PASS, whole suite. `SessionRefreshTests` must still pass — the default argument is what keeps its `AuthSession(...)` call sites valid.

- [ ] **Step 7: Commit**

```bash
git add LifeOSKit/Sources/Integrations/SupabaseAuth.swift \
        LifeOSKit/Sources/Integrations/SessionRefresh.swift \
        LifeOSKit/Tests/IntegrationsTests/AuthSessionProfileTests.swift
git commit -m "feat(auth): record whether a session already has a profile"
```

---

## Task 4: Add the second door

**Files:**
- Modify: `LIfeOS/Features/Onboarding/Model/OnboardingModels.swift` (add `AuthMode`)
- Modify: `LIfeOS/Features/Onboarding/ViewModel/OnboardingViewModel.swift`
- Modify: `LIfeOS/Features/Onboarding/View/IntroScreen.swift`
- Modify: `LIfeOS/Features/Onboarding/View/SignupScreens.swift` (`IdentityScreen`)
- Modify: `LIfeOS/Features/Onboarding/View/ConnectionsScreen.swift` (`OnboardingFlow`)

**Interfaces:**
- Consumes: `OnboardingStep` without `.linkSent` (Task 2).
- Produces: `AuthMode { case signUp, signIn }`; on `OnboardingViewModel` — `mode: AuthMode`, `beginSignIn()`, `toggleMode()`, `identityTitle: String`, `modeSwitchTitle: String`. Nothing in Task 5 or 6 depends on `mode`; it drives copy only.

- [ ] **Step 1: Add the mode**

In `LIfeOS/Features/Onboarding/Model/OnboardingModels.swift`, add below `OnboardingStep`:

```swift
/// Which door the user came through. With OTP there is no password, so signing
/// in and signing up are the same three steps; this changes copy and nothing
/// else. Picking the wrong door is harmless by design: the branch after verify
/// is what actually routes, so a "Sign in" tap with no account creates one and
/// a "Get started" tap with an account skips the profile step.
enum AuthMode: Equatable {
    case signUp
    case signIn
}
```

- [ ] **Step 2: Drive the copy from the mode**

In `LIfeOS/Features/Onboarding/ViewModel/OnboardingViewModel.swift`:

1. Add a stored property beside `step`:

```swift
    private(set) var mode: AuthMode = .signUp
```

2. Add these computed properties next to `identitySubtitle`:

```swift
    var identityTitle: String {
        mode == .signUp ? "Create your account" : "Welcome back"
    }

    var modeSwitchTitle: String {
        mode == .signUp ? "Already have an account? Sign in" : "New here? Create an account"
    }
```

3. Replace the `beginSignup()` line in the `// MARK: - Navigation` section with:

```swift
    func beginSignup() {
        mode = .signUp
        step = .identity
    }

    func beginSignIn() {
        mode = .signIn
        step = .identity
    }

    func toggleMode() {
        mode = mode == .signUp ? .signIn : .signUp
        errorMessage = nil
    }
```

4. In `signOut()`, reset the mode alongside the draft:

```swift
    func signOut() {
        store.clear()
        isSignedIn = false
        draft = SignupDraft()
        mode = .signUp
        step = .intro
    }
```

- [ ] **Step 3: Put the door on the intro**

In `LIfeOS/Features/Onboarding/View/IntroScreen.swift`:

1. Add the callback between the two existing ones, keeping declaration order stable for the synthesised init:

```swift
struct IntroScreen: View {
    let onStart: () -> Void
    var onSignIn: (() -> Void)?
    var onSkipAuth: (() -> Void)?
```

2. In the button `VStack`, add the sign-in button directly beneath `PrimaryButton`, above the skip button:

```swift
                    if let onSignIn {
                        Button("I already have an account") { onSignIn() }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(LifeOSTokens.accent)
                            .frame(height: Space.x5)
                    }
```

3. Update the preview at the bottom of the file so it still compiles:

```swift
#Preview {
    IntroScreen(onStart: {}, onSignIn: {})
}
```

- [ ] **Step 4: Wire it up in the flow**

In `LIfeOS/Features/Onboarding/View/ConnectionsScreen.swift`, change the `.intro` arm of `OnboardingFlow`'s switch to:

```swift
            case .intro:
                IntroScreen(
                    onStart: { model.beginSignup() },
                    onSignIn: { model.beginSignIn() },
                    onSkipAuth: onSkipAuth
                )
```

- [ ] **Step 5: Make the identity screen speak in both modes**

In `LIfeOS/Features/Onboarding/View/SignupScreens.swift`, inside `IdentityScreen`:

1. Change the scaffold's title from the hardcoded string:

```swift
        SignupScaffold(
            title: model.identityTitle,
            subtitle: model.identitySubtitle,
            onBack: { model.back() }
        ) {
```

2. In the `action:` block, add the mode switch under the existing buttons:

```swift
        } action: {
            VStack(spacing: Space.half) {
                PrimaryButton("Send code", isLoading: model.isBusy) {
                    Task { await model.sendCode() }
                }
                .disabled(!model.draft.canSendCode || !model.isConfigured)

                Button(model.modeSwitchTitle) { model.toggleMode() }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(LifeOSTokens.accent)
                    .frame(height: Space.x5)

                if let onSkipAuth {
                    SecondaryButton("Continue without an account") { onSkipAuth() }
                }
            }
        }
```

- [ ] **Step 6: Build**

Run: `xcodebuild -project ./LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add LIfeOS/Features/Onboarding
git commit -m "feat(auth): give a returning user a door of their own"
```

---

## Task 5: Branch to the app when the account already has a profile

**Files:**
- Modify: `LIfeOS/Features/Onboarding/Model/OnboardingModels.swift` (add `.signedIn`)
- Modify: `LIfeOS/Features/Onboarding/ViewModel/OnboardingViewModel.swift` (`back()`, `verifyCode()`)
- Modify: `LIfeOS/Features/Onboarding/View/ConnectionsScreen.swift` (`OnboardingFlow`)

**Interfaces:**
- Consumes: `AuthSession.hasProfile` (Task 3); `OnboardingStep` without `.linkSent` (Task 2).
- Produces: the terminal `OnboardingStep.signedIn`. `OnboardingFlow` calls `onFinish()` on entering it.

- [ ] **Step 1: Add the terminal step**

In `LIfeOS/Features/Onboarding/Model/OnboardingModels.swift`, add to `OnboardingStep` below `.connections`:

```swift
    case signedIn            // returning user; nothing left to ask
```

- [ ] **Step 2: Take the branch after verify**

In `LIfeOS/Features/Onboarding/ViewModel/OnboardingViewModel.swift`:

1. In `verifyCode()`, replace `step = .profile` with:

```swift
            // The only thing that separates a returning user from a new one,
            // and it is known only now. The door they came through does not
            // decide this; the account does.
            step = session.hasProfile ? .signedIn : .profile
```

2. In `back()`, add the terminal case to the switch so it stays exhaustive:

```swift
        case .signedIn:         break
```

- [ ] **Step 3: Render and finish**

In `LIfeOS/Features/Onboarding/View/ConnectionsScreen.swift`, add the `.signedIn` arm to `OnboardingFlow`'s switch and the `onChange` beside the existing animation modifier:

```swift
            case .signedIn:    ProgressView().controlSize(.large)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: model.step)
        .transition(.opacity)
        // Called from onChange rather than the `.signedIn` view body: a body can
        // run more than once for a single state, and onFinish flips persisted
        // app state.
        .onChange(of: model.step) { _, step in
            if step == .signedIn { onFinish() }
        }
```

- [ ] **Step 4: Build**

Run: `xcodebuild -project ./LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`. A non-exhaustive-switch error here means `back()` or `OnboardingFlow` is missing the new case.

- [ ] **Step 5: Commit**

```bash
git add LIfeOS/Features/Onboarding
git commit -m "feat(auth): send a returning user straight into the app after verify"
```

---

## Task 6: Leave a stuck user a way through

**Files:**
- Modify: `LIfeOS/Features/Onboarding/Model/OnboardingModels.swift` (`SignupDraft.channel` default)
- Modify: `LIfeOS/Features/Onboarding/ViewModel/OnboardingViewModel.swift`
- Modify: `LIfeOS/Features/Onboarding/View/SignupScreens.swift` (`IdentityScreen`)

**Interfaces:**
- Consumes: `switchChannel(to:)` and `sendCode()` as they stand after Task 2.
- Produces: `OnboardingViewModel.phoneSendFailed: Bool` and `useEmailInstead()`. Nothing later depends on them.

- [ ] **Step 1: Make email the default channel**

In `LIfeOS/Features/Onboarding/Model/OnboardingModels.swift`, change the first line of `SignupDraft`:

```swift
    /// Email first: it is free through Resend to 3,000 a month, needs no A2P
    /// registration, and carries none of the SMS failure modes. An SMS costs
    /// about $0.05 and can fail four different ways.
    var channel: SupabaseAuthChannel = .email
```

- [ ] **Step 2: Track a failed phone send and offer the way out**

In `LIfeOS/Features/Onboarding/ViewModel/OnboardingViewModel.swift`:

1. Add a stored property beside `errorMessage`:

```swift
    /// Set when a code could not be sent over SMS. Every Twilio failure the
    /// classifier knows about is one the user cannot fix from inside the app,
    /// so the only useful next move is the other channel.
    private(set) var phoneSendFailed = false
```

2. Flip the channel fallback in `loadChannels()`, since email is now the default:

```swift
        if !channels.contains(.email), channels.contains(.phone) {
            draft.channel = .phone
        }
```

3. In `sendCode()`, clear the flag with the error at the top and set it in the `AuthError` catch:

```swift
        isBusy = true
        errorMessage = nil
        phoneSendFailed = false
        defer { isBusy = false }
```

```swift
        } catch let error as AuthError {
            authLog.error("sendCode failed: \(error.readable, privacy: .public)")
            errorMessage = error.readable
            phoneSendFailed = draft.channel == .phone
        } catch {
            errorMessage = "Couldn't send the code"
            phoneSendFailed = draft.channel == .phone
        }
```

4. Clear it in `switchChannel(to:)` and add `useEmailInstead()` beside it:

```swift
    func switchChannel(to channel: SupabaseAuthChannel) {
        draft.channel = channel
        errorMessage = nil
        phoneSendFailed = false
    }

    /// The one move that gets a user past a Twilio failure. Nothing in the app
    /// can make SMS deliver, so the escape has to be the other channel.
    func useEmailInstead() {
        switchChannel(to: .email)
    }
```

5. Clear it in `back()` beside `errorMessage`:

```swift
    func back() {
        errorMessage = nil
        phoneSendFailed = false
```

- [ ] **Step 3: Put email first in the picker and add the escape**

In `LIfeOS/Features/Onboarding/View/SignupScreens.swift`, inside `IdentityScreen`:

1. Swap the picker's two tags so email reads first:

```swift
                    Text("Email").tag(SupabaseAuthChannel.email)
                    Text("Phone").tag(SupabaseAuthChannel.phone)
```

2. Directly below the `if let error = model.errorMessage` block, add:

```swift
                if model.phoneSendFailed {
                    Button("Use email instead") { model.useEmailInstead() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LifeOSTokens.accent)
                        .frame(height: Space.x5)
                }
```

- [ ] **Step 4: Build**

Run: `xcodebuild -project ./LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add LIfeOS/Features/Onboarding
git commit -m "feat(auth): default to email and offer it when SMS fails"
```

---

## Task 7: Verify the whole flow and record what is left

**Files:**
- Modify: `docs/superpowers/specs/2026-08-25-auth-login-and-email-otp-design.md` (status line)

**Interfaces:**
- Consumes: everything.
- Produces: nothing.

- [ ] **Step 1: Run the full suite**

```bash
swift test --package-path LifeOSKit
deno test supabase/functions/_shared/otp_twilio_test.ts
deno check supabase/functions/otp-start/index.ts
xcodebuild -project ./LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build
```

Expected: all four succeed. Paste the actual counts into the PR body; do not claim a number you did not read.

- [ ] **Step 2: Drive the simulator through both doors**

Use the `run` skill to launch the app. There is no `idb` on this machine — tap via AppleScript against the Simulator's AXGroup geometry.

Walk these four paths and note what each one shows:

1. Intro → "Get started" → title reads **Create your account**, channel defaults to **Email**, button reads **Send code**.
2. Intro → "I already have an account" → title reads **Welcome back**, same fields.
3. On the identity screen, tap the footer link → title flips between the two, no error left on screen.
4. Switch to **Phone**, enter the Twilio test number `+11234567890`, code `123123` → verify succeeds. A brand-new account lands on **About you**; an account that already has a first name lands straight in the app with no profile step.

If the returning-email path returns **403**, that is the known risk in the spec: `SupabaseAuth.verify` hardcodes `type: "email"` and GoTrue distinguishes that from `"magiclink"` for an address it has seen. Retry with `"magiclink"` and record which one the real project accepts.

- [ ] **Step 3: Update the spec status**

In `docs/superpowers/specs/2026-08-25-auth-login-and-email-otp-design.md`, change the status line and append what is still outstanding:

```markdown
Status: implemented in code; two server-side steps outstanding
```

Add at the end of the document:

```markdown
## Outstanding (server side, not code)

- **Resend.** Verify a sending domain, then `supabase secrets set RESEND_API_KEY=...`
  and `supabase config push` to put `[auth.email.smtp]` and both templates on the
  hosted project. Until that lands, email OTP still delivers only to project
  team members and caps at the built-in sender's two per hour.
- **Twilio.** Root cause still unconfirmed. Check the console for the trial
  badge, the code under Monitor > Logs > Errors, and whether subaccounts exist.
  If it reports 21608 on credentials belonging to a paid account, the
  credentials are a subaccount's and `TWILIO_ACCOUNT_SID` needs repointing.
  Nothing in this repository can make a trial account deliver to an unverified
  number; the app's job, now done, is to say which failure it is and offer
  email as the way through.
```

- [ ] **Step 4: Commit and open the PR**

```bash
git add docs/superpowers/specs/2026-08-25-auth-login-and-email-otp-design.md
git commit -m "docs(auth): mark the login and email OTP design implemented"
git push -u origin feat/auth-login-and-email-otp
```

Then open the PR with a body built from what you actually observed, in this shape — substitute the real counts from Step 1 and the real outcome of each path from Step 2, and delete any line you did not verify:

```bash
gh pr create --title "A login door, email OTP, and a truthful Twilio map" --body "$(cat <<'BODY'
## What

Three faults in one area of the app, per `docs/superpowers/specs/2026-08-25-auth-login-and-email-otp-design.md`.

1. **There was no way to sign in.** Every path through onboarding was a signup, so a returning user was asked to create an account and then re-enter their name. There is now a second door on the intro and a footer link on the identity screen. Both doors run the identical `identity -> code` machinery; `AuthMode` drives copy only.
2. **Email could not deliver.** The magic link existed because of a stale comment about the free tier. The templates already render `{{ .Token }}`; the blocker was that no SMTP sender was configured. The link path is deleted and `config.toml` now points at Resend.
3. **One SMS failure bucket covered two unrelated causes.** Twilio 21608 and 21610 shared a message that explained neither. They are now separate kinds, 30034 and 60410 are named rather than generic, and any phone send failure offers "Use email instead".

## The branch

`AuthSession.hasProfile` is decoded from `user_metadata.first_name` and is what routes after verify, so picking the wrong door is harmless. It decodes with `decodeIfPresent ?? false` so sessions already in the keychain do not throw and sign every existing user out on upgrade, and `carryingForward` ORs it so a sparse refresh cannot erase it.

## Tests

- Swift: NN tests / NN suites passing (`swift test --package-path LifeOSKit`).
- Deno: 7 tests passing (`deno test supabase/functions/_shared/otp_twilio_test.ts`) - the first Deno test in the repo, on a function that has now regressed twice.
- iOS app target builds clean.
- Simulator: walked both doors, the mode toggle, and verify on the Twilio test number. [State what each path actually showed.]

## Outstanding, server side

- **Resend:** verify a sending domain, `supabase secrets set RESEND_API_KEY=...`, `supabase config push`. Until then email still reaches project team members only.
- **Twilio:** root cause unconfirmed pending the console. Nothing in this repo can make a trial account deliver to an unverified number; naming the failure and offering email is the part the app owns, and it is done.
BODY
)"
```

---

## Notes for the executor

- **`hasProfile` defaults to `false` in the initialiser on purpose.** It is what keeps `SessionRefreshTests` and every other existing `AuthSession(...)` call site compiling without edits. Do not remove the default to make the initialiser "explicit".
- **The `sms_unverified` case is deliberately kept** in `AuthError.fromHTTP`, sharing an arm with `sms_trial_unverified`. It is not dead code: the Edge Function deploys separately from the app, so a new build will talk to an old function for a while.
- **Do not add an "account exists?" check.** Both the spec and the Global Constraints rule it out as user enumeration, and the post-verify branch already gives everything it would.
- **`lifeos://auth-callback` stays in `config.toml`.** Unused, harmless, and removing it means touching the Whoop callback's neighbour in a change that has nothing to do with Whoop.

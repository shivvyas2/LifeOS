# Login screen, email OTP, and the Twilio failure map

Date: 2026-08-25
Status: approved, not yet implemented

## Problem

Three faults in the same area of the app.

**There is no way to sign in.** `OnboardingStep` runs `intro → identity → code
→ profile → connections` and every path through it is a signup. A user who
reinstalls, switches device, or signs out is handed "Create your account" and,
after proving they own the number, is asked for their name and country again.
The account is already there; the app just has no idea and no screen that says
so.

**Email signup cannot deliver.** `SupabaseAuth.sendMagicLink` exists because of
a comment claiming the free tier cannot send a six digit token. That claim is
stale. `supabase/templates/magic_link.html` and `confirmation.html` both
already render `{{ .Token }}`, and `config.toml` already sets `otp_length = 6`.
The real blocker is one line lower: `[auth.email.smtp]` is commented out, so
the project is on Supabase's built in sender, which delivers only to project
team members and caps at two emails per hour. Someone did the template work and
then had no way to send the mail, so the magic link stayed switched on.

**Phone OTP fails with the wrong explanation.** Signup reports "Couldn't send
the text to that number yet". That string has exactly one source:
`classifyTwilioFailure` returning `sms_unverified`, which fires for Twilio code
21608 or 21610 and nothing else. 21608 is trial accounts only and this account
is paid, which leaves 21610, "attempt to send to unsubscribed recipient". The
number is on Twilio's opt out list. The copy names neither cause and offers no
remedy.

## Approach

One idea carries the whole design: **with OTP there is no such thing as a login
screen, only a login door.** Signing in and signing up are the same three
steps, entered from different places and distinguished only after the code is
accepted. So the flow gains a second entrance and a branch at the end, not a
second implementation.

Rejected: checking whether an identity exists before sending a code, so that
"Sign in" could say "no account found" up front. It needs an endpoint that
reports whether a phone or email is registered, which is a user enumeration
hole, and it buys nothing the post verify branch does not already give.

## Design

### 1. Two doors, one engine

`OnboardingStep` drops `.linkSent` and gains a terminal `.signedIn`:

```
intro ─→ identity ─→ code ─→ profile ─→ connections
                       └──────────────────→ signedIn
```

A new `AuthMode { case signUp, signIn }` lives on `OnboardingViewModel` and
drives copy only. Both modes run identical `identity → code` machinery.

| | `.signUp` | `.signIn` |
|---|---|---|
| Identity title | Create your account | Welcome back |
| Footer link | Already have an account? Sign in | New here? Create an account |

`IntroScreen` gains "I already have an account" beneath its primary button,
calling `model.beginSignIn()`. The temporary guest bypass stays as it is.

Picking the wrong door is harmless and deliberately so. Tap "Sign in" without
an account and you get one, then land on the profile step. Tap "Get started"
with an account and you skip profile and go straight in. Correct routing is a
consequence of the branch below, not of the door.

### 2. The branch

`AuthSession` gains `hasProfile`, decoded from `user.user_metadata.first_name`
being non empty. Both channels reach it: the email path reads
`/auth/v1/verify` directly, and the phone path gets the same body forwarded by
`mintSession`, which returns the verify response verbatim.

```swift
step = session.hasProfile ? .signedIn : .profile
```

`OnboardingFlow` renders a `ProgressView` for `.signedIn` and calls `onFinish()`
from `.onChange(of: model.step)`, never from the view body.

Two constraints on the new field:

- Sessions already in the keychain have no `hasProfile` key. A synthesised
  `init(from:)` would throw on them and sign every existing user out on
  upgrade, so it decodes with `decodeIfPresent ?? false`. Defaulting to false
  is safe because the branch only runs immediately after `verify`; a restored
  session goes straight to the app on `hasFinishedOnboarding`.
- `AuthSession.carryingForward` ORs the flag with the previous session's, for
  the same reason it already carries `userID`, `phone` and `email`: a refresh
  response is allowed to be sparse and must not erase what is known.

### 3. Email OTP replaces the magic link

Client side this is almost entirely deletion. `sendCode` and `verify` already
implement email OTP. Removed: `emailUsesMagicLink`, `sendMagicLink`,
`LinkSentScreen`, `.linkSent`, `handleAuthCallback`, `AuthSession(callback:)`,
`AuthSession.errorDescription(in:)`, `authCallback`, and the `auth-callback`
branch of `onOpenURL` in `AppShell`. `sendButtonTitle` becomes the constant
"Send code" and `identitySubtitle` loses its magic link wording.

`sendCode` keeps `create_user: true` in both modes. Setting it false in
`.signIn` would turn a typo into "no account with that email", which is the
same enumeration hole rejected above.

Server side is what actually unblocks it:

```toml
[auth.email.smtp]
enabled = true
host = "smtp.resend.com"
port = 465
user = "resend"
pass = "env(RESEND_API_KEY)"
sender_name = "Life OS"
```

with `auth.rate_limit.email_sent` raised from 2, which is a limit of the built
in sender and not of Resend. Then set `RESEND_API_KEY`, verify a sending domain
in Resend, and `supabase config push` to put the auth config and both templates
on the hosted project. Both templates are needed: GoTrue sends
`confirmation.html` to an address it has not seen and `magic_link.html` to one
it has.

Resend's free tier is 3,000 emails per month at no cost, which keeps this
inside the roughly $2 per user per month ceiling.

### 4. Twilio

The account fix is not code. Code 21610 means the number replied STOP and sits
on Twilio's opt out list; clearing it is a console action under Messaging →
Opt Outs, or texting START to the sender. This is recorded here because the
error copy is what sent the reader looking in the wrong place.

`classifyTwilioFailure` and `AuthError.fromHTTP` change regardless:

- Split 21608 from 21610. One is a developer misconfiguration that cannot occur
  on a paid account, the other is a user action with a user remedy. Today they
  share one bucket whose copy explains neither.
- Add 30034, unregistered A2P 10DLC campaign, and 60410, Verify delivery
  blocked. Both currently fall through to a generic "Couldn't send the text",
  which is the same class of bug `ba343c7` was written to fix.
- On any phone channel send failure the identity screen offers "Use email
  instead", which switches the channel and clears the error. This is the change
  that actually moves a stuck user forward.

Email also becomes the default channel, with phone second. SMS verification
costs roughly $0.05 each, needs A2P registration, and carries every failure
mode above; email through Resend is free to 3,000 a month and carries none of
them.

### 5. Testing

Swift: `hasProfile` decoded from a verify body; a keychain blob without the key
still decoding; `carryingForward` preserving it; sign in mode routing to
`.signedIn` and signup routing to `.profile`; new `AuthErrorMappingTests` cases
for 21610, 30034 and 60410.

Deno: a first test for `classifyTwilioFailure`, which is pure, untested, and has
now regressed twice.

## Risks

**Verify token type.** `SupabaseAuth.verify` hardcodes `type: "email"`. GoTrue
distinguishes that from `type: "magiclink"`, and which one a returning address
needs is version dependent. If the returning user path returns 403 in testing,
retry with `"magiclink"`. To be confirmed against the real project rather than
assumed.

**Conflict with `fix/otp-error-copy`.** That branch is unmerged and edits the
same `sms_unverified` case, rewriting it to "That number isn't verified for SMS
yet. Add it in Twilio, then try again". That is the 21608 trial account reading
and is wrong for this paid account. This work supersedes it in that block, and
whichever lands second has to take the split version.

**Deleting the callback path.** Removing `AuthSession(callback:)` leaves
`lifeos://auth-callback` allow listed in `config.toml` and unused. Harmless,
and left alone so the Whoop callback's neighbour is not disturbed in the same
change.

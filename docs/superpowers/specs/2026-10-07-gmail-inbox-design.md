# The important mail, on Today

Decided 2026-10-07 with the owner, who asked for "important Gmail to be
synced and showed in the inbox here on the Today". Slice 3 of the day
briefing (the 2026-10-06 spec named it: "a Google sign-in with Gmail read
access, on-device picking by the device model, nothing leaving the phone").

Decisions, in the order they were made:

- **Built for test users now.** `gmail.readonly` is a Google restricted
  scope. Up to 100 test users listed in the Google Cloud project can connect
  without Google's review (each sees an "unverified app" notice once). A
  public launch needs Google's app verification and a yearly CASA security
  assessment; that is out of scope here.
- **NEEDS YOU and FYI, summarised on the phone.** Apple's on-device model
  sorts recent important mail and writes a one-line summary; without Apple
  Intelligence it falls back to Gmail's order and snippet.

Nothing reaches the server: the token, the mail and the model's output stay
on the phone. No new function, table or secret; no running cost.

## 1. Connecting

`Settings › Connections` gains a `Gmail` card, drawn like GitHub's:
`Connect`, then `Connected as you@gmail.com` with `Disconnect`.

- **Sign-in:** `ASWebAuthenticationSession` to
  `https://accounts.google.com/o/oauth2/v2/auth` with the iOS OAuth client
  id, `response_type=code`, `scope=openid email
  https://www.googleapis.com/auth/gmail.readonly`, PKCE (S256), a random
  `state`, `access_type=offline`, `prompt=consent`, and
  `redirect_uri=<reversed client id>:/oauth2redirect`. The code is exchanged
  at `https://oauth2.googleapis.com/token` from the phone: an iOS client has
  no secret.
- **Tokens:** `GoogleConnection { accessToken, refreshToken, expiresAt,
  email }` in the Keychain, per account (`KeychainGoogleTokenStore`, built
  like `KeychainGitHubTokenStore`). An access token within a minute of
  expiry is refreshed with the refresh token before any call. A refresh
  refused with `invalid_grant` marks the connection as needing reconnect.
- **Disconnect:** `POST https://oauth2.googleapis.com/revoke?token=<refresh>`
  (best effort), then the Keychain item, the cache and the module offer flag
  are cleared.
- **Configuration:** `GOOGLE_CLIENT_ID` in `Secrets.xcconfig` →
  `GoogleClientID` in `App-Info.plist`; the reversed client id is added to
  the app's URL schemes as `GOOGLE_REVERSED_CLIENT_ID`. Unset, the card reads
  `Setup` and is disabled.

## 2. What is read

- **List:** `GET https://gmail.googleapis.com/gmail/v1/users/me/messages`
  with `q=in:inbox category:primary is:important newer_than:2d` and
  `maxResults=25`.
- **Each message:** `GET .../messages/{id}?format=metadata&
  metadataHeaders=From&metadataHeaders=Subject&metadataHeaders=Date`, which
  carries `threadId`, `labelIds` (for `UNREAD`), `internalDate` and Gmail's
  own `snippet` (about 200 characters). Bodies are never downloaded.
- **When:** when Today appears, if the last fetch is more than 10 minutes
  old; on pull to refresh; never in the background.
- **The result** is a `MailItem { id, threadId, sender, senderEmail,
  subject, snippet, receivedAt, isUnread }`, newest first.

## 3. Sorting, on the phone

`MailSorter` asks `SystemLanguageModel.default` (FoundationModels) once per
new message, with guided generation of:

```swift
@Generable struct MailVerdict {
    @Guide(description: "needsYou if the sender asks the reader to reply, decide, sign, pay, attend or meet a deadline; otherwise fyi")
    var bucket: Bucket   // .needsYou, .fyi
    @Guide(description: "One plain sentence, at most 90 characters, saying what the mail wants or says")
    var summary: String
}
```

The prompt carries only the sender name, subject and snippet. Verdicts are
cached per message id (`gmail.verdicts` in the account's defaults, at most
200, oldest dropped), so a message is judged once. When the model is
unavailable (`SystemLanguageModel.default.availability` not `.available`)
or a call fails, the message is FYI and its line is the snippet, trimmed to
90 characters on a word.

`InboxDigest` (a tested rule in `Integrations`) builds what Today shows
from items and verdicts: NEEDS YOU first (newest first), then FYI, at most
five in all, NEEDS YOU never cut for FYI, and the count of NEEDS YOU.

## 4. On Today

- `TodayModule.inbox`, titled `Inbox`, hidden by default and added once to
  the left column the first time Gmail connects (as GitHub's module is).
- The module: `INBOX` with `<n> need you` (or `Nothing needs you`), then
  `NEEDS YOU` and `FYI` groups, each row `Sender · Subject`, the time, and
  the summary line in quiet ink; unread rows have a dot. A tap opens
  `googlegmail:///cv=<threadId>`, or
  `https://mail.google.com/mail/u/0/#inbox/<threadId>` when Gmail is not
  installed (`LSApplicationQueriesSchemes` gains `googlegmail`).
- States: not connected (hidden outside arranging; a ghost with `Connect
  Gmail` while arranging), loading, `Gmail needs reconnecting` (a row that
  opens Settings), and `No important mail in the last two days.`

## 5. Verification

- Package tests: the list query and metadata URL; decoding a list and a
  metadata message (sender name and address from `From`, unread from
  labels, date from `internalDate`); `InboxDigest` (order, the five-row cap,
  NEEDS YOU never cut, the count); the snippet fallback trimmed on a word;
  the verdict cache cap; the authorize URL with PKCE and state; the token
  expiry check; `invalid_grant` read as reconnect.
- A preview page `today-inbox` with a stub mail source and stub verdicts;
  a UI test that the module shows NEEDS YOU above FYI and opens a row.
- The app and the package for macOS build; typography reports nothing new.

## 6. Owner's steps

1. Google Cloud console: a project, enable the **Gmail API**.
2. OAuth consent screen: External, **Testing**, add test users (yourself
   first).
3. Credentials: an **iOS** OAuth client for bundle id
   `com.shivvyas.lifeos`; send the client id.

## Out of scope

- Replying, archiving, marking read; other providers; the Watch; push
  alerts; Google verification and CASA.

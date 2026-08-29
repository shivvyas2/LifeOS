# Proactive LIFO, Slice 2: what shipped and what it still needs

**Date:** 2026-08-28
**Spec:** `docs/superpowers/specs/2026-08-28-proactive-lifo-design.md`
**Covers:** sections 5.1, 5.3, 6.1, 6.2, 6.4, 6.5, 8, 9

Slice 1 (the conversational core, section 4) landed in `475824b`. This is the
slice that lets LIFO speak first.

## What shipped

**Server**

- `supabase/functions/_shared/nudge.ts` plus `nudge_test.ts` (25 tests). The
  trigger layer: pure functions from rows to an optional fired result, the
  volume rules, and the phrasing prompt. No network, no clock, no database.
- `supabase/functions/_shared/apns.ts` plus `apns_test.ts` (9 tests). Payload,
  headers, dead-token classification, and ES256 provider tokens with the
  fifty minute cache Apple's rate limit requires.
- `supabase/functions/lifo-nudge/index.ts`. The door: cron auth, one batched
  query per table, claim then phrase then send.
- `supabase/migrations/20260830090000_proactive_nudges.sql`. `device_tokens`,
  `nudge_log`, and `kind` added to `lifo_usage`'s key.
- `_shared/lifo.ts` gains the `nudge` task, behind the same `SCOPE` guardrail
  and the same typography prohibitions chat uses.
- `lifo-agent/index.ts` is scoped to `kind = 'chat'`. Required, not cosmetic:
  an unscoped `maybeSingle()` finds two rows on any day a nudge went out.

**Device**

- `PushTokenClient` and `NudgePayload` in `Integrations`, with tests.
- `PushService` and `PushDelegate` in `LIfeOS/App`.
- `aps-environment` in the entitlements, `remote-notification` in the plist.
- `CoachViewModel.seed(_:)`, which writes the nudge into the store as well as
  the transcript so the model answering the reply can see what it opened with.

## What it still needs before a nudge can arrive

None of this is code. All of it is credentials or a one-time setup step.

1. **Enable Push Notifications** on the App ID in the Apple Developer portal,
   and regenerate the provisioning profile.
2. **Create an APNs auth key** (.p8) and set four Edge Function secrets:
   `APNS_KEY` (the PEM contents, newlines intact), `APNS_KEY_ID`,
   `APNS_TEAM_ID`, `APNS_BUNDLE_ID`. Set `APNS_SANDBOX=true` while the build
   is signed for development; the entitlement and the host have to agree or
   every send is `400 BadDeviceToken`.
3. **Apply the migration.** `supabase db push`.
4. **Schedule the job.** Run `supabase/functions/lifo-nudge/schedule.sql` once,
   after storing the service role key and project URL in Vault. It is not a
   migration because it needs both, and neither belongs in git.
5. **Deploy the function.** `supabase functions deploy lifo-nudge`.

Until step 2 is done, `lifo-nudge` returns `apns_not_configured` and sends
nothing. That is deliberate: a deployment without keys should be quiet, not
noisy.

## What has not been verified

- **The migration has not run against a database.** There is no Docker on this
  machine, so it is reviewed SQL rather than applied SQL. The riskiest line is
  the primary key swap on `lifo_usage`; check it on a branch database first.
- **No real push has been delivered.** Everything up to the APNs request is
  tested, including the signature. The request itself needs a key.
- **Whether a given sentence was worth interrupting someone for.** The spec
  says this needs a week of real days on a real device, and it still does. The
  volume rules exist because that judgement is unreliable and the cost of
  getting it wrong is a permanently disabled channel.

## Not in this slice

Section 5.2 (device-side triggers), 6.3 (`sector_snapshots`) and 7
(`open_commitments`) are slice 3. `lifo-nudge` therefore ships without step 1
of section 6.2, as the spec says it should, and gains it there.

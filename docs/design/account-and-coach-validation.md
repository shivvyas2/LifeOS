# Account, onboarding and coach changes — 2026-09-13

## Behavior

- Login, signup, code entry, profile setup, and connection setup share the warm canvas, charcoal actions, orange accents, consistent margins and scrollable native forms. Email/phone tabs use an underline instead of pills. Sign-in and its code-entry screen have no progress bar or step count.
- Onboarding explains WHOOP, Google Fitbit and bank accounts through Plaid, with live connection actions and account ownership explained in plain language.
- Opening an account creates or restores only that account's SwiftData file, keychain namespace, preferences and conversation history. A fresh login cannot adopt an unidentified legacy store.
- Saved provider links belong to the authenticated account. WHOOP credentials are also stored on the backend; Fitbit and Plaid restore from their account-owned backend records. Transient failures preserve saved links.
- Logout closes the active store, clears auth and pending OAuth flows, stops connection observers, clears notifications and calendar/Health opt-ins, and returns to onboarding. The owner's saved data and server links remain available after they sign in again. It does not delete events from the phone's Calendar app.
- Calendar system permission alone no longer authorizes another LifeOS account. That account must explicitly enable calendar access.
- Coach replies use short answers, optional metric cells, comparison tables and action rows. Formatting is preserved through both chat engines. Missing values are not replaced with zero; malformed tables remain visible as text.

## Post-login welcome

The second onboarding came from `AppShell` presenting the independent `FirstRunTour` overlay when `hasSeenFirstRunTour` was false. The former six-page tour is now a single, scrollable welcome screen using the same 3D mascot, neutral canvas, orange accents and rectangular action. It points to Today, connections and the coach, then opens the app. Completion remains per account; cancellation of the launch task cannot present a stale tour.

## Verification

- Full Swift package suite: **1,167 tests passed**, including account identity, per-account stores, refresh/logout races, WHOOP app-session versus provider revocation, Fitbit sync retries, Plaid connection reconciliation and structured coach parsing.
- Shared backend tests: **44 passed**.
- WHOOP and Fitbit edge functions pass Deno type checks.
- The WHOOP account-connection migration was applied to the linked backend. WHOOP token, Fitbit token/sync and coach functions were deployed. Unauthenticated POST smoke checks returned **401** for all four endpoints.
- Coach metric cards, comparison table and action rows were visually inspected using clearly labeled sample data (`docs/design/coach-cards.png`). The temporary harness was removed from the app entry point after compilation.
- Native simulator build succeeded. Login, signup and code-entry layouts were inspected on iPhone 17 Pro / iOS 26. Login/signup images are in this folder's `onboarding` subdirectory.

## Configuration still required

Live Fitbit linking is blocked by configuration, not by a saved-link reset: `FITBIT_CLIENT_ID` and `FITBIT_CLIENT_SECRET` are absent from the linked backend. The app build is also missing `FITBIT_CLIENT_ID` and `FITBIT_REDIRECT_URI`. Use the existing `Config/Secrets.example.xcconfig` template for public client settings; keep the client secret only in the backend. Never put it in the app bundle.

No live WHOOP, Fitbit or bank OAuth authorization was performed during this verification. Provider consent, external revocation, cross-device restore and physical-device animation performance still need an end-to-end run with test accounts.

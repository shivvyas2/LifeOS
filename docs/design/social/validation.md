# Social implementation validation

## Available flows

Profile → Together contains People, Groups and Rankings. People supports search, friendship requests and public profiles. Friends can message from a profile or return through the inbox. Groups support creation, invitations, chat, member management, leaving and an optional leaderboard. Group owners can invite accepted friends and remove members; ownership transfers when an owner leaves.

Rankings use actual recorded streaks, all-time workouts and all-time days tracked. Group activity sharing is opt-in per group. Shared profile totals are a separate accepted-friends-only setting. Missing activity is omitted; real zero remains valid. Ties retain server ranks.

## Checks

- Normal native build: passed; `/private/tmp/lifeos-social-final-build.log`.
- Full package suite: 1,182 tests in 154 suites passed; `/private/tmp/lifeos-social-final-tests.log`.
- Linked database lint: passed; `/private/tmp/lifeos-social-db-lint.log`.
- SQL behavior: 43 assertions passed; `/private/tmp/lifeos-social-transaction-tests.log`. The pgTAP assertions in `supabase/tests/social_groups.test.sql` were executed in a rollback transaction through the authenticated management API because the CLI pgTAP runner required an unavailable Docker daemon. No fixture users, groups or messages remain.
- Migration `20260914090000_social_groups.sql` applied to the linked backend.
- UI sample fixtures reviewed on iPhone 17 Pro/iOS 26 and iPad/iOS 26.2, including large text, ties and dark chat. See the project-root `design-qa.md` and local screenshots.
- The normal app bundle remains `com.shivvyas.lifeos`; sample preview bundle is separate, `com.shivvyas.lifeos.socialpreview`. Production startup does not reference the design preview.

## Delivery state

App source changes are local and have not been committed or pushed in this pass. Backend migration is deployed. Live two-account UI verification and iOS 27 runtime testing remain outside the verified coverage.

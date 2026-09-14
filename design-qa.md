# Social design QA

Final result: passed

## Source and scope

- Visual source: `/Users/shivvyas/Downloads/4a3ef793a8177e8e97074f7e39800177.jpg` (1200 × 900).
- Latest user direction takes precedence over the reference font: keep the app’s existing typography consistent. Native system sans and the shared LifeOSType scale are used throughout social UI, with scalable counterparts for Dynamic Type.
- This is a native SwiftUI implementation in the existing app. The reference guides cream surfaces, strong hierarchy, top-three avatars, divided ranked rows, black actions, and colorful score circles. Quiz content, gems, the sample photographs, and the reference’s navigation are not copied into the product.

## Evidence and normalization

- Combined comparison: `docs/design/social/reference-comparison.png`. Source leaderboard region (815,154)-(1110,740), scaled to 402 pixels wide; native render cropped below the debug control strip (0,325)-(1206,2520), normalized from 3× to 402 pixels wide. The source is a perspective mockup; this compares composition and visual direction, not exact pixel geometry.
- iPhone: 1206 × 2622 pixels, native 402 × 874 points, 3×. `leaderboard-iphone.png`, `leaderboard-large-iphone.png`, `leaderboard-ties-iphone.png`, `friends-iphone.png`, `friends-large-iphone.png`, `groups-iphone.png`, `chat-iphone.png`, `chat-dark-iphone.png` in `docs/design/social/`.
- iPad: 1668 × 2420 pixels, native 834 × 1210 points, 2×. `leaderboard-ipad.png`, `groups-ipad.png`.
- State: explicitly labeled sample fixtures; no account data loaded by preview models. Debug controls above the navigation bar are excluded from the comparison and are absent from the production entry point.
- The normalized comparison makes the full hierarchy and focused podium/list typography, spacing, circles and rows readable together. Original full-resolution captures were also opened for text and accessibility review.

## Findings and comparison history

1. P2, initial typography and vertical density: `leaderboard-iphone-before-polish.png` used an overly heavy condensed face and oversized introductory block. Replaced the separate face with the app’s shared system typography in response to the user’s clarification; removed redundant copy and reduced spacing. Verified in `leaderboard-iphone.png` and the combined comparison.
2. P2, accessibility tabs and actions: enlarged tabs split labels, and single-row request actions competed with the person’s name. Accessibility sizes now use a native section menu; request actions stack below identity. Verified in `friends-large-iphone.png` and `leaderboard-large-iphone.png`.
3. P2, enlarged leaderboard heading: `leaderboard-large-before-polish.png` split “Leaderboard” in the crowded title/filter row. Moved the metric control beneath the title. Recaptured the same device and accessibility size in `leaderboard-large-iphone.png`; the title now remains intact.
4. No remaining actionable P0/P1/P2 findings in the reviewed states.

## Required fidelity surfaces

- Typography: one system sans family; shared display, screen, section, row, body and caption roles. Dynamic Type preserves the app’s default scale and increases readability. The deliberate difference from the narrow reference face follows the latest user request.
- Spacing/layout: native navigation, 20-point phone gutters, capped wide layouts, compact ranked rows, three-person podium and clear separators. At accessibility sizes the full ranked list replaces the podium. Equal ranks retain equal labels and equal visual prominence; a tie crossing the podium boundary falls back to the complete list.
- Colors/tokens: warm cream fades toward an off-white paper surface; brand orange remains on navigation, sharing controls and sending. Coral, mint, lilac and yellow identify avatar/score accents. Dark mode keeps readable text and distinct incoming/outgoing bubbles.
- Images/icons: actual profile photos load through the authenticated avatar client. Initials are the legitimate no-photo fallback, demonstrated in fixtures; stock people are not substituted for users. Native SF Symbols provide interface icons. Profile photos are circular, clipped and ringed consistently.
- Copy: real streak/workout/day metrics replace quiz points. Group consent is explicit and independent of friend-profile sharing. No invented online/read status or fabricated activity. Empty and error states provide actionable next steps.

## Interaction and test evidence

- Simulator UI navigation from leaderboard to chat verified. Composer changed from disabled send to enabled after entering a draft; no message was sent. Large text toggled and examined. Accessibility tree exposes full rank/name/score labels and selected sections.
- Native app build passed with production entry point restored.
- Package suite: 1,182 tests in 154 suites passed.
- Backend: 43 transactional assertions passed, including RLS isolation, invitation acceptance, sharing consent, ties, message retry idempotency, removal/ownership transfer and deletion of the final empty group. Fixtures rolled back.

## Residual test gaps

- Live two-account end-to-end messaging and real avatar downloads were not exercised through the simulator UI in this pass; transport and database behavior were checked separately.
- Installed simulators are iOS 26/26.2. iOS 27 and unannounced device configurations have not been runtime-tested.
- No changes were made to Today’s dot interface or the owner profile’s photo-derived glass presentation.

## Daily health leaderboard update

The user subsequently replaced streak/workout/day rankings with Effort, Recharge and Rest comparisons and required Apple Health, WHOOP and Fitbit support. The added metric explanation, day selector and provider labels are intentional functional additions to the earlier reference-guided layout.

Evidence: `docs/design/social/wellness-leaderboard-iphone.png`, `wellness-leaderboard-large-iphone.png`, `wellness-leaderboard-ties-iphone.png`, `wellness-leaderboard-ipad.png`, and `wellness-recharge-explanation.png`. Same 402 × 874 point iPhone and 834 × 1210 point iPad fixture viewports. The compact and accessibility layouts were opened and inspected; typography remains shared, controls fit, and missing readings have an explicit state. Category menu selection and the Recharge disclosure were exercised in the simulator. Provider names are also included in the final VoiceOver rank labels.

Final health-update verification: 1,199 package tests, 10 Fitbit helper tests, 23 wellness database assertions and 43 group/chat database regression assertions passed; native build and database lint passed. See `docs/design/social/wellness-leaderboards.md` for definitions, caveats, API references and deployment state. Live accounts for all three providers have not been exercised in the simulator.

Final result: passed

## Health, account and Begin Activity — 2026-09-14

Visual target: the supplied health tiles / heart-rate reference and journal reference (`8b43589606845085ce824c83cf05a695.jpg` and `667e20b408cf9b32ef62977eef31746c.jpg`). This is an adaptation into the existing native app, not a pixel clone: SF typography, orange actions, the original module pastels, system navigation and the photo-derived profile glass are intentional constraints. No reference illustrations, fictional chart values or emotion scores were introduced.

Evidence: `docs/design/health-activity/`. iPhone screenshots are 1206×2622 pixels at 3× (402×874 points); iPad screenshots are 1668×2420 at 2× (834×1210 points). Native screen content was compared with both supplied references in the same image inputs. The reference phone mockups include device framing; comparisons assessed app-owned card composition, color, typography, spacing and hierarchy rather than the mockup bezels.

First-pass fixes:
- P2: recovery caption used low-contrast green on the restored blue card. Changed caption to adaptive primary ink; `health-iphone.png` was recaptured and inspected after the fix.
- P2: Settings repeated the Appearance title inside and outside its card. Removed the inner heading; `settings-iphone.png` was recaptured and inspected after the fix.

Final visual checks:
- Existing four top Health tiles retain their data, ordering, navigation and date controls, with the requested module colors restored.
- Category cards feature a leading reading with aligned supporting cells; accessibility text uses a single supporting column. No clipping in the reviewed iPhone/iPad category layouts.
- Profile shortcuts keep the transparent glass surface; Together is prominent and Connections/Settings sit in two readable cards. See `profile-shortcuts-iphone.png`.
- The mint weight panel and peach journal card have coherent spacing and a clear writing action. See `journal-weight-iphone.png`.
- Begin Activity has clear selection, timer, pause/resume and save hierarchy. Missing measurements are stated; no simulated beats or calories appear in production.
- Shared typography, warm canvas, orange actions, adaptive dark palette, real SF Symbols and concise copy match the existing app. The illustrative reference assets were intentionally not recreated because the request was to adapt its card presentation.

Interaction checks: selected Run, started with Health saving off, paused at 00:19, confirmed elapsed time stayed fixed while opening the syncing explanation, resumed and saved at 00:25. The saved screen correctly reported local account storage. `activity-running-iphone.png` and `activity-saved-iphone.png` capture these states. Nine additional native recorder lifecycle checks passed in an isolated in-memory store; 1,202 package tests passed. The final production-entry iOS build passed and `git diff --check` is clean.

Physical sensor streaming, Apple Watch delivery timing and actual HealthKit write authorization/saving remain hardware validation items. The simulator checks do not establish end-to-end wearable performance. There is no Apple Watch companion in this repository, and the UI does not claim live control of Apple's Workout app. No real account data was used in the preview or recorder checks.

final result: passed

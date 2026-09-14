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

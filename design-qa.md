# Onboarding visual QA — 2026-09-13

Source visual: `/Users/shivvyas/Desktop/View recent photos.png` (658 × 780).
Implementation: `docs/design/onboarding/light.png` and `docs/design/onboarding/dark.png` (1206 × 2622).
Device: iPhone 17 Pro, iOS 26.0, 402 × 874 points at 3× density.
State: introduction, first page, signed out. Source is a character reference, not an onboarding screen; screen geometry and typography are intentionally designed for native iOS rather than copied from the image.

## Comparison

Opened the reference and final simulator capture together in the same comparison input. Compared the cat silhouette, facial proportions, raised paw, neutral surface, and horizontal stripes. The native 3D rendering intentionally adds smooth volume, articulated animation, and a rounded mascot face. Full-resolution captures make the face and screen copy readable without a separate crop.

- Typography: system sans, bold two-line headline, smaller tracked category, and readable supporting copy. No text clipping at the standard size.
- Layout: consistent horizontal margins; character, category, headline, page dots, and bottom action all fit the first screen. Category pills removed. Primary action uses a 16-point rounded rectangle.
- Colors: existing warm canvas and charcoal text. User-requested orange remains on the brand, selected dot, action arrow, and sign-in link. No per-page pastel fills.
- Character: rounded ears, oversized head and eyes, small body, curved smile, and visible horizontal line texture. The mesh is animated natively, as requested, rather than represented by a still image.
- Copy: five concise introductions retain health, money, habits, and plans and explain account-owned connections before the account flow.

## Iterations

1. Initial scene crowded the page dots below the visible region. Reduced hero height using the available screen height. Final light capture shows dots and footer together.
2. User rejected pill labels and mixed colors. Removed badges and per-page tints; changed the action shape and page indicator. Restored focused orange accents following the user's correction.
3. Mascot refinement: enlarged eyes/head, shortened ears/body, softened the mouth and ear geometry, and reduced lighting intensity. Final capture shows the rounded smile and softened ears.
4. Maximum text-size check revealed branding wrapping. Capped decorative branding scaling, kept its name unbroken, and allowed accessible copy to use a continuous vertical layout outside the nested pager. Footer remains pinned; long text is intentionally scrollable.

## Validation

- Final iOS simulator build: **BUILD SUCCEEDED**.
- `git diff --check`: passed.
- Exercised Continue to health, direct selection of money, Continue to the last page, and Get started to account creation. Back from signup returned to the intro.
- Light/dark rendering visually inspected; final simulator restored to light and standard text size.
- Animation frames show the wave and blink. Scene construction uses one retained scene; rendering pauses offscreen/inactive and for Reduce Motion.

Residual verification gaps: no physical-device performance measurement, VoiceOver session, or runtime Reduce Motion toggle test. Largest-text branding was inspected; the final continuous accessibility layout has build verification but has not had a complete scroll-through after that change.

final result: passed


## Login, signup and coach follow-up

Login/signup now share the onboarding canvas, typography, orange brand and progress, and charcoal rectangular action. Email/phone selection uses a plain underline. The form scrolls and the action respects the keyboard safe area. Native login, signup and code entry were inspected; no clipped standard-size text was observed. Saved captures: `docs/design/onboarding/login.png` and `signup.png`. The email placeholder was subsequently given an explicit neutral color to remove the system blue.

Account lifecycle, provider persistence, structured coach rendering, deployment evidence and the remaining Fitbit configuration are documented in `docs/design/account-and-coach-validation.md`.


## Final post-login and sign-in pass

Traced the second onboarding to `AppShell`'s account-scoped `hasSeenFirstRunTour` overlay. Replaced the six-page `FirstRunTour` with a single welcome screen, the same animated 3D cat, three concise orientation rows and an orange-accented “Open my day” action. The final welcome capture shows all content and the action at standard text size without clipping. Sign-in identity and code entry no longer show a progress bar or step count; signup retains its step guide.

Final captures: `docs/design/onboarding/welcome.png`, `docs/design/onboarding/login.png`, and `docs/design/coach-cards.png` (coach uses explicitly labeled preview data). A separate simulator and temporary native view harness kept the user's current sign-in untouched. The app entry point was restored and the normal iOS app rebuilt successfully after capture. Final `git diff --check` passed.

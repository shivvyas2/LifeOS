# Health Restructure + App-Wide Restyle Design Spec

**Date:** 2026-08-25
**Status:** Approved in brainstorming; awaiting spec review
**Scope of this document:** Project 1 of the August 2026 roadmap (Section 2). UI/IA only — no schema, sync, or backend changes.

---

## 1. What this is

Two coupled changes shipped as one project:

1. **Restructure**: the Body tab becomes **Health**, organized as two segments — **Health** (how the body is doing: recovery, sleep, vitals with anomaly alerts, weight, journal) and **Fitness** (what the body did: steps, strain, calories burnt, workouts). The old four-way Activity/Weight/Recovery/Wellness split disappears.
2. **Restyle**: the whole app — Today, Health, Money, Plan — moves from saturated per-module gradient canvases to a soft light-card aesthetic modeled on the reference screenshots: cream canvas, white rounded cards with soft shadows, pastel accent chips, ring-progress week strip, and a custom floating pill nav. Dark mode remains fully supported.

Reference screenshots (fitness-app UI the user wants to emulate) live on the user's Desktop, dated 2026-08-24. Their defining traits: near-white warm canvas; white rounded-2xl cards; big dark hero numerals; icons in pastel circular bubbles; rounded-bar weekly charts (two-tone orange); a red alert banner card for abnormal vitals; a week strip with per-day progress rings; a floating pill nav of circular icon buttons with a dark filled circle for the selected tab.

## 2. Roadmap context

Decided during brainstorming on 2026-08-24/25. Each project is its own spec → plan → implementation cycle:

- **Project 1 (this spec)** — Health/Fitness restructure + app-wide restyle. No backend needed.
- **Project 0.5** — API backbone: a containerized custom API on **GCP Cloud Run** (FastAPI or Hono; Swagger UI at `/docs`), replacing Supabase Edge Functions as the home for server logic. **Supabase stays for auth + Postgres.** Vercel is reserved for a possible future web dashboard, not the API. Chosen for cost: free tier at personal scale, no plan cliffs, no function-duration limits for long Whoop syncs.
- **Project 2** — Nutrition + AI meal logging: `MealRecord` model, meal cards in the Health segment, photo/chat → Claude vision calorie & macro estimation via a `meal-analyze` endpoint on the Cloud Run API (holds the Anthropic key), with manual-entry fallback.
- **Project 3** — Wake-triggered morning check-in: Whoop webhook → Cloud Run → APNs push the moment sleep ends; tapping opens a check-in sheet (sleep-quality rating, habit checklist reusing `HabitTick`, mood + energy sliders, free-text journal reusing `PlanKind.journal`). Requires an APNs key and a device-token table. User explicitly chose the full APNs pipeline over local-notification approximation.

Order: 1 → 0.5 → 2 → 3.

## 3. Information architecture

### 3.1 Tabs and navigation

- Four tabs, unchanged in identity: **Today, Health, Money, Plan**.
- The native `TabView` chrome is replaced by a **custom floating pill nav**: a horizontal pill of circular icon buttons, selected tab shown as a dark filled circle with light icon. User chose this over the native iOS 26 floating tab bar knowing the trade-offs (we own hit-testing, safe areas, accessibility).
- iPad: same centered pill, sized by `LayoutMetrics`. The `.sidebarAdaptable` sidebar is dropped so there is exactly one nav component to maintain.
- The Quick-log `+` FAB stays, positioned above the pill nav.
- Settings remains the gear-button sheet on Today; it does not get a nav slot.
- Accessibility: each pill button gets a label and `isSelected` trait; hit targets ≥ 44pt; the pill respects safe areas and the keyboard.

### 3.2 Health tab layout

Top to bottom:

1. **Week strip** day picker (existing `WeekStrip`, restyled with per-day progress rings like the reference). Selecting a day scopes both segments, as the Body tab does today.
2. **Segmented control**: `Health | Fitness` (existing `SegmentedPill`, restyled).
3. Segment content (below).

### 3.3 Health segment (how the body is doing)

Order reflects morning-glance priority:

1. **Anomaly alert banner** — shown only when at least one vital deviates from baseline (Section 5). Red-tinted card naming the metric(s), e.g. "Resting HR is well above your 2-week baseline." Factual wording only; no medical advice, no "contact doctor."
2. **Recovery card** — recovery % hero with the existing colored `RecoveryBand`.
3. **Sleep card(s)** — duration, performance, efficiency, consistency, debt; sleep-stage composition for the selected night. Content currently in `RecoveryScreen`'s Sleep group + `WellnessSection`'s sleep verdict.
4. **Vitals card** — SpO2, skin temp, respiratory rate, resting HR, HRV, each with its delta-from-baseline (already computed today).
5. **Weight card** — hero kg, weekly delta, 14-day bar chart (the current `WeightSection`, restyled).
6. **Journal card** — last entries + "Write today" (moves from `WellnessSection`).
7. *(Project 2 will insert calories-today + meal cards at the top, under the banner.)*

### 3.4 Fitness segment (what the body did)

1. **Calories burnt card** — weekly rounded-bar chart in the reference's two-tone orange, with the week's total.
2. **Steps + active minutes tiles** — icon-bubble stat tiles.
3. **Strain card** — day strain, avg/max HR.
4. **Workouts list** — the per-workout rows from `ActivitySection` (strain, avg HR, distance, partial flag).
5. **Weekly training rollup** — workout days vs target, avg session (moves from `WellnessSection`).

### 3.5 Navigation depth

`WhoopDetailScreen` (14-day trend charts) stays reachable: from the Health segment via the recovery/sleep cards, from Fitness via the strain card. `TodayScreen`, `DayDetailSheet`, Money, and Plan keep their exact content and structure — restyle only.

## 4. Design system restyle

All changes happen **in place** in `LifeOSKit/Sources/DesignSystem/` — no parallel theme, so every tab flips at once and nothing drifts. The package's macOS-buildability constraint holds (no UIKit-only APIs).

### 4.1 Tokens (`Tokens.swift`)

- **Canvas:** warm near-white cream (light) / warm near-black gray (dark), via the existing `AdaptiveColor` pattern.
- **Cards:** white / elevated dark-gray surfaces, rounded-2xl (~24pt), very soft shadow (light mode only; dark mode uses surface contrast).
- **`ModuleHue` survives, demoted**: hues become pastel accent tints for icon bubbles, chart fills, and segment highlights instead of full-screen gradients. Each hue gains a `pastel`/`pastelDark` pair.
- **Accent** stays the warm orange; primary chart color follows the reference's two-tone orange (solid + ~25% tint).
- Alert tint: soft red background + strong red text, adaptive pair.
- Hero numerals: primary dark text on light (inverted from today's white-on-gradient).

### 4.2 Components

- `GradientCanvas` → flat canvas with at most a subtle per-module tint wash at the top. Keep the type name if that minimizes churn; drop the saturated gradients.
- `GlassCard` + `SolidCard` → consolidate into one **`SoftCard`** (white rounded card, soft shadow). Call sites migrate mechanically.
- **New components:** `PillNavBar` (floating tab pill), `IconBubbleTile` (pastel-circle icon + big number + caption), `RoundedBarChart` (weekly two-tone bars), `AlertBanner`, ring-progress day cell for `WeekStrip`.
- Restyled: `SegmentedPill`, `MetricTile`/`StatTile`, `HeroNumeral` (dark text variant), `MonthCalendarView` dots, FAB.
- `DotGrid` on Today keeps its role as the app's central visual claim, re-tinted for the light canvas.

### 4.3 Dark mode

Every new/changed color ships as an `AdaptiveColor` pair. Verification includes eyeballing all four tabs in both schemes.

## 5. Anomaly detection

Small, honest, and local — pure functions in the package:

- **Baseline:** trailing 14-day mean of each vital from `DailyMetrics`, excluding the selected day; a metric needs ≥ 7 non-nil days to have a baseline at all.
- **Thresholds (per metric, tuned later):** resting HR +10%, respiratory rate +8%, skin temp +1.0°C absolute, SpO2 −3 percentage points, HRV −30%.
- **No data → no banner.** A nil today-value or an insufficient baseline yields no evaluation, never a "normal" verdict. Consistent with the app-wide "a false zero is worse than a blank" rule.
- Output: `AnomalySnapshot` listing flagged metrics with today's value, baseline, and direction; the banner renders from it.
- Wording is descriptive ("well above your baseline"), never diagnostic or prescriptive.

## 6. Data flow and view models

- **No schema, sync, or persistence changes.** All screens keep rendering `Equatable` snapshot structs; view models keep owning the `ModelContext`; reloads stay event-driven off `ModelContext.didSave` + `scenePhase`.
- `BodyViewModel` → **`HealthViewModel`**, composing existing snapshot logic into `HealthSegmentSnapshot` and `FitnessSegmentSnapshot`, plus the new `AnomalySnapshot`. `ActivityViewModel`, `RecoveryViewModel`, `WellnessViewModel` logic is absorbed or delegated — whichever keeps files small; the snapshot-purity rule is the invariant, not the file layout.
- `BodySection` (4-case enum) → `HealthSection` (2-case: `.health`, `.fitness`).
- `RootView` swaps `TabView` chrome for `PillNavBar` and remains the single composition root.

## 7. Error handling and empty states

Unchanged in policy: missing metrics render as "—" or `HeroEmptyState` with a named reason; the Whoop-not-connected empty state moves up to the Health tab level ("Connect Whoop in Settings"). The anomaly banner simply absents itself without data (Section 5).

## 8. Testing

- **Unit (package, `swift test`):** anomaly baseline/threshold math — nil handling, insufficient-baseline, boundary values, direction; snapshot composition for the two segments.
- **Manual:** build and walk all four tabs + Health's two segments in light and dark, iPhone portrait and iPad, with Whoop connected and disconnected. Verify pill nav hit targets, FAB placement, and safe-area behavior with keyboard up.
- Existing package tests must stay green; call-site migrations (`GlassCard`→`SoftCard` etc.) are compile-verified.

## 9. Out of scope for this project

- Nutrition/meals (Project 2), notifications/check-in (Project 3), Cloud Run API (Project 0.5).
- HealthKit/Apple Watch ingestion (still future; Whoop remains the only live source).
- Any Supabase or sync-pipeline change.
- Workout plans or training content — Fitness shows real wearable data only (explicit brainstorming decision).

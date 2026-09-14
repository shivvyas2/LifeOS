# Daily health comparisons

## Product behavior

Groups compare **Effort**, **Recharge** and **Rest** for today or yesterday. All scores use the app’s 0–100 scale, with a provider label, measurement day and sync timestamp. Equal scores share a rank; missing or ineligible readings are unranked. The existing cream/orange visual language and shared system typography remain intact.

These are app-defined comparisons, not renamed proprietary WHOOP Strain, Recovery or Sleep Performance values. Personal goals and device measurement methods differ, so the screen explains the calculation rather than claiming physiological equivalence.

| Category | Calculation | Eligible inputs |
|---|---|---|
| Effort | Rounded active minutes / personal exercise-minute goal × 100, capped at 100 | Apple Health exercise time; WHOOP tracked workout duration; Fitbit fairly + very active minutes |
| Recharge | Clamp and round `50 + 100 × (0.6 × (HRV / usual HRV − 1) + 0.4 × (1 − resting HR / usual resting HR))` | Current HRV and resting heart rate plus at least 7 earlier distinct days within 28 days, all from the same provider |
| Rest | Rounded recorded sleep / personal sleep-minute goal × 100, capped at 100 | Apple Health, WHOOP or Fitbit sleep duration; Fitbit explicitly marked naps excluded |

“Usual” is the median of eligible prior days. Today never counts toward its own baseline. WHOOP calibration readings, invalid numbers, manually entered values and readings without supported provenance are excluded. Missing activity components from Fitbit are not assumed to be zero. A duplicate date cannot satisfy the seven-day requirement. Server dates are Gregorian local-day keys even when the device uses another calendar.

Recharge is an app estimate of signals relative to a personal baseline, not a recovery percentage, clinical assessment or vendor readiness score. Effort is activity-goal progress, an activity-load proxy rather than an intensity/heart-rate-zone strain calculation. Exceeding activity or sleep goals earns no extra points.

## Data flow and consent

- Existing account-scoped DailyMetrics and MetricArbiter choose one source per metric. Provider totals are never added together.
- Fitbit sync now fetches two activity range collections and merges their complete paired values into exerciseMinutes. Successfully fetched collections survive quota-retry responses.
- RootView republishes eligible scores following provider-state changes only after checking for a group with explicit health-score consent. Opening the social hub and enabling sharing also publish snapshots. Older observations cannot overwrite fresher server rows.
- New `shares_wellness` consent defaults off independently of the earlier streak/activity-sharing setting. It is controlled per group and takes effect immediately on leaderboard reads.
- Only derived scores, sources, day and observation time are shared; raw HRV, heart rate and sleep duration are not uploaded by this leaderboard endpoint.
- Backend writes always use auth.uid(). Nonmembers and invitees cannot read rankings; raw daily score rows are visible only to their account owner. Profile activity sharing remains a separate feature.

## Verification

- Native app build passed: `/private/tmp/lifeos-wellness-build.log`.
- Full Swift suite: **1,199 tests in 156 suites passed**: `/private/tmp/lifeos-wellness-tests.log`.
- Fitbit helper tests: **10 passed**, plus `deno check` for the sync function.
- Backend: **23 new assertions** plus **43 group/chat regression assertions** passed in rolled-back fixture transactions. Covers fresh consent, per-group isolation, date filtering, ties across sources, valid zero versus missing, score/source bounds, stale-device writes and anonymous access denial.
- Linked database lint passed. Additive migration `20260914110000_group_wellness_leaderboards.sql` applied; updated `fitbit-sync` function deployed with its existing JWT-verification behavior preserved.
- iPhone/iPad previews saved as `wellness-leaderboard-*.png`; Recharge selection and explanation were opened through the simulator UI. Sample-only fixtures were used; live three-provider accounts were not linked or exercised during verification.
- App source remains local and unpushed. Backend deployment is complete.

## API references

WHOOP exposes its own cycle, recovery and sleep scores and their underlying measurements in its [official API](https://developer.whoop.com/api/). Those proprietary scores are kept separate from these app comparisons.

Apple Health records HRV using SDNN, so raw HRV is not compared directly against another provider’s HRV values. See [Apple’s HRV documentation](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn).

Fitbit’s [official API explorer](https://dev.fitbit.com/build/reference/web-api/explore/) documents activity range requests; its [data dictionary](https://enterprise.fitbit.com/wp-content/uploads/Fitbit-Web-API-Data-Dictionary-Downloadable-Version-2023.pdf) lists fairly/very-active minute resources. The existing Fitbit activity scope covers these requests.

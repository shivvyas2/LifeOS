# Changelog

All notable changes to Almanac are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- **Badminton demo.** Try the demo from the badminton start screen or the empty history: a scripted doubles match plays through the live screen with simulated Watch data, scores its own rallies, and ends in the real court review. Nothing from it is saved.
- **Swing analysis status.** The start screen says whether the next badminton workout will analyze swings, and if not, the one setting to change.
- **Past sessions.** Badminton history groups motion reviews from summaries and says why a summary has no motion: still waiting for the Watch, motion that could not be read, recorded on iPhone, or imported. The saved screen opens the session just finished rather than the list.

### Fixed

- **Swing analysis on phone-started workouts.** The phone now sends its athlete profile to the Watch with the workout it starts, so a Watch that never received the profile, or holds an older one, adopts it and begins analyzing swings instead of silently recording none.
- **The tab bar no longer sits on top of the keyboard.** While typing on a phone the bar steps out of the way and the page runs down to the keys; it returns when the keyboard closes.

## [1.0.1] - 2026-10-05

The editorial redesign and badminton match tracking.

### Added

- **Badminton matches.** Score a match on the watch or the phone with a rules-exact scoring engine. When a rally goes quiet the watch asks who won, and a double tap scores the point. The match carries through sync and storage.
- **Badminton review.** Tag shots in the session review and compare the two sides. The review measures forearm twist, learns your forehand from the tags, splits short and long serves and estimates them, and replays every swing on a player figure, animated shot by shot from any side.
- **Live readings.** Activity shows where each live reading comes from and what it means.
- **Watch.** Start a workout without setup and sync without a button, with activity HUDs and durable workout sync.

### Changed

- **Editorial design.** An editorial layer across the app: every tab labeled, a single accent, one button style, and gradient fields in place of the module pastels.
- **Money.** The Money tab rebuilt as an editorial page.
- **Health.** Health, activity and the Live Activity restyled as one.
- **Badminton review** follows light and dark mode.
- **Watch** glass overlays share the activity palettes, and activity gradients extend behind navigation.

### Fixed

- Watch sync reply handlers no longer trap off the main actor.
- The phone keeps in step when the watch goes away.
- A badminton workout is kept when its swing review fails checks, and the 3D replay is cheap and crash-safe.
- Stray test files removed from the app target.

## [1.0.0] - 2026-09-28

The first public release. Almanac started as Life OS on 10 August 2026 and reached this point in about seven weeks and 640 commits. Everything below is what the app does today.

### Added

- **Today.** One page per day joining sleep, recovery, strain, steps, weight, and the plan, with a page of its own for every metric.
- **Health.** Apple Health as the primary source, Whoop and Fitbit through OAuth with tokens that never leave the device or the Edge Function, and a Renpho scale through Health. Recovery band and sleep composition views.
- **Activity.** A live session recorder with heart-rate zones from age, estimated effort, capacity and push state, a glass HUD, sensors that reconnect on their own, and a gradient Live Activity. Full activity catalog with recents and a searchable picker. iPad layouts in both orientations.
- **Apple Watch.** A watch app that runs and mirrors a session from the wrist, counts reps from wrist acceleration, corrects a rep, recovers an active workout, and starts any catalog activity. Watch complications.
- **Workouts.** A curated, verified video library with today's plan, bookmarks, search, scheduling, and full screen or landscape playback with a movable HUD.
- **Money.** Bank accounts and transactions through Plaid, including OAuth banks via a universal link, with merchant logos, categories, weekly and monthly spend, a donut of shares, and pages for each category and merchant. Amounts carry exact cents.
- **Notes.** A notes library that opens as a Liquid Glass drawer beside the phone's stack.
- **Calendar.** EventKit calendars on Today and an agenda widget with a week strip and rolling next events.
- **Coach.** Text and voice screens around a glowing orb, backed by an Edge Function that calls Claude, with the voice leading and cards following.
- **Life board and social.** Nine life sectors with a planner, groups, a leaderboard, and wellness scores under Row Level Security.
- **Widgets.** Home and Lock Screen widgets on a shared periwinkle palette, and a Lock Screen live session.
- **Design system.** `LifeOSKit/DesignSystem` with tokens, a nine-step type scale, and a typography guard script. The Almanac logo as vectors, PNG exports, and an in-app `AlmanacMark` view.
- **Backend.** A Supabase project with 18 migrations, 12 Edge Functions for OTP sign-in, Whoop, Fitbit, Plaid, the coach, and nudges, and SQL policy tests.
- **Handbook.** A 24-chapter engineering handbook as PDF, EPUB, and HTML.
- **Open source.** MIT license, contributing guide, code of conduct, security policy, issue and pull request templates, and CI that runs the package tests, an app build, the Deno tests, and a secret scan.

[Unreleased]: https://github.com/shivvyas2/LifeOS/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/shivvyas2/LifeOS/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/shivvyas2/LifeOS/releases/tag/v1.0.0

# Changelog

All notable changes to Almanac are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/shivvyas2/LifeOS/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/shivvyas2/LifeOS/releases/tag/v1.0.0

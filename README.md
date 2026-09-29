<p align="center">
  <img src="docs/brand/exports/almanac-icon-512.png" width="128" alt="Almanac">
</p>

<h1 align="center">Almanac</h1>

<p align="center">A local-first life OS for iPhone and Apple Watch. Health, activity, money, notes, calendar, and a coach, joined on one row per day.</p>

<p align="center"><a href="docs/handbook/Almanac-Engineering-Handbook.pdf">Read the engineering handbook</a> · <a href="https://github.com/shivvyas2/LifeOS/releases/latest">Latest release</a> · <a href="CONTRIBUTING.md">Contribute</a></p>

<p align="center">
  <a href="https://github.com/shivvyas2/LifeOS/actions/workflows/ci.yml"><img src="https://github.com/shivvyas2/LifeOS/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT"></a>
  <img src="https://img.shields.io/badge/iOS-26-black.svg" alt="iOS 26">
  <img src="https://img.shields.io/badge/Swift-6-orange.svg" alt="Swift 6">
</p>

Almanac is built on one bet: the value is in the join, not the collection. Seven sources feed it, everything lands in a SwiftData store on the device, and every screen reads from that store before anything touches the network. The backend is a Supabase project with Postgres, Row Level Security, and a dozen Edge Functions. The app is free and the code is MIT.

## What it does

- **Today.** One page per day with sleep, recovery, strain, steps, weight, and the plan. Tap any metric for its own page and history.
- **Health and body.** Apple Health in, Whoop and Fitbit through OAuth, a Renpho scale through Health. Recovery and sleep composition views.
- **Activity and workouts.** A live session recorder with heart-rate zones, effort, glass HUD, Live Activity, and a Watch companion that mirrors the session and counts reps from wrist motion. A curated, verified workout video library.
- **Money.** Bank accounts and transactions through Plaid, with merchant logos, categories, weekly and monthly spend, and a donut of shares.
- **Notes and calendar.** A notes library in a drawer, EventKit calendars, and an agenda widget with a week strip.
- **Coach.** A text and voice coach with a glowing orb, backed by an Edge Function that calls Claude. The cost ceiling is a design constraint: the whole backend is meant to stay under a couple of dollars per user per month.
- **Life board and social.** Nine life sectors with a planner, groups, and a leaderboard.
- **Widgets and Watch.** Home and Lock Screen widgets, a watch app with its own widgets, and a live session on the wrist.

## Requirements

| Tool | Version | Needed for |
| --- | --- | --- |
| Xcode | 26.3 | The app, widgets, and watch targets |
| iOS / watchOS | 26.0 | Deployment target |
| macOS | 26.0 | Running the package tests on the Mac |
| Deno | 2.x | Edge Function tests and the catalog verifier |
| Supabase CLI | latest | Only if you run the backend |

## Quick start

```sh
git clone https://github.com/shivvyas2/LifeOS.git
cd LifeOS
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
open LIfeOS.xcodeproj
```

Pick the `LIfeOS` scheme and an iPhone simulator, then build and run. The secrets file is gitignored and can stay empty. Every integration checks its own keys and stays switched off until you fill them in, so the on-device parts work with no backend at all.

To run the package tests without Xcode's UI:

```sh
cd LifeOSKit && swift test
```

## Connecting a backend

Sign-in, the coach, money, social, and wearable sync need a Supabase project. Create one, then:

1. Put the project URL and anon key in `Config/Secrets.xcconfig`. The anon key is designed to ship in clients; Row Level Security gates every row.
2. Apply the migrations and deploy the functions:

   ```sh
   supabase link --project-ref <your-ref>
   supabase db push
   supabase functions deploy
   ```

3. Set the real secrets on the functions, never in the repo:

   ```sh
   supabase secrets set ANTHROPIC_API_KEY=... WHOOP_CLIENT_SECRET=... FITBIT_CLIENT_SECRET=... PLAID_CLIENT_ID=... PLAID_SECRET=...
   ```

Each integration is optional. Leave a key blank and that connection does not appear in Settings. Whoop, Fitbit, and Plaid each need their own developer account and redirect URI; `Config/Secrets.example.xcconfig` documents each one.

## Project layout

```
LIfeOS/               The iOS app. Features/<Name>/{Model,View,ViewModel}
LifeOSKit/            Swift package with eight modules and the tests
  Sources/DesignSystem     Tokens, type scale, shared components, the logo
  Sources/Persistence      SwiftData models, one row per day
  Sources/Integrations     HealthKit, Whoop, Fitbit, Plaid, Supabase clients
  Sources/Insights         Derived metrics, effort, zones
  Sources/Sectors          The nine-sector life board and planner
  Sources/Assistant        The coach
  Sources/Motion           Rep counting from wrist acceleration
  Sources/AppSurfaces      Wire types shared with widgets and the watch
AlmanacWidgets/       Home, Lock Screen, and Live Activity widgets
AlmanacWatch/         The watch app
AlmanacWatchWidgets/  Watch complications
supabase/             Migrations, Edge Functions, SQL tests
scripts/              The typography guard and the workout catalog verifier
docs/handbook/        The engineering handbook, as PDF, EPUB, and HTML
docs/brand/           Logo, wordmark, exports, and brand rules
docs/superpowers/     Design specs and implementation plans, one per feature
web/                  The static site behind the Plaid OAuth redirect
```

The module graph is compiler-enforced. `Persistence` knows nothing about the network, `Integrations` depends on it, and the app depends on all of them. If a change needs an arrow in the other direction, that is the design telling you something.

## The handbook

<a href="docs/handbook/Almanac-Engineering-Handbook.pdf"><img src="docs/handbook/cover.jpg" width="160" align="right" alt="Almanac Engineering Handbook cover"></a>

The Almanac Engineering Handbook is the long-form description of the system in 24 chapters: the architecture, every data source and the door it comes through, the coach, the widgets, the watch, money, and how releases go to TestFlight. Read it before a large change.

- [PDF](docs/handbook/Almanac-Engineering-Handbook.pdf) and [EPUB](docs/handbook/Almanac-Engineering-Handbook.epub) in the repo
- Downloads on the [latest release](https://github.com/shivvyas2/LifeOS/releases/latest)
- Source chapters in `docs/handbook/src/chapters/`, built with `build.py`, `render-pdf.sh`, and `pack-epub.py`

Where the code and the handbook disagree, the code is right and the handbook has a bug. Please file it.

<br clear="all">

## Tests

| Command | Runs | Where |
| --- | --- | --- |
| `cd LifeOSKit && swift test` | 1,300+ unit tests across the eight modules | Mac or CI |
| `cd supabase/functions && deno test --allow-env --allow-read` | Edge Function tests | Anywhere with Deno |
| `cd scripts/catalog && deno test` | Workout catalog verifier | Anywhere with Deno |
| `zsh scripts/check-typography.sh` | Lists fonts set outside the type scale. Advisory in CI while a few known violations remain | Mac |
| `supabase test db` | SQL policy tests | Needs the local Supabase stack |

CI runs the first four on every push and pull request, plus a secret scan of the history.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) for how the repo works: one branch per change, conventional commits, a design note for anything larger than a fix, and the tests above before you open a pull request. Security issues go through [SECURITY.md](SECURITY.md), not the issue tracker.

## Privacy

Health, money, and notes are personal. The app keeps everything on the device first and syncs only what a feature needs to a Supabase project you control. Real secrets live only in Edge Function environments. There is no analytics SDK, no ad SDK, and no third-party crash reporter.

## License

[MIT](LICENSE). The workout catalog links to videos owned by their creators; the catalog itself is data, not a redistribution.

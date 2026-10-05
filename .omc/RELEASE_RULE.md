# Release Rules
<!-- last-analyzed: 2026-10-05T18:00:00Z -->

## Version Sources
- `LIfeOS.xcodeproj/project.pbxproj`: `MARKETING_VERSION = X.Y.Z;` (8 occurrences, one per target and configuration; bump all with one sed) and `CURRENT_PROJECT_VERSION = N;` (8 occurrences, the build number, bump by one per TestFlight upload).
- `CHANGELOG.md`: the `## [X.Y.Z] - YYYY-MM-DD` heading and the compare links at the bottom.
- No release automation script. `LifeOSKit/Package.swift` carries no version; it is a local package.

## Release Trigger
- Push of an annotated tag `vX.Y.Z` to GitHub runs `.github/workflows/release.yml`.

## Test Gate
- `cd LifeOSKit && swift test` (1,316 tests). Runs in `ci.yml` job `kit` and again in `release.yml` before the release is created.
- `deno test` in `supabase/functions` and `scripts/catalog`, `ci.yml` job `deno`.
- Simulator build of the app with blank secrets, `ci.yml` job `app`.
- `gitleaks` history scan, `ci.yml` job `secrets`.
- `scripts/check-typography.sh` is advisory (continue-on-error) until the known violations are cleared.

## Registry / Distribution
- No package registry. Distribution is the App Store and TestFlight through Xcode, by hand; see `docs/handbook/testflight-release.md`.
- The GitHub Release carries the engineering handbook PDF and EPUB from `docs/handbook/` as assets.

## Release Notes Strategy
- Keep a Changelog in `CHANGELOG.md`, written by hand from `git log <prev>..HEAD --no-merges --format=%s` grouped by conventional-commit type and feature scope.
- `release.yml` extracts the matching `## [X.Y.Z]` section as the release body.

## CI Workflow Files
- `.github/workflows/ci.yml`
- `.github/workflows/release.yml`

## TestFlight / App Store Connect Upload
- Bump `CURRENT_PROJECT_VERSION` (all 8) before every upload; the number must match across the iPhone app, widgets, watch app and watch widgets, and `MARKETING_VERSION` must match too, or App Store Connect drops the watch app.
- Archive and upload from the CLI: `xcodebuild archive -scheme LIfeOS -destination 'generic/platform=iOS' -archivePath <path> -allowProvisioningUpdates`, then `xcodebuild -exportArchive -archivePath <path> -exportOptionsPlist <plist with method app-store-connect, destination upload, teamID Z42YU5W6WY> -allowProvisioningUpdates`.
- The checkout used to archive must be at origin/main; on 2026-10-05 a stale local main shipped build 48 without the 20 commits of UI work.

## Release Steps
1. Move `## [Unreleased]` items into a new `## [X.Y.Z] - date` section and update the links.
2. `sed -i '' 's/MARKETING_VERSION = OLD;/MARKETING_VERSION = NEW;/g' LIfeOS.xcodeproj/project.pbxproj`
3. `cd LifeOSKit && swift test`
4. Commit `chore(release): vX.Y.Z`, merge to main.
5. `git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin main vX.Y.Z`
6. Watch `gh run list --workflow=release.yml`, then `gh release view vX.Y.Z`.

## First-Time Setup Gaps
- Resolved on 2026-09-28: no tags, no CI, no changelog, no release workflow. Build artifacts were already gitignored.

# Shipping Life OS to TestFlight

Everything the repo can settle is already settled. This covers the parts that
need your Apple ID, and the two things that will bite you if you forget them.

## What the project already declares

| Setting | Value | Where |
| --- | --- | --- |
| Display name | `Life OS` | `INFOPLIST_KEY_CFBundleDisplayName` |
| Bundle ID | `com.shivvyas.lifeos` | `PRODUCT_BUNDLE_IDENTIFIER` |
| Team | `Z42YU5W6WY` | `DEVELOPMENT_TEAM` |
| Minimum iOS | `26.0` | `IPHONEOS_DEPLOYMENT_TARGET` + `LifeOSKit/Package.swift` |
| Version / build | `1.0` / `1` | `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` |
| Export compliance | declared exempt | `ITSAppUsesNonExemptEncryption` |

The Xcode target is still named `LIfeOS` with the capital `I`. That is
deliberate: renaming the target churns the project file for no user-visible
gain, and nobody outside this repo ever sees it. `CFBundleDisplayName` is what
appears under the home screen icon, and that reads `Life OS`.

## One time, before the first upload

The bundle ID is already registered on the developer portal. Xcode's automatic
signing did it during the first archive, so there is nothing to do at
developer.apple.com.

What is left is the App Store Connect record:

1. App Store Connect → **Apps** → **+** → **New App**
2. Platform iOS, Name `Life OS`, Primary Language, Bundle ID
   `com.shivvyas.lifeos`, SKU anything stable (`lifeos-ios` works)
3. Create

If the name `Life OS` is taken, App Store Connect rejects it here. That blocks
only the public listing, never TestFlight: pick any unique placeholder name to
create the record, and the home screen still reads `Life OS` because that comes
from the bundle, not the listing.

## Every upload

**Bump the build number first, and commit it.** App Store Connect rejects a
`(version, build)` pair it has already seen, and it rejects it *after* the
upload finishes, which wastes the whole round trip. Bump
`CURRENT_PROJECT_VERSION` in both the Debug and Release configurations:

```
MARKETING_VERSION       1.0   → user-facing, bump for real releases
CURRENT_PROJECT_VERSION 17    → bump for EVERY upload, even a re-upload
```

Committing it is the part that was being skipped. Through build 15 the number
in git never moved off 1, because each archive was made from an edit that was
never committed, so nothing in the repository could answer "what did we upload
last?" and every archive was a guess. The number here is the last build that
reached App Store Connect. Raise it, commit, then archive, and the guess goes
away.

A rejected upload still burns the number. If a build fails validation, bump
again rather than re-uploading the same one.

Then, in Xcode:

1. Destination → **Any iOS Device (arm64)**. Archive is disabled for simulators.
2. **Product → Archive**
3. In Organizer: **Distribute App** → **TestFlight & App Store Connect**
4. Accept automatic signing. Xcode re-signs with the Apple Distribution identity;
   the Apple Development identity used for a local archive is not the one that
   ships.
5. Upload, then wait. Processing takes a few minutes, and TestFlight shows the
   build as unavailable until it finishes.

Internal testers (up to 100, on your own team) get the build immediately with no
review. External testers require a Beta App Review on the first build.

## The one real trap: Secrets.xcconfig

`Config/Secrets.xcconfig` is the base configuration for both Debug and Release,
and it is gitignored. It holds the Supabase URL and anon key, the Whoop client
ID, and the Whoop redirect URI.

A clean checkout has no such file. It still **builds and archives without
error**. xcconfig substitution of a missing variable yields an empty string, not
a failure. The result is an app that launches, shows the signup screen, and can
never sign anyone in.

So: before archiving on any machine that is not this one, confirm the file
exists and is populated. `Config/Secrets.example.xcconfig` is the template.

None of those four values is a true secret. Real secrets (the Supabase
service-role key, `WHOOP_CLIENT_SECRET`, `ANTHROPIC_API_KEY`) live only in the
Supabase Edge Function environment.

## Regenerating the app icon

Sources are in `docs/brand/`:

- `lifeos-icon.svg`: the square artwork the app actually ships
- `lifeos-icon-squircle-original.svg`: the original, kept for reference

The original clips its artwork to a squircle, which leaves the corners
transparent. iOS applies its own mask and requires an opaque, full-square,
1024×1024 image, so the shipping SVG has that `clip-path` removed and lets the
background gradient run to the edges. An icon with an alpha channel is rejected
at validation.

To re-render after editing the SVG:

```sh
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless --disable-gpu --force-device-scale-factor=1 --hide-scrollbars \
  --screenshot=icon-1024.png --window-size=1024,1024 \
  "file://$PWD/docs/brand/lifeos-icon.svg"

cp icon-1024.png LIfeOS/Resources/Assets.xcassets/AppIcon.appiconset/
```

Confirm it stayed opaque before committing. `hasAlpha` must read `no`:

```sh
sips -g pixelWidth -g pixelHeight -g hasAlpha \
  LIfeOS/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
```

## Warnings that are not failures

**"The archive did not include a dSYM for the LinkKit.framework."** Expected,
and nothing to fix here. Plaid ships `LinkKit.xcframework` with no dSYMs in any
slice, so there is nothing for the archive to include. The upload still
processes and the build still reaches TestFlight; the only cost is that crash
reports cannot symbolicate frames inside Plaid's own code. Ours symbolicate
normally.

Do not try to silence it by turning off `DEBUG_INFORMATION_FORMAT` or by
stripping symbols: that would trade a cosmetic warning for unsymbolicated
crash reports in the app's own code.

## Auth emails send a code, not a link

Sign-in is a six-digit code. Supabase's stock templates send a magic *link*
instead, and a link cannot be typed into an app, so signup dead-ends at
"check your email" with nothing to enter. Worse, the link points at whatever
`site_url` the project holds, which lands on a page unrelated to the app.

`supabase/templates/` holds the templates that fix this, and
`supabase/config.toml` points at them. **Both only apply to `supabase start`.**
The hosted project reads its templates from the dashboard, and neither
`supabase db push` nor a function deploy carries them across.

To change them on the hosted project, paste the contents of
`supabase/templates/magic_link.html` and `confirmation.html` into
**Authentication → Emails** in the dashboard, as the Magic Link and Confirm
Signup templates. GoTrue picks between them by whether it has seen the address
before, so both are needed; either one still sending `{{ .ConfirmationURL }}`
brings the magic link back for half the users.

**Do not run `supabase config push` to do it.** It pushes the whole `[auth]`
block, which in this repo means a localhost `site_url` and an SMTP section
whose `RESEND_API_KEY` is unset locally. That combination would stop every auth
email being delivered, which is a considerably worse failure than the one being
fixed.

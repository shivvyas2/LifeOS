# Contributing to Almanac

Thanks for looking. This is a personal app that grew a real architecture, and it is easier to contribute to than it looks, as long as you follow the few rules below. They exist because each one was learned the hard way.

## Before you start

- **Open an issue first for anything bigger than a fix.** Say what you want to change and why. Features here start as a short design note in `docs/superpowers/specs/`, and it is much cheaper to agree on the note than on a finished pull request.
- **Check the handbook chapter** for the area you are touching. `docs/handbook/index.html` opens it in a browser. It explains why the code is shaped the way it is.
- **Set up as in the README.** The app builds with an empty `Config/Secrets.xcconfig`, so you do not need a backend to work on most of it.

## How the repo works

**One branch per change.** Never commit to `main`. Branch from it, open a pull request, and let CI run.

**Conventional commits.** `feat(activity): ...`, `fix(money): ...`, `docs(handbook): ...`, `test(...)`, `refactor(...)`, `chore(...)`. The scope is the feature folder or the module. The subject is a sentence in plain words about what changed for the user, not what you did to the code.

**No em dashes.** In code comments, commit messages, docs, and UI strings. Use a comma, a period, or a colon.

**The type scale is the only type.** Every font comes from `LifeOSType` in `LifeOSKit/Sources/DesignSystem/Typography.swift`. `scripts/check-typography.sh` fails the build if you set a font any other way. If the scale is missing a step, add it there, on purpose, in its own commit.

**SwiftData fields need defaults.** A new field on an existing `@Model` must be optional or have a default value, or installed stores refuse to open and the app hangs on the spinner. This has bitten us more than once.

**Modules point one way.** `Persistence` knows nothing about the network. `Integrations` depends on `Persistence`. The app depends on the modules. Widgets and the watch talk to the app only through `AppSurfaces` wire types. If your change needs an import in the other direction, stop and open an issue.

**Secrets never enter the repo.** Not in code, not in docs, not in a test fixture. `Config/Secrets.xcconfig` is gitignored and holds only client-safe values. Real secrets live in Supabase Edge Function environments. CI runs a secret scan on every pull request.

## Tests

Run these before you push. They are what CI runs.

```sh
cd LifeOSKit && swift test
cd supabase/functions && deno test --allow-env --allow-read
cd scripts/catalog && deno test
zsh scripts/check-typography.sh
```

New logic goes in `LifeOSKit` with a test beside it. The app target holds views and view models; pure computation belongs in a module where `swift test` can reach it in under two seconds. Write the failing test first when you can. It keeps the change small.

## Pull requests

- Keep one change per pull request. A refactor and a feature are two pull requests.
- Fill in the template. Say what changed, why, and how you verified it. A screenshot or a short recording for anything visual.
- Update the handbook chapter or the design note if behaviour changed. The handbook is built from `docs/handbook/src/chapters/` with `build.py`.
- Expect review comments about naming and about whether the change belongs in the app or in a module. Those are the two questions that keep this codebase workable.

## Design and visual work

The app's look is deliberate: cream surfaces, ink text, one orange, native system sans, rounded numerals. Read `docs/brand/README.md` before touching the logo and `LifeOSKit/Sources/DesignSystem/Tokens.swift` before adding a colour. If a screen needs a new colour, that is a conversation, not a commit.

## Code of conduct

Be kind and be direct. See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

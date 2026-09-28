# Almanac brand

The Almanac logo is the app icon: three stacked isometric leaves, plum under red under glass, with a dark orb and a small crescent ring on top, on an orange gradient tile. Everything in this folder is derived from that one drawing so the website, the App Store, social previews and the in-app views all show the same thing.

The App Store icon itself stays `LIfeOS/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`. That PNG is the original render and is kept as the source of truth for the icon. The SVGs here are a vector rebuild of it, close enough to sit beside it, and are what you use everywhere else.

## Files

| File | Use it for |
| --- | --- |
| `almanac-icon.svg` | The squircle tile. Website header, favicons, social avatars, anywhere the logo stands alone. |
| `almanac-icon-square.svg` | Same tile with square corners. For places that apply their own mask, such as Xcode and Apple touch icons. |
| `almanac-mark.svg` | The stack alone on a transparent background. Use over photos, on coloured backgrounds, and in lockups you build yourself. |
| `almanac-mark-mono.svg` | Single-colour stack. Tint it with `currentColor`. For watermarks, print, and dark or light one-colour contexts. |
| `almanac-wordmark-ink.svg`, `-cream.svg`, `-orange.svg` | "Almanac" set in Inter Display SemiBold, converted to outlines. Ink on light, cream on dark, orange as an accent. |
| `almanac-lockup-horizontal-ink.svg`, `-cream.svg` | Tile left of the wordmark. The default logo for the website and email footers. |
| `almanac-lockup-stacked-ink.svg`, `-cream.svg` | Tile above the wordmark. For square spaces such as splash screens and social cards. |
| `exports/` | PNGs of every SVG at several widths, plus `favicon-32/64/192.png`, `apple-touch-icon-180.png`, `og-image-1200x630.png`, and the original icon render `app-icon-original-1024.png`. |
| `legacy/` | The earlier LifeOS compass mark. Not used any more. |
| `source/` | The generator. `npm install && npm run build` regenerates every SVG and PNG. Needs Node and Google Chrome. |

In the app, use `AlmanacMark` from the `DesignSystem` module rather than an image. It draws the same geometry from shapes, scales to any size, and its `.mono` style follows `foregroundStyle`.

## Colours

| Name | Hex | Where |
| --- | --- | --- |
| Ink | `#141210` | Wordmark on light backgrounds, mono mark |
| Cream | `#fbf5ee` | Wordmark on dark backgrounds, light page backgrounds |
| Orange | `#f45b2e` | Accent wordmark, links, the app's accent |
| Tile gradient | `#ffd23f` to `#ff6a10` to `#e93905` to `#b04d14` | Top left to bottom right of the tile |
| Plum | `#640820` | Bottom leaf |
| Red | `#e2453b` to `#b8161c` | Middle leaf |
| Glass | white at 50% to 22% | Top leaf |
| Orb | `#5a0f22` with a `#8a3a45` highlight | The orb |
| Ring | `#fff0d8` | Orb ring and crescent ring |

## Type

The wordmark is Inter Display SemiBold with letter spacing of -0.03 em. On the website load "Inter Tight" from Google Fonts for headings that sit near the logo; it is the same design. In the app, type stays the system sans, as `LifeOSType` documents. Never set the word "Almanac" in a serif or in a rounded face next to the mark.

## Rules

- Clear space around the tile or lockup is at least the height of the orb ring, which is about a quarter of the tile's height.
- Do not use the tile smaller than 16 px or the transparent mark smaller than 24 px. Below that the leaves merge. At 16 px use the tile; the gradient carries the recognition.
- Do not recolour the tile, rotate the stack, add a drop shadow, or put the tile on an orange background. On orange, use the mono mark in cream.
- Do not stretch the lockups. Scale them proportionally.
- The tile already has the squircle. Do not put it inside another rounded rectangle.

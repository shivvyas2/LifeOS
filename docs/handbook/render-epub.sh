#!/usr/bin/env bash
# Rasterize the Kindle cover and pack Almanac-Engineering-Handbook.epub.
#
# Cover source of truth is cover.svg (1600×2560). Chromium screenshots it to
# JPEG; pack-epub.py then splits index.html into one XHTML file per chapter
# and packs them with that JPEG, a navigation document and an NCX into a
# Kindle-sendable EPUB 3 with the author and cover set.
#
# Usage:  ./docs/handbook/render-epub.sh      (run build.py first)

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHROME="${CHROME:-$HOME/Library/Caches/ms-playwright/chromium-1228/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing}"

if [[ ! -x "$CHROME" ]]; then
  echo "Chrome for Testing not found at:" >&2
  echo "  $CHROME" >&2
  echo "Set CHROME to a Chromium binary, or run the PDF renderer once to cache Playwright's." >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Inline the SVG so headless Chrome does not have to fetch a second file:// URL.
{
  printf '%s\n' '<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;padding:0;width:1600px;height:2560px;background:#EFEDE8;overflow:hidden}svg{display:block}</style></head><body>'
  cat "$HERE/cover.svg"
  printf '%s\n' '</body></html>'
} > "$WORK/cover.html"

echo "Rasterizing cover…"
"$CHROME" \
  --headless=new \
  --disable-gpu \
  --hide-scrollbars \
  --no-first-run \
  --no-default-browser-check \
  --force-device-scale-factor=1 \
  --window-size=1600,2560 \
  --default-background-color=EFEDE8FF \
  --screenshot="$WORK/cover.png" \
  "file://$WORK/cover.html" >/dev/null

PNG_BYTES="$(wc -c < "$WORK/cover.png" | tr -d ' ')"
if (( PNG_BYTES < 80000 )); then
  echo "Cover screenshot looks empty (${PNG_BYTES} bytes). SVG probably did not paint." >&2
  exit 1
fi

sips -s format jpeg -s formatOptions 90 -z 2560 1600 "$WORK/cover.png" --out "$HERE/cover.jpg" >/dev/null
echo "Cover JPEG written: $HERE/cover.jpg ($(wc -c < "$HERE/cover.jpg" | tr -d ' ') bytes)"

python3 "$HERE/pack-epub.py"

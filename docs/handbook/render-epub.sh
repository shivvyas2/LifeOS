#!/usr/bin/env bash
# Rasterize the Kindle cover and pack Life-OS-Engineering-Handbook.epub.
#
# Cover source of truth is cover.svg (1600×2560). Chromium screenshots it to
# JPEG; Python then wraps index.html + that JPEG into a Kindle-sendable EPUB.
#
# Usage:  ./docs/handbook/render-epub.sh

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

python3 - "$HERE" <<'PY'
import datetime, io, re, sys, zipfile
from pathlib import Path

from bs4 import BeautifulSoup
from bs4.dammit import EntitySubstitution
from bs4.formatter import XMLFormatter

here = Path(sys.argv[1])
html = (here / "index.html").read_text(encoding="utf-8")
cover_jpg = (here / "cover.jpg").read_bytes()

soup = BeautifulSoup(html, "html.parser")
if soup.html is None:
    raise SystemExit("index.html has no <html> root")
soup.html["data-theme"] = "light"
soup.html["xmlns"] = "http://www.w3.org/1999/xhtml"
soup.html["xml:lang"] = "en"

chapter = soup.decode(
    formatter=XMLFormatter(entity_substitution=EntitySubstitution.substitute_xml)
)
if not chapter.lstrip().startswith("<?xml"):
    chapter = '<?xml version="1.0" encoding="UTF-8"?>\n' + chapter

# XML escaping turns CSS child combinators into &gt;, which Kindle then
# treats as literal text and drops the two-column contents layout.
def restore_css(match: re.Match[str]) -> str:
    css = (
        match.group(1)
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&amp;", "&")
    )
    return "<style>" + css + "</style>"

chapter = re.sub(r"<style>(.*?)</style>", restore_css, chapter, count=1, flags=re.S)

modified = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

cover_xhtml = """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
  <title>Cover</title>
  <style type="text/css">
    html, body { margin: 0; padding: 0; background: #EFEDE8; }
    img { width: 100%; height: auto; }
  </style>
</head>
<body>
  <img src="cover.jpg" alt="Life OS Engineering Handbook"/>
</body>
</html>
"""

nav_xhtml = """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="en" lang="en">
<head><title>Contents</title></head>
<body>
  <nav epub:type="toc" id="toc">
    <h1>Contents</h1>
    <ol>
      <li><a href="cover.xhtml">Cover</a></li>
      <li><a href="handbook.xhtml">Life OS Engineering Handbook</a></li>
    </ol>
  </nav>
  <nav epub:type="landmarks">
    <ol>
      <li><a epub:type="cover" href="cover.xhtml">Cover</a></li>
      <li><a epub:type="bodymatter" href="handbook.xhtml">Handbook</a></li>
    </ol>
  </nav>
</body>
</html>
"""

opf = f"""<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid" version="3.0" xml:lang="en">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">urn:uuid:6e1f0c8a-4b2d-4f91-9e3a-25a825082026</dc:identifier>
    <dc:title>Life OS Engineering Handbook</dc:title>
    <dc:creator>Shiv Vyas</dc:creator>
    <dc:language>en</dc:language>
    <dc:date>2026-08-25</dc:date>
    <dc:publisher>Life OS</dc:publisher>
    <meta property="dcterms:modified">{modified}</meta>
    <meta name="cover" content="cover-image"/>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="cover-image" href="cover.jpg" media-type="image/jpeg" properties="cover-image"/>
    <item id="cover" href="cover.xhtml" media-type="application/xhtml+xml"/>
    <item id="chap" href="handbook.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="cover"/>
    <itemref idref="chap"/>
  </spine>
  <guide>
    <reference type="cover" title="Cover" href="cover.xhtml"/>
  </guide>
</package>
"""

container = """<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""

epub_path = here / "Life-OS-Engineering-Handbook.epub"
buf = io.BytesIO()
with zipfile.ZipFile(buf, "w") as zf:
    zf.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
    zf.writestr("META-INF/container.xml", container, compress_type=zipfile.ZIP_DEFLATED)
    zf.writestr("OEBPS/content.opf", opf, compress_type=zipfile.ZIP_DEFLATED)
    zf.writestr("OEBPS/nav.xhtml", nav_xhtml, compress_type=zipfile.ZIP_DEFLATED)
    zf.writestr("OEBPS/cover.xhtml", cover_xhtml, compress_type=zipfile.ZIP_DEFLATED)
    zf.writestr("OEBPS/handbook.xhtml", chapter, compress_type=zipfile.ZIP_DEFLATED)
    zf.writestr("OEBPS/cover.jpg", cover_jpg, compress_type=zipfile.ZIP_DEFLATED)

epub_path.write_bytes(buf.getvalue())
print(f"EPUB written: {epub_path} ({epub_path.stat().st_size} bytes)")
PY

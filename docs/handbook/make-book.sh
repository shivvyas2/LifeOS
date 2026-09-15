#!/usr/bin/env bash
# Build the whole handbook: assemble index.html, render the PDF (two passes so
# the contents carries real page numbers), then pack the Kindle EPUB.
#
# Usage:  ./docs/handbook/make-book.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$HERE/build.py"
"$HERE/render-pdf.sh"
"$HERE/render-epub.sh"

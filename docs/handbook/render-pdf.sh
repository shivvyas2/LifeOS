#!/usr/bin/env bash
# Regenerate Life-OS-Engineering-Handbook.pdf from index.html.
#
# Two passes, the way a typesetter does it:
#   1. render the PDF,
#   2. read back which page each numbered heading landed on and write those
#      numbers into the contents page of index.html,
#   3. render again so the printed contents shows the real numbers.
#
# The contents geometry does not change between passes (the page-number
# column is fixed width) so two passes are enough to reach a fixed point.
#
# Uses Puppeteer's own Chromium rather than a locally installed browser:
# Brave's headless mode hangs indefinitely on this machine (v151), including
# on a trivial test page, so --print-to-pdf against it is not an option.
#
# Usage:  ./docs/handbook/render-pdf.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/render.js" <<JS
const puppeteer = require('puppeteer');
const fs = require('fs');

const HTML = '${HERE}/index.html';
const PDF  = '${HERE}/Life-OS-Engineering-Handbook.pdf';

async function render() {
  const browser = await puppeteer.launch({ args: ['--no-sandbox'] });
  const page = await browser.newPage();
  // Force light regardless of the rendering machine's OS theme.
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }]);
  await page.goto('file://' + HTML, { waitUntil: 'networkidle0' });
  await page.evaluate(() => document.fonts.ready);
  await page.pdf({
    path: PDF,
    format: 'A4',
    printBackground: true,
    margin: { top: '16mm', bottom: '18mm', left: '15mm', right: '15mm' },
    displayHeaderFooter: true,
    headerTemplate: '<div></div>',
    footerTemplate: '<div style="width:100%;font-family:Roboto,-apple-system,sans-serif;font-size:8pt;color:#8a857c;padding:0 15mm;display:flex;justify-content:space-between;"><span>Life OS Engineering Handbook · Rev B</span><span class="pageNumber"></span></div>',
  });
  await browser.close();
}

/** Every contents entry: its anchor id, and the heading text to hunt for. */
function tocEntries(html) {
  const re = /<a href="#([^"]+)"><span class="toc-num">([^<]*)<\/span><span class="toc-title">([^<]*)<\/span>/g;
  const out = [];
  let m;
  while ((m = re.exec(html)) !== null) {
    out.push({ id: m[1], needle: squash(m[2] + m[3]) });
  }
  return out;
}

const squash = (s) => s.replace(/&amp;/g, '&').replace(/\s+/g, '').toLowerCase();

async function pageIndex() {
  const pdfjs = await import('pdfjs-dist/legacy/build/pdf.mjs');
  const doc = await pdfjs.getDocument({ data: new Uint8Array(fs.readFileSync(PDF)) }).promise;
  const pages = [];
  for (let i = 1; i <= doc.numPages; i++) {
    const content = await (await doc.getPage(i)).getTextContent();
    pages.push(squash(content.items.map((it) => it.str).join(' ')));
  }
  return pages;
}

(async () => {
  console.log('Pass 1: rendering…');
  await render();

  const pages = await pageIndex();
  // The contents itself repeats every heading string; never match against it.
  const isContents = pages.map((t) => t.includes('tableofcontents'));

  let html = fs.readFileSync(HTML, 'utf8');
  const entries = tocEntries(html);
  const missing = [];

  for (const { id, needle } of entries) {
    const idx = pages.findIndex((text, i) => !isContents[i] && text.includes(needle));
    if (idx === -1) { missing.push(needle); continue; }
    const re = new RegExp('(<span class="toc-page" data-page-for="' + id + '">)[^<]*(<\\/span>)');
    html = html.replace(re, '\$1' + (idx + 1) + '\$2');
  }

  fs.writeFileSync(HTML, html);
  console.log('Located ' + (entries.length - missing.length) + '/' + entries.length + ' headings across ' + pages.length + ' pages.');
  if (missing.length) console.warn('NOT FOUND: ' + missing.join(', '));

  console.log('Pass 2: rendering with contents page numbers…');
  await render();
  console.log('PDF written: ' + PDF);
})().catch((e) => { console.error('FAILED:', e.message); process.exit(1); });
JS

cd "$WORK"
npm init -y > /dev/null 2>&1
echo "Installing Puppeteer and pdfjs-dist (downloads Chromium on first run)…"
npm install puppeteer pdfjs-dist > /dev/null 2>&1
node render.js

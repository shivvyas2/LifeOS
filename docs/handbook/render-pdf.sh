#!/usr/bin/env bash
# Regenerate Life-OS-Engineering-Handbook.pdf from index.html.
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

(async () => {
  const browser = await puppeteer.launch({ args: ['--no-sandbox'] });
  const page = await browser.newPage();
  // Force light regardless of the rendering machine's OS theme.
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }]);
  await page.goto('file://${HERE}/index.html', { waitUntil: 'networkidle0' });
  await page.pdf({
    path: '${HERE}/Life-OS-Engineering-Handbook.pdf',
    format: 'A4',
    printBackground: true,
    margin: { top: '16mm', bottom: '18mm', left: '15mm', right: '15mm' },
    displayHeaderFooter: true,
    headerTemplate: '<div></div>',
    footerTemplate: '<div style="width:100%;font-family:-apple-system,sans-serif;font-size:8pt;color:#8a857c;padding:0 15mm;display:flex;justify-content:space-between;"><span>Life OS — Engineering Handbook · Rev A</span><span class="pageNumber"></span></div>',
  });
  await browser.close();
  console.log('PDF written');
})().catch(e => { console.error('FAILED:', e.message); process.exit(1); });
JS

cd "$WORK"
npm init -y > /dev/null 2>&1
echo "Installing Puppeteer (downloads Chromium on first run)…"
npm install puppeteer > /dev/null 2>&1
node render.js

#!/usr/bin/env python3
"""Assemble docs/handbook/index.html from src/.

    src/fonts.css          Roboto and Roboto Mono, inlined as base64
    src/book.css           the stylesheet
    src/front.html         the title page (author, revision, standfirst)
    src/chapters/chNN.html one <section class="chapter"> per file

The contents page is generated from the chapters' h2 and h3 headings, so a
heading added to a chapter appears in the contents without any other edit.
Page numbers in the contents are written by render-pdf.sh; this script carries
the last known numbers forward so a rebuild does not blank them.

Every chapter must parse as XML, because the same fragments are packed into a
Kindle EPUB by pack-epub.py. A chapter that does not parse stops the build.

Usage:  python3 docs/handbook/build.py
"""
from __future__ import annotations

import html
import re
import sys
import xml.dom.minidom
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = HERE / "src"
OUT = HERE / "index.html"

TITLE = "Almanac Engineering Handbook"

# Part dividers. Each part lists the chapter files it contains, in order.
PARTS = [
    {
        "id": "part1",
        "kicker": "Part one",
        "title": "Foundations",
        "blurb": "The shape of the system before any screen: how the modules depend on each "
                 "other, where state lives, how a screen is built, what every screen is built "
                 "from, and how a person gets through the door.",
        "chapters": ["ch01", "ch02", "ch03", "ch04"],
    },
    {
        "id": "part2",
        "kicker": "Part two",
        "title": "The screens",
        "blurb": "One chapter per feature. Each follows the same shape: intent, files, model, "
                 "view model, view, how it works end to end, what keeps it fast and cheap, what "
                 "breaks and how it is handled, and how to study it.",
        "chapters": ["ch05", "ch06", "ch07", "ch08", "ch09", "ch10", "ch11", "ch12",
                     "ch13", "ch14", "ch15", "ch16", "ch17", "ch18"],
    },
    {
        "id": "part3",
        "kicker": "Part three",
        "title": "Under the hood",
        "blurb": "The external systems, the backend, every stored type, the edge cases the "
                 "app is built to survive, how to set it up and ship it, and what it costs.",
        "chapters": ["ch19", "ch20", "ch21", "ch22", "ch23", "ch24"],
    },
    {
        "id": "part4",
        "kicker": "Appendices",
        "title": "Reference",
        "blurb": "Why the product exists, every decision that shaped it, and a glossary with a "
                 "reading order for studying the code.",
        "chapters": ["chA", "chB", "chC"],
    },
]

H2_RE = re.compile(r'<h2>\s*<span class="num">([^<]*)</span>\s*<span>(.*?)</span>\s*</h2>', re.S)
H3_RE = re.compile(r'<h3 id="([^"]+)">\s*<span class="num">([^<]*)</span>\s*<span>(.*?)</span>\s*</h3>', re.S)
SECTION_RE = re.compile(r'<section class="chapter" id="([^"]+)"')
PAGE_RE = re.compile(r'<span class="toc-page" data-page-for="([^"]+)">([^<]*)</span>')


def strip_tags(s: str) -> str:
    return html.unescape(re.sub(r"<[^>]+>", "", s)).strip()


def validate_xml(name: str, fragment: str) -> None:
    try:
        xml.dom.minidom.parseString("<div>" + fragment + "</div>")
    except Exception as e:  # noqa: BLE001
        sys.exit(f"{name}: not well-formed XML: {e}")


def check_prose(name: str, fragment: str) -> None:
    text = strip_tags(fragment)
    dashes = text.count("—")
    if dashes:
        print(f"  warning: {name} contains {dashes} em dash(es)")


def load_chapter(stem: str) -> dict:
    path = SRC / "chapters" / f"{stem}.html"
    if not path.exists():
        sys.exit(f"missing chapter file: {path}")
    frag = path.read_text(encoding="utf-8").strip()
    validate_xml(path.name, frag)
    check_prose(path.name, frag)
    m = SECTION_RE.search(frag)
    if not m:
        sys.exit(f"{path.name}: no <section class=\"chapter\" id=...>")
    chap_id = m.group(1)
    h2 = H2_RE.search(frag)
    if not h2:
        sys.exit(f"{path.name}: no chapter h2 with .num span")
    sections = [(sid, num, strip_tags(title)) for sid, num, title in H3_RE.findall(frag)]
    words = len(strip_tags(re.sub(r"<(pre|svg)[^>]*>.*?</\1>", "", frag, flags=re.S)).split())
    return {
        "stem": stem,
        "id": chap_id,
        "num": h2.group(1).strip(),
        "title": strip_tags(h2.group(2)),
        "sections": sections,
        "html": frag,
        "words": words,
    }


def toc_row(href: str, num: str, title: str, pages: dict[str, str], cls: str) -> str:
    page = pages.get(href, "")
    return (
        f'<li class="{cls}"><a href="#{href}"><span class="toc-num">{html.escape(num)}</span>'
        f'<span class="toc-title">{html.escape(title)}</span><span class="toc-dots"></span>'
        f'<span class="toc-page" data-page-for="{href}">{page}</span></a>'
    )


def build_toc(parts: list[dict], pages: dict[str, str]) -> str:
    out = ['<nav class="toc" aria-label="Contents">', "<ol>"]
    for part in parts:
        out.append(f'<li class="toc-part">{html.escape(part["kicker"])}: {html.escape(part["title"])}</li>')
        for ch in part["loaded"]:
            out.append(toc_row(ch["id"], ch["num"], ch["title"], pages, "toc-chap"))
            if ch["sections"]:
                out.append("<ol>")
                for sid, num, title in ch["sections"]:
                    out.append(toc_row(sid, num, title, pages, "toc-sec") + "</li>")
                out.append("</ol>")
            out.append("</li>")
    out += ["</ol>", "</nav>"]
    return "\n".join(out)


def part_divider(part: dict) -> str:
    items = "".join(
        f'<li><a href="#{ch["id"]}">{html.escape(ch["num"])}. {html.escape(ch["title"])}</a></li>'
        for ch in part["loaded"]
    )
    return (
        f'<section class="part" id="{part["id"]}">\n'
        f'<p class="part-kicker">{html.escape(part["kicker"])}</p>\n'
        f'<h2>{html.escape(part["title"])}</h2>\n'
        f'<p>{html.escape(part["blurb"])}</p>\n'
        f"<ul>{items}</ul>\n"
        "</section>\n"
    )


def main() -> None:
    fonts = (SRC / "fonts.css").read_text(encoding="utf-8")
    css = (SRC / "book.css").read_text(encoding="utf-8")
    front = (SRC / "front.html").read_text(encoding="utf-8")
    validate_xml("front.html", front)

    pages: dict[str, str] = {}
    if OUT.exists():
        pages = {k: v for k, v in PAGE_RE.findall(OUT.read_text(encoding="utf-8")) if v.strip()}

    total_words = 0
    for part in PARTS:
        part["loaded"] = [load_chapter(stem) for stem in part["chapters"]]
        for ch in part["loaded"]:
            total_words += ch["words"]
            print(f"  {ch['stem']:5}  {ch['num']:>3}  {ch['title']:<44} {len(ch['sections']):2} sections  {ch['words']:6} words")

    # Cross-document checks: every #href resolves, ids and marker ids are unique.
    all_html = "".join(ch["html"] for part in PARTS for ch in part["loaded"])
    ids = re.findall(r'\sid="([^"]+)"', all_html)
    dupes = sorted({i for i in ids if ids.count(i) > 1})
    if dupes:
        sys.exit(f"duplicate ids across chapters: {dupes}")
    known = set(ids) | {p["id"] for p in PARTS}
    broken = sorted({h for h in re.findall(r'href="#([^"]+)"', all_html) if h not in known})
    if broken:
        print(f"  warning: unresolved cross references: {broken}")
    markers = re.findall(r'<marker id="([^"]+)"', all_html)
    mdupes = sorted({m for m in markers if markers.count(m) > 1})
    if mdupes:
        sys.exit(f"duplicate SVG marker ids: {mdupes}")

    body = [front]
    body.append('<section class="contents">')
    body.append("<h2>Table of contents</h2>")
    body.append(
        '<p class="contents-note">Every line is a link as well as a page number. '
        "Part two is the features, one chapter per screen, each in the same shape.</p>"
    )
    body.append(build_toc(PARTS, pages))
    body.append("</section>")
    for part in PARTS:
        body.append(part_divider(part))
        for ch in part["loaded"]:
            body.append(f"<!-- ============ {ch['stem']}: {ch['title']} ============ -->")
            body.append(ch["html"])
    body.append("<hr/>")
    body.append(
        '<p class="colophon">Almanac Engineering Handbook, Revision E, 15 September 2026. '
        "Written by Shiv Vyas from the code on <code>main</code>. "
        "Source of record: the code; <code>docs/superpowers/specs/</code> for work not yet built. "
        "Built by <code>docs/handbook/build.py</code>; page numbers by <code>render-pdf.sh</code>; "
        "the Kindle edition by <code>render-epub.sh</code>.</p>"
    )

    doc = (
        "<!doctype html>\n"
        '<html lang="en">\n<head>\n<meta charset="utf-8"/>\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1"/>\n'
        '<meta name="color-scheme" content="light dark"/>\n'
        '<meta name="author" content="Shiv Vyas"/>\n'
        f"<title>{TITLE}</title>\n"
        "<style>\n" + fonts + "\n" + css + "\n</style>\n"
        "</head>\n<body>\n<div class=\"page\">\n" + "\n".join(body) + "\n</div>\n</body>\n</html>\n"
    )
    OUT.write_text(doc, encoding="utf-8")
    print(f"index.html written: {OUT.stat().st_size} bytes, about {total_words} words of prose")


if __name__ == "__main__":
    main()

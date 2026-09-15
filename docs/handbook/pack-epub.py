#!/usr/bin/env python3
"""Pack index.html into a Kindle-ready EPUB 3, one XHTML file per chapter.

Reads the assembled index.html (see build.py) and cover.jpg (see render-epub.sh),
splits the body into a title page, a printed contents page, one file per part
divider and one file per chapter, rewrites every cross reference to point at the
file that holds its target, and writes a navigation document (nav.xhtml), a
legacy NCX, and the package document with the author and cover set.

The stylesheet is src/kindle.css: plain CSS 2.1 that Kindle's renderer honours,
instead of the web stylesheet with its custom properties, columns and
color-mix() that it does not. Diagrams keep their SVG but their CSS classes are
turned into presentation attributes so they render without the stylesheet.

Usage:  python3 docs/handbook/pack-epub.py
"""
from __future__ import annotations

import datetime
import html
import io
import re
import sys
import uuid
import xml.dom.minidom
import zipfile
from pathlib import Path

from bs4 import BeautifulSoup, Tag
from bs4.dammit import EntitySubstitution
from bs4.formatter import XMLFormatter

HERE = Path(__file__).resolve().parent
INDEX = HERE / "index.html"
COVER = HERE / "cover.jpg"
KINDLE_CSS = HERE / "src" / "kindle.css"
OUT = HERE / "Almanac-Engineering-Handbook.epub"

TITLE = "Almanac Engineering Handbook"
AUTHOR = "Shiv Vyas"
AUTHOR_SORT = "Vyas, Shiv"
LANG = "en"
DATE = "2026-09-15"
BOOK_ID = "urn:uuid:6e1f0c8a-4b2d-4f91-9e3a-25a825082026"

XMLNS = 'xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"'

# Presentation attributes for the diagram classes, light palette.
SVG_STYLE = {
    "box":      {"fill": "#FBFAF7", "stroke": "#16150F", "stroke-width": "1.25"},
    "box-alt":  {"fill": "#E7E4DD", "stroke": "#16150F", "stroke-width": "1.25"},
    "box-hot":  {"fill": "#FBE4DB", "stroke": "#F0572E", "stroke-width": "1.5"},
    "lbl":      {"fill": "#16150F", "font-family": "sans-serif", "font-size": "12"},
    "lbl-sm":   {"fill": "#7C776C", "font-family": "monospace", "font-size": "10"},
    "lbl-hot":  {"fill": "#F0572E", "font-family": "monospace", "font-size": "10"},
    "flow":     {"stroke": "#16150F", "stroke-width": "1.25", "fill": "none"},
    "flow-hot": {"stroke": "#F0572E", "stroke-width": "1.75", "fill": "none"},
    "flow-dash": {"stroke": "#7C776C", "stroke-width": "1.25", "fill": "none", "stroke-dasharray": "5 4"},
    "wall":     {"stroke": "#C2412A", "stroke-width": "2", "stroke-dasharray": "7 5"},
    "head":     {"fill": "#16150F"},
    "head-hot": {"fill": "#F0572E"},
}


def serialize(tag: Tag) -> str:
    out = tag.decode(formatter=XMLFormatter(entity_substitution=EntitySubstitution.substitute_xml))
    return re.sub(r"^<\?xml[^>]*\?>\s*", "", out)


def xhtml_doc(title: str, body_inner: str, extra_head: str = "") -> str:
    doc = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<html {XMLNS} xml:lang="{LANG}" lang="{LANG}">\n<head>\n'
        f"<title>{html.escape(title)}</title>\n"
        '<meta charset="utf-8"/>\n'
        '<link rel="stylesheet" type="text/css" href="kindle.css"/>\n'
        f"{extra_head}</head>\n<body>\n{body_inner}\n</body>\n</html>\n"
    )
    try:
        xml.dom.minidom.parseString(doc.encode("utf-8"))
    except Exception as e:  # noqa: BLE001
        sys.exit(f"{title}: generated XHTML is not well-formed: {e}")
    return doc


def bake_svg_styles(root: Tag) -> None:
    """Turn diagram classes into presentation attributes so Kindle draws them."""
    for svg in root.find_all("svg"):
        svg["xmlns"] = "http://www.w3.org/2000/svg"
        svg.attrs.pop("class", None)
        if "viewBox" in svg.attrs and "width" not in svg.attrs:
            svg["width"] = "100%"
        svg["style"] = "max-width:100%;height:auto;"
        for el in svg.find_all(True):
            classes = el.get("class")
            if not classes:
                continue
            if isinstance(classes, str):
                classes = classes.split()
            for cls in classes:
                for k, v in SVG_STYLE.get(cls, {}).items():
                    el[k] = v
            el.attrs.pop("class", None)


def strip_web_only(root: Tag) -> None:
    """Remove pieces that only make sense on the web page."""
    for el in root.select(".toc-dots, .toc-page"):
        el.decompose()


def main() -> None:
    if not INDEX.exists():
        sys.exit("index.html missing; run build.py first")
    if not COVER.exists():
        sys.exit("cover.jpg missing; run render-epub.sh, which rasterizes cover.svg")
    kindle_css = KINDLE_CSS.read_text(encoding="utf-8")

    # Parse only the page body, and as XML: html.parser lowercases SVG
    # attributes (viewBox, markerWidth, refX), which XML treats as different
    # attributes, and a diagram without a viewBox does not scale on Kindle.
    # build.py guarantees the body is well-formed; the <style> in the head is not.
    raw = INDEX.read_text(encoding="utf-8")
    start = raw.index('<div class="page">')
    end = raw.rindex("</div>") + len("</div>")
    soup = BeautifulSoup(raw[start:end], "xml")
    page = soup.find("div", class_="page")
    if page is None:
        sys.exit("index.html has no div.page")

    cover_header = page.select_one("header.cover")
    contents = page.select_one("section.contents")
    blocks = [el for el in page.find_all(["section"], recursive=False) if el is not contents]
    colophon = page.select_one("p.colophon")

    # One file per part divider and per chapter, in document order.
    files: list[tuple[str, str, Tag]] = []  # (filename, title, element)
    def classes_of(el: Tag) -> list[str]:
        c = el.get("class") or []
        return c.split() if isinstance(c, str) else list(c)

    for el in blocks:
        classes = classes_of(el)
        if "part" in classes:
            fname = f"{el['id']}.xhtml"
            title = el.h2.get_text(" ", strip=True) if el.h2 else el["id"]
            files.append((fname, title, el))
        elif "chapter" in classes:
            fname = f"{el['id']}.xhtml"
            h2 = el.find("h2")
            num = h2.select_one(".num").get_text(strip=True) if h2 and h2.select_one(".num") else ""
            name = h2.find_all("span")[-1].get_text(" ", strip=True) if h2 else el["id"]
            title = f"{num}. {name}" if num and not num.isalpha() else (f"Appendix {num}. {name}" if num else name)
            files.append((fname, title, el))

    # Every id in the document, mapped to the file that will hold it.
    id_to_file: dict[str, str] = {}
    for fname, _, el in files:
        for node in el.find_all(True):
            if node.get("id"):
                id_to_file[node["id"]] = fname
        if el.get("id"):
            id_to_file[el["id"]] = fname

    def rewrite_links(root: Tag) -> None:
        for a in root.find_all("a", href=True):
            href = a["href"]
            if href.startswith("#"):
                target = href[1:]
                if target in id_to_file:
                    a["href"] = f"{id_to_file[target]}#{target}"
                else:
                    print(f"  warning: unresolved link #{target}")

    for _, _, el in files:
        rewrite_links(el)
        bake_svg_styles(el)

    # Chapter and section list for the navigation documents.
    # Three levels: part, chapter, section. A chapter before any part divider
    # sits at the top level.
    toc: list[dict] = []
    for fname, title, el in files:
        entry = {"file": fname, "title": title, "id": el.get("id"), "children": []}
        if "part" in classes_of(el):
            toc.append(entry)
            continue
        for h3 in el.find_all("h3", id=True):
            num = h3.select_one(".num").get_text(strip=True) if h3.select_one(".num") else ""
            name = h3.find_all("span")[-1].get_text(" ", strip=True)
            entry["children"].append({"file": fname, "id": h3["id"], "title": f"{num} {name}".strip(), "children": []})
        if toc and "part" in classes_of(next(e for f, t, e in files if f == toc[-1]["file"])):
            toc[-1]["children"].append(entry)
        else:
            toc.append(entry)

    manifest: list[str] = []
    spine: list[str] = []
    zipped: dict[str, bytes] = {}

    # Cover page.
    cover_xhtml = xhtml_doc(
        "Cover",
        '<div style="text-align:center;padding:0;margin:0;">'
        f'<img src="cover.jpg" alt="{html.escape(TITLE)}" style="max-width:100%;height:auto;"/></div>',
    )
    zipped["OEBPS/cover.xhtml"] = cover_xhtml.encode("utf-8")
    manifest.append('<item id="cover" href="cover.xhtml" media-type="application/xhtml+xml"/>')
    spine.append('<itemref idref="cover" linear="no"/>')

    # Title page from the web title page.
    if cover_header is not None:
        strip_web_only(cover_header)
        for el in cover_header.select(".dotrow"):
            el.decompose()
        title_inner = f'<section epub:type="titlepage" class="titlepage">{serialize(cover_header)}</section>'
        zipped["OEBPS/titlepage.xhtml"] = xhtml_doc("Title page", title_inner).encode("utf-8")
        manifest.append('<item id="titlepage" href="titlepage.xhtml" media-type="application/xhtml+xml"/>')
        spine.append('<itemref idref="titlepage"/>')

    # Printed contents page and nav share one recursive list renderer.
    def href_of(entry: dict) -> str:
        return entry["file"] if entry.get("id") is None or entry["file"].startswith(("part", "ch")) and entry["id"] in (entry["file"].replace(".xhtml", ""),) else f'{entry["file"]}#{entry["id"]}'

    def render_list(entries: list[dict], cls: str = "") -> str:
        attr = f' class="{cls}"' if cls else ""
        out = [f"<ol{attr}>"]
        for entry in entries:
            out.append(f'<li><a href="{href_of(entry)}">{html.escape(entry["title"])}</a>')
            if entry["children"]:
                out.append(render_list(entry["children"]))
            out.append("</li>")
        out.append("</ol>")
        return "\n".join(out)

    def contents_list() -> str:
        return render_list(toc, "contents-list")

    contents_inner = (
        '<section epub:type="toc" class="contents"><h1>Contents</h1>'
        "<p class=\"contents-note\">Part two is the features, one chapter per screen, each in the same shape.</p>"
        + contents_list() + "</section>"
    )
    zipped["OEBPS/contents.xhtml"] = xhtml_doc("Contents", contents_inner).encode("utf-8")
    manifest.append('<item id="contents" href="contents.xhtml" media-type="application/xhtml+xml"/>')
    spine.append('<itemref idref="contents"/>')

    # Parts and chapters.
    for i, (fname, title, el) in enumerate(files):
        strip_web_only(el)
        inner = serialize(el)
        if i == len(files) - 1 and colophon is not None:
            inner += "\n<hr/>\n" + serialize(colophon)
        zipped[f"OEBPS/{fname}"] = xhtml_doc(title, inner).encode("utf-8")
        item_id = fname.replace(".xhtml", "")
        manifest.append(f'<item id="{item_id}" href="{fname}" media-type="application/xhtml+xml"/>')
        spine.append(f'<itemref idref="{item_id}"/>')

    # Navigation document (EPUB 3) and NCX (older Kindle readers).
    def nav_list() -> str:
        return render_list(toc)

    nav_inner = (
        '<nav epub:type="toc" id="toc"><h1>Contents</h1>' + nav_list() + "</nav>\n"
        '<nav epub:type="landmarks" hidden="hidden"><h2>Guide</h2><ol>'
        '<li><a epub:type="cover" href="cover.xhtml">Cover</a></li>'
        '<li><a epub:type="titlepage" href="titlepage.xhtml">Title page</a></li>'
        '<li><a epub:type="toc" href="contents.xhtml">Contents</a></li>'
        f'<li><a epub:type="bodymatter" href="{files[0][0]}">Start</a></li>'
        "</ol></nav>"
    )
    zipped["OEBPS/nav.xhtml"] = xhtml_doc("Navigation", nav_inner).encode("utf-8")
    manifest.append('<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>')

    ncx_points: list[str] = []
    play = 0

    def ncx_walk(entries: list[dict]) -> None:
        nonlocal play
        for entry in entries:
            play += 1
            ncx_points.append(
                f'<navPoint id="np{play}" playOrder="{play}"><navLabel><text>{html.escape(entry["title"])}</text></navLabel>'
                f'<content src="{href_of(entry)}"/>'
            )
            ncx_walk(entry["children"])
            ncx_points.append("</navPoint>")

    ncx_walk(toc)
    ncx = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">\n'
        f'<head><meta name="dtb:uid" content="{BOOK_ID}"/><meta name="dtb:depth" content="3"/>'
        '<meta name="dtb:totalPageCount" content="0"/><meta name="dtb:maxPageNumber" content="0"/></head>\n'
        f"<docTitle><text>{html.escape(TITLE)}</text></docTitle>\n"
        f"<docAuthor><text>{html.escape(AUTHOR)}</text></docAuthor>\n"
        "<navMap>\n" + "\n".join(ncx_points) + "\n</navMap>\n</ncx>\n"
    )
    xml.dom.minidom.parseString(ncx.encode("utf-8"))
    zipped["OEBPS/toc.ncx"] = ncx.encode("utf-8")
    manifest.append('<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>')

    zipped["OEBPS/kindle.css"] = kindle_css.encode("utf-8")
    manifest.append('<item id="css" href="kindle.css" media-type="text/css"/>')
    zipped["OEBPS/cover.jpg"] = COVER.read_bytes()
    manifest.append('<item id="cover-image" href="cover.jpg" media-type="image/jpeg" properties="cover-image"/>')

    modified = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    opf = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid" version="3.0" xml:lang="en">\n'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">\n'
        f'<dc:identifier id="bookid">{BOOK_ID}</dc:identifier>\n'
        f"<dc:title>{html.escape(TITLE)}</dc:title>\n"
        f'<dc:creator id="creator">{html.escape(AUTHOR)}</dc:creator>\n'
        '<meta refines="#creator" property="role" scheme="marc:relators">aut</meta>\n'
        f'<meta refines="#creator" property="file-as">{html.escape(AUTHOR_SORT)}</meta>\n'
        f"<dc:language>{LANG}</dc:language>\n"
        f"<dc:date>{DATE}</dc:date>\n"
        "<dc:publisher>Almanac</dc:publisher>\n"
        "<dc:description>How Almanac, a personal iOS app that gathers every health, money, "
        "calendar and notes signal into one local store and puts a coach on top, is built, "
        "why, and what it does when things go wrong. Revision E.</dc:description>\n"
        f'<meta property="dcterms:modified">{modified}</meta>\n'
        '<meta name="cover" content="cover-image"/>\n'
        "</metadata>\n<manifest>\n" + "\n".join(manifest) + "\n</manifest>\n"
        '<spine toc="ncx">\n' + "\n".join(spine) + "\n</spine>\n"
        '<guide><reference type="cover" title="Cover" href="cover.xhtml"/>'
        '<reference type="toc" title="Contents" href="contents.xhtml"/>'
        f'<reference type="text" title="Start" href="{files[0][0]}"/></guide>\n'
        "</package>\n"
    )
    xml.dom.minidom.parseString(opf.encode("utf-8"))

    container = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
        '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>\n'
        "</container>\n"
    )

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        zf.writestr("META-INF/container.xml", container, compress_type=zipfile.ZIP_DEFLATED)
        zf.writestr("OEBPS/content.opf", opf, compress_type=zipfile.ZIP_DEFLATED)
        for name, data in zipped.items():
            zf.writestr(name, data, compress_type=zipfile.ZIP_DEFLATED)
    OUT.write_bytes(buf.getvalue())
    print(f"EPUB written: {OUT} ({OUT.stat().st_size} bytes, {len(files)} chapter files, {play} nav points)")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Read-only local ExDoc link/resource and Markdown navigation acceptance."""
import json
import posixpath
import re
import sys
import zipfile
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit


class Page(HTMLParser):
    def __init__(self, source):
        super().__init__()
        self.ids, self.links = set(), []
        self.feed(source)

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if attrs.get("id"):
            self.ids.add(attrs["id"])
        if tag == "a" and attrs.get("name"):
            self.ids.add(attrs["name"])
        key = {"a": "href", "link": "href", "img": "src", "script": "src",
               "form": "action"}.get(tag)
        if key and attrs.get(key):
            self.links.append(attrs[key])


def prose(markdown):
    """Ignore fenced and inline code when reading prose destinations."""
    fence = None
    for line in markdown.splitlines():
        marker = re.match(r"^\s{0,3}(`{3,}|~{3,})", line)
        if marker and fence is None:
            fence = marker[1]
        elif fence and re.match(r"^\s{0,3}" + re.escape(fence[0]) +
                               r"{" + str(len(fence)) + r",}\s*$", line):
            fence = None
        elif fence is None:
            if not re.match(r"^\[[^\]]+\]:", line):
                line = re.sub(r"`+[^`]*`+", "", line)
            yield line


def main(root):
    root = root.resolve()
    pages = {path: Page(path.read_text()) for path in root.glob("*.html")}
    errors, counts = [], {"html_pages": len(pages), "html_targets": 0,
                          "markdown_pages": 0, "markdown_targets": 0}

    for name in ["index.html", "welcome.html", "getting-started.html", "agents.html",
                 "agents.md", "llms.txt"]:
        if not (root / name).is_file():
            errors.append(f"missing entry point {name}")

    def check(source, destination, fragment=False):
        uri = urlsplit(destination)
        if uri.scheme or uri.netloc:
            return
        target = (source.parent / unquote(uri.path)).resolve() if uri.path else source
        if not target.is_relative_to(root) or not target.is_file():
            errors.append(f"{source.name}: missing/escaping target {destination}")
        elif fragment and uri.fragment and target.suffix == ".html":
            if unquote(uri.fragment) not in pages[target].ids:
                errors.append(f"{source.name}: missing anchor {destination}")

    for source, page in pages.items():
        for destination in page.links:
            counts["html_targets"] += 1
            check(source, destination, fragment=True)

    for source in list(root.glob("*.md")) + [root / "llms.txt"]:
        if not source.is_file():
            errors.append(f"missing {source.name}")
            continue
        counts["markdown_pages"] += 1
        for line in prose(source.read_text()):
            destinations = re.findall(r"\]\(([^\s)]+)", line)
            reference = re.match(r"^\[[^\]]+\]:\s*(\S+)", line)
            if reference:
                destinations.append(reference[1])
            destinations += re.findall(r'href="([^"]+)"', line)
            for destination in destinations:
                counts["markdown_targets"] += 1
                check(source, destination)

    counts.update(epub_pages=0, epub_targets=0)
    epubs = [path for path in root.glob("*.epub") if not path.name.startswith(".")]
    if len(epubs) != 1:
        errors.append("expected one generated EPUB")
    else:
        with zipfile.ZipFile(epubs[0]) as book:
            members = set(book.namelist())
            epub_pages = {name: Page(book.read(name).decode()) for name in members
                          if name.endswith(".xhtml")}
            counts["epub_pages"] = len(epub_pages)
            for source, page in epub_pages.items():
                for destination in page.links:
                    counts["epub_targets"] += 1
                    uri = urlsplit(destination)
                    if uri.scheme or uri.netloc:
                        continue
                    target = posixpath.normpath(posixpath.join(posixpath.dirname(source),
                                                              unquote(uri.path))) if uri.path else source
                    if target not in members:
                        errors.append(f"{source}: missing EPUB target {destination}")
                    elif uri.fragment and target in epub_pages:
                        if unquote(uri.fragment) not in epub_pages[target].ids:
                            errors.append(f"{source}: missing EPUB anchor {destination}")

    print(json.dumps({**counts, "errors": errors}, indent=2))
    return bool(errors)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: documentation_site.py /path/to/generated/docs")
    raise SystemExit(main(Path(sys.argv[1])))

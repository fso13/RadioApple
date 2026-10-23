#!/usr/bin/env python3
"""Sanity checks for the static site: local links resolve, images have alt text."""

from __future__ import annotations

import html.parser
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SITE = ROOT / "site"

REQUIRED_MARKERS = ["data-download", "data-version", "data-win-download", "data-win-version", 'id="features"', 'id="install"', 'id="windows"']
EXTERNAL_PREFIXES = ("http://", "https://", "mailto:", "tel:", "data:", "javascript:", "#")


class Collector(html.parser.HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.references: list[tuple[str, str]] = []
        self.images_without_alt: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = {key: value for key, value in attrs}
        if tag == "img":
            src = values.get("src") or ""
            self.references.append(("img", src))
            if not values.get("alt"):
                self.images_without_alt.append(src)
        elif tag in ("link", "script"):
            target = values.get("href") or values.get("src")
            if target:
                self.references.append((tag, target))
        elif tag == "a":
            href = values.get("href")
            if href:
                self.references.append(("a", href))


def is_local(reference: str) -> bool:
    return bool(reference) and not reference.startswith(EXTERNAL_PREFIXES)


def main() -> int:
    index = SITE / "index.html"
    if not index.is_file():
        print("error: site/index.html is missing", file=sys.stderr)
        return 1

    source = index.read_text(encoding="utf-8")
    parser = Collector()
    parser.feed(source)

    missing: list[str] = []
    checked = 0
    for _, reference in parser.references:
        if not is_local(reference):
            continue
        path = reference.split("#", 1)[0].split("?", 1)[0]
        if not path:
            continue
        candidate = (SITE / path.lstrip("/")).resolve()
        checked += 1
        if not candidate.exists():
            missing.append(reference)

    problems: list[str] = []
    if missing:
        problems.append("missing local files: " + ", ".join(sorted(set(missing))))
    if parser.images_without_alt:
        problems.append("images without alt: " + ", ".join(parser.images_without_alt))
    for marker in REQUIRED_MARKERS:
        if marker not in source:
            problems.append(f"missing marker: {marker}")

    for name in ("styles.css", "app.js", "config.js"):
        if not (SITE / name).is_file():
            problems.append(f"missing {name}")

    if problems:
        for problem in problems:
            print(f"error: {problem}", file=sys.stderr)
        return 1

    print(f"site: OK ({checked} local references, {len(parser.references)} total)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

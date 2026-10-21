#!/usr/bin/env python3
"""Checks the wiki sources: page links resolve, sidebar covers every page, H1 exists."""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
WIKI = ROOT / "wiki"

SPECIAL = {"_Sidebar.md", "_Footer.md"}
LINK_RE = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
EXTERNAL_PREFIXES = ("http://", "https://", "mailto:", "tel:", "data:", "#")
FILE_SUFFIXES = (".jpg", ".jpeg", ".png", ".gif", ".webp", ".svg", ".pdf")


def page_files() -> dict[str, pathlib.Path]:
    return {path.stem: path for path in sorted(WIKI.glob("*.md")) if path.name not in SPECIAL}


def check_links(pages: dict[str, pathlib.Path]) -> list[str]:
    problems: list[str] = []
    for stem, path in pages.items():
        for target in LINK_RE.findall(path.read_text(encoding="utf-8")):
            target = target.strip()
            if not target or target.startswith(EXTERNAL_PREFIXES):
                continue
            page = target.split("#", 1)[0]
            if not page:
                continue
            if page.lower().endswith(FILE_SUFFIXES):
                if not (WIKI / page).is_file():
                    problems.append(f"{path.name}: missing local file '{target}'")
                continue
            page = page.removesuffix(".md")
            if page not in pages:
                problems.append(f"{path.name}: link '{target}' does not match a wiki page")
    return problems


def check_sidebar(pages: dict[str, pathlib.Path]) -> list[str]:
    sidebar = WIKI / "_Sidebar.md"
    if not sidebar.is_file():
        return ["_Sidebar.md is missing"]
    text = sidebar.read_text(encoding="utf-8")
    linked: set[str] = set()
    for target in LINK_RE.findall(text):
        if target.startswith(EXTERNAL_PREFIXES):
            continue
        linked.add(target.split("#", 1)[0].removesuffix(".md"))
    missing = sorted(set(pages) - linked)
    if missing:
        return ["sidebar does not link: " + ", ".join(missing)]
    return []


def check_pages(pages: dict[str, pathlib.Path]) -> list[str]:
    problems: list[str] = []
    if "Home" not in pages:
        problems.append("Home.md is missing")
    for stem, path in pages.items():
        text = path.read_text(encoding="utf-8")
        if not any(line.startswith("# ") for line in text.splitlines()):
            problems.append(f"{path.name}: no level-1 heading")
        if "TODO" in text or "FIXME" in text:
            problems.append(f"{path.name}: contains TODO/FIXME")
    return problems


def main() -> int:
    if not WIKI.is_dir():
        print("error: wiki/ is missing", file=sys.stderr)
        return 1
    pages = page_files()
    problems = check_links(pages) + check_sidebar(pages) + check_pages(pages)
    if problems:
        for problem in problems:
            print(f"error: {problem}", file=sys.stderr)
        return 1
    print(f"wiki: OK ({len(pages)} pages, sidebar complete)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

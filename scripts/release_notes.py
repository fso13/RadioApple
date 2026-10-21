#!/usr/bin/env python3
"""Build the GitHub Release body for a version.

Reads the matching section from CHANGELOG.md, adds download links and a short
install hint. Exits with status 2 when the changelog has no section for the
version, so the caller can fall back to `gh release create --generate-notes`.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

DOWNLOAD_LABELS = [
    ("dmg", "Установочный образ (DMG)"),
    ("pkg", "Установщик (PKG)"),
    ("SHA256SUMS.txt", "Контрольные суммы"),
    ("spdx.json", "SBOM (SPDX)"),
]


def extract_section(changelog: pathlib.Path, version: str) -> str | None:
    if not changelog.exists():
        return None
    text = changelog.read_text(encoding="utf-8")
    pattern = re.compile(
        rf"^##\s*\[?v?{re.escape(version)}\]?(?=\s|$)[^\n]*\n(.*?)(?=^##\s|\Z)",
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(text)
    if not match:
        return None
    body = match.group(1).strip()
    return body or None


def build_body(
    version: str,
    repo: str,
    tag: str,
    section: str,
    previous_tag: str | None = None,
) -> str:
    base = f"https://github.com/{repo}/releases/download/{tag}"
    lines = [
        "## Скачать",
        "",
    ]
    for suffix, label in DOWNLOAD_LABELS:
        asset = f"RadioMac-{version}.{suffix}" if suffix != "SHA256SUMS.txt" else suffix
        lines.append(f"- [{label}]({base}/{asset})")
    lines += [
        "",
        "Требуется macOS 14 или новее (Apple Silicon и Intel).",
        "Проверка файлов: `shasum -a 256 -c SHA256SUMS.txt`.",
        "",
        "## Что изменилось",
        "",
        section,
        "",
        "---",
        f"Полный список изменений: [CHANGELOG.md](https://github.com/{repo}/blob/main/CHANGELOG.md).",
    ]
    if previous_tag:
        lines.append(
            f"Сравнение: [{previous_tag}...{tag}]"
            f"(https://github.com/{repo}/compare/{previous_tag}...{tag})."
        )
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--repo", required=True, help="owner/name")
    parser.add_argument("--tag", default=None)
    parser.add_argument("--previous-tag", default=None)
    parser.add_argument("--changelog", default="CHANGELOG.md")
    parser.add_argument("--output", default=None)
    args = parser.parse_args()

    version = args.version.lstrip("v")
    tag = args.tag or f"v{version}"
    section = extract_section(pathlib.Path(args.changelog), version)
    if not section:
        print(
            f"warning: no changelog section for {version}; using a compare link",
            file=sys.stderr,
        )
        if args.previous_tag:
            section = (
                "Полный список изменений: "
                f"[сравнение {args.previous_tag}...{tag}]"
                f"(https://github.com/{args.repo}/compare/{args.previous_tag}...{tag})."
            )
        else:
            section = (
                "Первый публичный релиз. История изменений — в "
                f"[CHANGELOG.md](https://github.com/{args.repo}/blob/main/CHANGELOG.md)."
            )

    body = build_body(version, args.repo, tag, section, args.previous_tag)
    if args.output:
        pathlib.Path(args.output).write_text(body, encoding="utf-8")
    else:
        sys.stdout.write(body)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

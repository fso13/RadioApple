#!/usr/bin/env python3
"""Create a Sparkle 2 appcast with an Ed25519 signature and release notes.

The update dialog shows the `<description>` of the appcast item, so the notes
are rendered from the matching CHANGELOG section as HTML. That way Sparkle
explains what changed in the version being installed.
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import email.utils
import html
import pathlib
import re
import xml.sax.saxutils as xml

ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_CHANGELOG = ROOT / "CHANGELOG.md"


def extract_changelog_section(version: str, changelog: pathlib.Path) -> str:
    """Returns the body of `## [version] …` up to the next `## [` heading."""
    try:
        text = changelog.read_text(encoding="utf-8")
    except OSError as exc:
        raise SystemExit(f"cannot read changelog {changelog}: {exc}") from exc

    heading = re.search(rf"^## \[{re.escape(version)}\][^\n]*$", text, re.MULTILINE)
    if heading is None:
        raise SystemExit(
            f"CHANGELOG has no '## [{version}]' section; release notes would be empty"
        )

    rest = text[heading.end():]
    next_heading = re.search(r"^## \[", rest, re.MULTILINE)
    section = rest[: next_heading.start()] if next_heading else rest
    return section.strip()


def _inline(text: str) -> str:
    """Escapes HTML and converts the small Markdown subset used in CHANGELOG."""
    escaped = html.escape(text, quote=False)
    escaped = re.sub(r"`([^`]+)`", r"<code>\1</code>", escaped)
    escaped = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", escaped)
    escaped = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', escaped)
    return escaped


def render_notes_html(markdown_text: str, version: str, release_url: str) -> str:
    """Renders the changelog subset as XHTML suitable for Sparkle."""
    parts: list[str] = []
    paragraph: list[str] = []
    list_open = False

    def close_list() -> None:
        nonlocal list_open
        if list_open:
            parts.append("</ul>")
            list_open = False

    def flush_paragraph() -> None:
        if paragraph:
            parts.append(f"<p>{_inline(' '.join(paragraph))}</p>")
            paragraph.clear()

    for raw in markdown_text.splitlines():
        line = raw.rstrip()
        stripped = line.strip()
        if not stripped:
            flush_paragraph()
            close_list()
            continue

        if stripped.startswith("### "):
            flush_paragraph()
            close_list()
            parts.append(f"<h3>{_inline(stripped[4:])}</h3>")
            continue

        if stripped.startswith("- "):
            flush_paragraph()
            if not list_open:
                parts.append("<ul>")
                list_open = True
            parts.append(f"<li>{_inline(stripped[2:])}</li>")
            continue

        # Wrapped bullet text is indented with two spaces in CHANGELOG.
        if list_open and line[:1].isspace():
            if parts and parts[-1].endswith("</li>"):
                parts[-1] = f"{parts[-1][:-5]} {_inline(stripped)}</li>"
                continue

        close_list()
        paragraph.append(stripped)

    flush_paragraph()
    close_list()

    if not parts:
        raise SystemExit(f"changelog section for {version} is empty")

    link = html.escape(release_url, quote=True)
    parts.append(
        f'<p><a href="{link}">Полный список изменений и файлы релиза</a></p>'
    )
    return "\n".join(parts)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--dmg", required=True, type=pathlib.Path)
    parser.add_argument("--url", required=True)
    parser.add_argument("--private-key", default="")
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--minimum-system-version", default="14.0")
    parser.add_argument("--changelog", type=pathlib.Path, default=DEFAULT_CHANGELOG)
    parser.add_argument("--release-url", default="")
    args = parser.parse_args()

    try:
        from nacl.signing import SigningKey
    except ImportError:
        raise SystemExit("PyNaCl is required: pip install -r scripts/requirements-appcast.txt")

    private_key = args.private_key or __import__("os").environ.get("SPARKLE_PRIVATE_KEY", "")
    if not private_key:
        raise SystemExit("SPARKLE_PRIVATE_KEY is empty")
    try:
        seed = base64.b64decode(private_key, validate=True)
        signing_key = SigningKey(seed)
    except Exception as exc:  # noqa: BLE001
        raise SystemExit(f"invalid SPARKLE_PRIVATE_KEY: {exc}")

    notes = extract_changelog_section(args.version, args.changelog)
    release_url = args.release_url
    if not release_url:
        release_url = (
            args.url.split("/releases/download/", 1)[0]
            + f"/releases/tag/v{args.version}"
        )
    notes_html = render_notes_html(notes, args.version, release_url)

    dmg = args.dmg.read_bytes()
    signature = base64.b64encode(signing_key.sign(dmg).signature).decode("ascii")
    pub = email.utils.format_datetime(dt.datetime.now(dt.timezone.utc))
    link = args.url.rsplit("/", 1)[0]
    escaped_url = xml.escape(args.url, {'"': "&quot;"})
    title = xml.escape(f"RadioMac {args.version}")

    appcast = f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>RadioMac</title>
    <link>{xml.escape(link)}</link>
    <description>RadioMac updates</description>
    <language>ru</language>
    <item>
      <title>{title}</title>
      <sparkle:version>{xml.escape(args.build)}</sparkle:version>
      <sparkle:shortVersionString>{xml.escape(args.version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{xml.escape(args.minimum_system_version)}</sparkle:minimumSystemVersion>
      <description><![CDATA[{notes_html.replace("]]>", "]]&gt;")}]]></description>
      <pubDate>{pub}</pubDate>
      <enclosure url="{escaped_url}"
                 length="{len(dmg)}"
                 type="application/octet-stream"
                 sparkle:edSignature="{signature}" />
    </item>
  </channel>
</rss>
'''
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(appcast, encoding="utf-8")
    print(
        f"wrote {args.output} ({args.version}, build {args.build}, "
        f"{len(dmg)} bytes, {len(notes_html)} bytes of notes)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

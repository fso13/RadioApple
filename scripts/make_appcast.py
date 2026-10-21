#!/usr/bin/env python3
"""Create a Sparkle 2 appcast with an Ed25519 signature."""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import email.utils
import pathlib
import xml.sax.saxutils as xml


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--dmg", required=True, type=pathlib.Path)
    parser.add_argument("--url", required=True)
    parser.add_argument("--private-key", default="")
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--minimum-system-version", default="14.0")
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
      <description>{title}</description>
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
    print(f"wrote {args.output} ({args.version}, build {args.build}, {len(dmg)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

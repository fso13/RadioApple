#!/usr/bin/env python3
"""Validate the Sparkle feed settings and, when present, the generated appcast."""

from __future__ import annotations

import base64
import pathlib
import plistlib
import sys
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
PLIST = ROOT / "RadioMac" / "Resources" / "Info.plist"
APPCAST = ROOT / "dist" / "appcast.xml"


def main() -> int:
    with PLIST.open("rb") as handle:
        info = plistlib.load(handle)

    feed = info.get("SUFeedURL", "")
    public_key = info.get("SUPublicEDKey", "")
    if not isinstance(feed, str) or not feed.startswith("https://"):
        print("error: SUFeedURL must be an https URL", file=sys.stderr)
        return 1
    try:
        raw_key = base64.b64decode(public_key, validate=True)
    except Exception:
        raw_key = b""
    if len(raw_key) != 32:
        print("error: SUPublicEDKey must be a base64 Ed25519 public key", file=sys.stderr)
        return 1
    if not info.get("SUEnableAutomaticChecks"):
        print("error: SUEnableAutomaticChecks must be true", file=sys.stderr)
        return 1

    if APPCAST.exists():
        tree = ET.parse(APPCAST)
        root = tree.getroot()
        channel = root.find("channel")
        item = channel.find("item") if channel is not None else None
        enclosure = item.find("enclosure") if item is not None else None
        if enclosure is None or not enclosure.get(
            "{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"
        ):
            print("error: appcast has no Sparkle EdDSA signature", file=sys.stderr)
            return 1

    print("Sparkle feed: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

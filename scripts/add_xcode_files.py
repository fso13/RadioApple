#!/usr/bin/env python3
"""Adds Swift files to RadioMac.xcodeproj without Xcode.

Usage: python3 scripts/add_xcode_files.py <group-key> <file> [<file> ...]

group-key is one of: models, data, services, intents, ui, window, tests, app.
"""
import re
import sys
from pathlib import Path

PROJECT = Path("RadioMac.xcodeproj/project.pbxproj")

GROUPS = {
    "models": "A30000000000000000000126",
    "data": "A30000000000000000000127",
    "services": "A30000000000000000000128",
    "intents": "A30000000000000000000129",
    "ui": "A30000000000000000000130",
    "window": "A30000000000000000000131",
    "app": "A30000000000000000000088",
    "tests": "A30000000000000000000093",
    "uitests": "A30000000000000000000104",
}
SOURCES_PHASES = {
    "app": "C40000000000000000000133",
    "models": "C40000000000000000000133",
    "data": "C40000000000000000000133",
    "services": "C40000000000000000000133",
    "intents": "C40000000000000000000133",
    "ui": "C40000000000000000000133",
    "window": "C40000000000000000000133",
    "tests": "C40000000000000000000094",
    "uitests": "C40000000000000000000105",
}


def next_id(text: str, prefix: str, start: int) -> str:
    candidate = start
    while True:
        value = f"{prefix}{candidate:020d}"
        if value not in text:
            return value
        candidate += 1


def insert_sorted_children(text: str, group_id: str, line: str, name: str) -> str:
    pattern = re.compile(
        rf"({group_id} = \{{.*?children = \(\n)(.*?)(\t\t\t\);)", re.S
    )
    match = pattern.search(text)
    if not match:
        raise SystemExit(f"group {group_id} not found")

    existing = [row for row in match.group(2).splitlines() if row.strip()]
    existing.append(line)
    existing.sort(key=lambda row: row.split("/*", 1)[1].split("*/")[0].strip().lower()
                  if "/*" in row else row)
    body = "\n".join(existing) + "\n"
    return text[: match.start(2)] + body + text[match.end(2):]


def insert_phase_file(text: str, phase_id: str, build_id: str) -> str:
    pattern = re.compile(rf"({phase_id} = \{{.*?files = \(\n)(.*?)(\t\t\t\);)", re.S)
    match = pattern.search(text)
    if not match:
        raise SystemExit(f"phase {phase_id} not found")
    body = match.group(2) + f"\t\t\t\t{build_id},\n"
    return text[: match.start(2)] + body + text[match.end(2):]


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    group_key = sys.argv[1]
    if group_key not in GROUPS:
        raise SystemExit(f"unknown group {group_key}")
    group_id = GROUPS[group_key]
    phase_id = SOURCES_PHASES[group_key]

    text = PROJECT.read_text()
    for raw in sys.argv[2:]:
        path = Path(raw)
        name = path.name
        if f"path = {name};" in text and f"/* {name} */" in text:
            print(f"skip (already registered): {name}")
            continue

        file_ref = next_id(text, "F1", 301)
        build_ref = next_id(text, "B2", 301)

        file_line = (
            f"\t\t{file_ref} /* {name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = sourcecode.swift; path = {name}; "
            f'sourceTree = "<group>"; }};\n'
        )
        build_line = (
            f"\t\t{build_ref} /* {name} in Build */ = {{isa = PBXBuildFile; "
            f"fileRef = {file_ref} /* {name} */; }};\n"
        )

        text = text.replace(
            "/* Begin PBXBuildFile section */\n",
            "/* Begin PBXBuildFile section */\n" + build_line,
            1,
        )
        text = text.replace(
            "/* Begin PBXFileReference section */\n",
            "/* Begin PBXFileReference section */\n" + file_line,
            1,
        )
        text = insert_sorted_children(
            text, group_id, f"\t\t\t\t{file_ref} /* {name} */,\n", name
        )
        text = insert_phase_file(text, phase_id, build_ref)
        print(f"added {name} -> {group_key} ({file_ref}, {build_ref})")

    PROJECT.write_text(text)


if __name__ == "__main__":
    main()

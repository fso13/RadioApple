#!/usr/bin/env python3
"""Write a menu-bar template PNG (black artwork, transparent background)."""

import struct
import zlib
from pathlib import Path


def png(width: int, height: int, rgba_rows: list[bytes]) -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    raw = b"".join(b"\x00" + row for row in rgba_rows)
    return b"".join(
        [
            b"\x89PNG\r\n\x1a\n",
            chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)),
            chunk(b"IDAT", zlib.compress(raw, 9)),
            chunk(b"IEND", b""),
        ]
    )


def draw(size: int) -> bytes:
    pixels = [[(0, 0, 0, 0) for _ in range(size)] for _ in range(size)]

    def set_pixel(x: int, y: int, a: int = 255) -> None:
        if 0 <= x < size and 0 <= y < size:
            pixels[y][x] = (0, 0, 0, a)

    def disk(cx: float, cy: float, r: float) -> None:
        for y in range(size):
            for x in range(size):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    set_pixel(x, y)

    def arc(cx: float, cy: float, r: float, width: float) -> None:
        for y in range(size):
            for x in range(size):
                dx, dy = x - cx, y - cy
                dist = (dx * dx + dy * dy) ** 0.5
                # Upper-right broadcast arcs.
                if abs(dist - r) <= width and dy <= r * 0.35 and dx >= -r * 0.2:
                    set_pixel(x, y)

    cx = size * 0.38
    cy = size * 0.62
    disk(cx, cy, size * 0.10)
    arc(cx, cy, size * 0.26, size * 0.055)
    arc(cx, cy, size * 0.40, size * 0.055)

    rows = []
    for y in range(size):
        row = b"".join(bytes((r, g, b, a)) for r, g, b, a in pixels[y])
        rows.append(row)
    return png(size, size, rows)


def main() -> None:
    out = Path(__file__).resolve().parents[1] / "assets" / "AppIcons"
    out.mkdir(parents=True, exist_ok=True)
    (out / "tray_icon.png").write_bytes(draw(32))
    (out / "tray_icon.png").write_bytes(draw(44))
    print(f"wrote {out / 'tray_icon.png'}")


if __name__ == "__main__":
    main()

"""Generate the Kurier HD mark and Android launcher densities.

Icon-512.png in this repo was the leftover Flutter template. This writes a
courier chevron (send / greater-than) on navy — not Discord blurple and not
the Flutter logo — then downscales it for every density.
"""

from __future__ import annotations

import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Sampled from the HD mark (chevron fill).
NAVY = (11, 31, 58, 255)  # #0B1F3A
CHEVRON = (59, 130, 246, 255)  # #3B82F6
LIGHT = (147, 197, 253, 255)  # #93C5FD
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)


def _blend(dst: list[int], x: int, y: int, w: int, rgba: tuple[int, int, int, int], cover: float) -> None:
    if cover <= 0 or x < 0 or y < 0 or x >= w or y >= w:
        return
    i = (y * w + x) * 4
    a = rgba[3] / 255.0 * min(1.0, cover)
    inv = 1.0 - a
    dst[i] = int(dst[i] * inv + rgba[0] * a)
    dst[i + 1] = int(dst[i + 1] * inv + rgba[1] * a)
    dst[i + 2] = int(dst[i + 2] * inv + rgba[2] * a)
    dst[i + 3] = min(255, int(dst[i + 3] * inv + rgba[3] * a))


def _overwrite(dst: list[int], x: int, y: int, w: int, rgba: tuple[int, int, int, int], cover: float) -> None:
    if cover <= 0 or x < 0 or y < 0 or x >= w or y >= w:
        return
    i = (y * w + x) * 4
    t = min(1.0, cover)
    inv = 1.0 - t
    dst[i] = int(dst[i] * inv + rgba[0] * t)
    dst[i + 1] = int(dst[i + 1] * inv + rgba[1] * t)
    dst[i + 2] = int(dst[i + 2] * inv + rgba[2] * t)
    dst[i + 3] = int(dst[i + 3] * inv + rgba[3] * t)


def _fill_poly(
    px: list[int],
    w: int,
    pts: list[tuple[float, float]],
    color: tuple[int, int, int, int],
    *,
    put=_blend,
) -> None:
    if len(pts) < 3:
        return
    min_y = max(0, int(min(p[1] for p in pts)) - 1)
    max_y = min(w - 1, int(max(p[1] for p in pts)) + 1)
    n = len(pts)
    for y in range(min_y, max_y + 1):
        ys = y + 0.5
        xs: list[float] = []
        for i in range(n):
            x1, y1 = pts[i]
            x2, y2 = pts[(i + 1) % n]
            if y1 == y2:
                continue
            if (y1 <= ys < y2) or (y2 <= ys < y1):
                t = (ys - y1) / (y2 - y1)
                xs.append(x1 + t * (x2 - x1))
        xs.sort()
        for k in range(0, len(xs) - 1, 2):
            x0 = xs[k]
            x1 = xs[k + 1]
            for x in range(int(math.floor(x0)), int(math.ceil(x1))):
                cover = 1.0
                if x < x0:
                    cover = x + 1 - x0
                elif x + 1 > x1:
                    cover = x1 - x
                put(px, x, y, w, color, cover)


def _fill_circle(px: list[int], w: int, cx: float, cy: float, r: float, color: tuple[int, int, int, int]) -> None:
    r2 = r * r
    min_x = max(0, int(cx - r) - 1)
    max_x = min(w - 1, int(cx + r) + 1)
    min_y = max(0, int(cy - r) - 1)
    max_y = min(w - 1, int(cy + r) + 1)
    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            d2 = (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2
            if d2 <= r2:
                _blend(px, x, y, w, color, 1.0)
            elif d2 <= (r + 1) ** 2:
                _blend(px, x, y, w, color, max(0.0, r + 1 - math.sqrt(d2)))


def render_mark(size: int, *, padded: bool) -> bytes:
    px = [0] * (size * size * 4)
    # Navy field.
    for i in range(0, len(px), 4):
        px[i : i + 4] = list(NAVY)
    s = float(size)
    inset = s * (0.18 if padded else 0.12)
    left = inset
    right = s - inset
    top = inset
    bot = s - inset
    mid_y = s * 0.5
    thickness = s * 0.13
    # Right-pointing chevron (courier / send), two bands so it reads as a K-wing.
    outer = [
        (left, top),
        (left + thickness * 1.15, top),
        (right - thickness * 0.2, mid_y),
        (left + thickness * 1.15, bot),
        (left, bot),
        (right - thickness * 1.45, mid_y),
    ]
    inner = [
        (left + thickness * 0.55, top + thickness * 0.85),
        (left + thickness * 1.55, top + thickness * 0.85),
        (right - thickness * 1.05, mid_y),
        (left + thickness * 1.55, bot - thickness * 0.85),
        (left + thickness * 0.55, bot - thickness * 0.85),
        (right - thickness * 2.15, mid_y),
    ]
    _fill_poly(px, size, outer, CHEVRON)
    _fill_poly(px, size, inner, LIGHT)
    # Message node at the chevron crook.
    _fill_circle(px, size, left + thickness * 0.95, mid_y, s * 0.055, WHITE)
    return _png(size, size, px)


def render_stat_icon(size: int) -> bytes:
    """White chevron silhouette on a transparent field for Android smallIcon.

    Android tints every opaque pixel, so a navy square becomes a white square.
    Extra inset keeps the glyph in the 16dp optical square of a 24dp canvas.
    """
    px = [0] * (size * size * 4)
    s = float(size)
    inset = s * (4.0 / 24.0)
    left = inset
    right = s - inset
    top = inset
    bot = s - inset
    mid_y = s * 0.5
    thickness = s * 0.16
    outer = [
        (left, top),
        (left + thickness * 1.15, top),
        (right - thickness * 0.2, mid_y),
        (left + thickness * 1.15, bot),
        (left, bot),
        (right - thickness * 1.45, mid_y),
    ]
    inner = [
        (left + thickness * 0.55, top + thickness * 0.85),
        (left + thickness * 1.55, top + thickness * 0.85),
        (right - thickness * 1.05, mid_y),
        (left + thickness * 1.55, bot - thickness * 0.85),
        (left + thickness * 0.55, bot - thickness * 0.85),
        (right - thickness * 2.15, mid_y),
    ]
    _fill_poly(px, size, outer, WHITE)
    _fill_poly(px, size, inner, CLEAR, put=_overwrite)
    _fill_circle(px, size, left + thickness * 0.95, mid_y, s * 0.07, WHITE)
    return _png(size, size, px)


def _png(w: int, h: int, rgba: list[int]) -> bytes:
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        start = y * w * 4
        raw.extend(rgba[start : start + w * 4])

    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def _nearest(src: bytes, src_size: int, dst_size: int) -> bytes:
    # Decode is unnecessary — re-render at target size for sharpness.
    padded = dst_size >= 108
    return render_mark(dst_size, padded=padded)


def write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    print(f"wrote {path} ({len(data)} bytes)")


def write_stat_icons() -> None:
    res = ROOT / "android" / "app" / "src" / "main" / "res"
    for name, size in (
        ("mdpi", 24),
        ("hdpi", 36),
        ("xhdpi", 48),
        ("xxhdpi", 72),
        ("xxxhdpi", 96),
    ):
        write(res / f"drawable-{name}" / "ic_stat_kurier.png", render_stat_icon(size))


def main() -> None:
    hd = render_mark(512, padded=False)
    write(ROOT / "web" / "icons" / "Icon-512.png", hd)
    write(ROOT / "web" / "icons" / "Icon-maskable-512.png", render_mark(512, padded=True))
    write(ROOT / "web" / "icons" / "Icon-192.png", render_mark(192, padded=False))
    write(ROOT / "web" / "icons" / "Icon-maskable-192.png", render_mark(192, padded=True))
    write(ROOT / "web" / "favicon.png", render_mark(32, padded=False))
    write(ROOT / "assets" / "branding" / "kurier.png", hd)

    densities = {
        "mdpi": 48,
        "hdpi": 72,
        "xhdpi": 96,
        "xxhdpi": 144,
        "xxxhdpi": 192,
    }
    fg = {
        "mdpi": 108,
        "hdpi": 162,
        "xhdpi": 216,
        "xxhdpi": 324,
        "xxxhdpi": 432,
    }
    res = ROOT / "android" / "app" / "src" / "main" / "res"
    for name, size in densities.items():
        write(res / f"mipmap-{name}" / "ic_launcher.png", render_mark(size, padded=False))
    for name, size in fg.items():
        write(res / f"mipmap-{name}" / "ic_launcher_foreground.png", render_mark(size, padded=True))
        write(res / f"drawable-{name}" / "ic_launcher_foreground.png", render_mark(size, padded=True))
    write_stat_icons()
    write(res / "drawable" / "splash_logo.png", render_mark(288, padded=True))


if __name__ == "__main__":
    main()

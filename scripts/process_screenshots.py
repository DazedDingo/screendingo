#!/usr/bin/env python3
"""
Crop Pixel 7 (1080×2400) emulator captures down to Play-Store-ready
1080×1920 (9:16) frames.

Play Console rejects phone screenshots whose min:max aspect ratio sits
outside [9:16, 16:9]. Pixel 7 captures at 9:20 — too tall — so they're
rejected as-is. This script:

  1. Strips the system status bar (top 88 px) and gesture nav pill area
     (bottom 60 px) — pure chrome with no app content.
  2. Hard-crops the bottom further to land at 1080×1920 (9:16).
     The top 1920 is kept because that's where the selling content sits
     (animated wordmark, Tonight's Pick, action row, top rec cards) —
     losing the bottom rec rows is preferable to losing the hero.

Also writes a 1080×2252 "loose" variant — the minimum-chrome crop — in
case you want to upload the taller frame instead (some Play accounts
report 1080×2400 working today; 1080×2252 is well under the rejection
threshold but preserves more app content).

Usage:
  python3 scripts/process_screenshots.py <input-dir> [--out <dir>]

Defaults output dir to <input-dir>/processed.

Reads any *.png in input-dir; writes:
  <input>/<name>-1080x1920.png      Play-safe (9:16)
  <input>/<name>-1080x2252.png      Loose (chrome-trimmed only)
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw

# Pixel 7 emulator chrome heights for adb screencap (1080×2400 full
# system framebuffer including system status bar + gesture nav). Fixed
# values, both screenshots.yml + screenshots-real.yml pin
# `profile: pixel_7` so dimensions are deterministic. Conservative —
# leave a few px of slop so we don't clip into the AppBar by accident.
STATUS_BAR_PX = 88
NAV_PILL_PX = 60

EXPECTED_W = 1080
PLAY_W = 1080
PLAY_H = 1920  # 9:16 ratio Play Console enforces

# Flutter's debug-build red "DEBUG" ribbon sits diagonally in the
# top-right corner of every screen in debug APKs. The screenshots
# pipelines build debug APKs (no release-signing setup needed for the
# CI runner), so the ribbon shows up on every capture. The ribbon is
# a 45° triangle ~140 px on each leg — we cover it by painting a
# right triangle of the same dimensions over the corner, leaving the
# AppBar's `?` help icon (which sits just BELOW the ribbon's
# hypotenuse) intact.
#
# A rectangle blot of the same dimensions would clip the `?` icon at
# ~(1030, 90). The diagonal hypotenuse from (940, 0) to (1080, 140)
# cuts at x + y = 1220, which leaves the icon (sum ~1120) safely in
# the kept region.
DEBUG_RIBBON_LEG_PX = 152
# Pixel to sample for the cover color — column near the left edge but
# clear of the wordmark, row near the top of the AppBar. Captured
# screenshots show this region is uniform AppBar background.
SAMPLE_X, SAMPLE_Y = 8, 40


def crop_one(src: Path, out_dir: Path) -> bool:
    """Process one PNG. Returns True on success, False on skip.

    Supports two input shapes both produced by our pipelines:
      - 1080×2400: raw `adb screencap` from screenshots-real.yml — full
                   system framebuffer including system status bar +
                   gesture nav pill. Trim both.
      - 1080×N (N<2400): integration_test `binding.takeScreenshot()`
                   from screenshots-real-it.yml — Flutter surface only,
                   no status bar (~63 px lopped) and may also exclude
                   the nav pill. Just bottom-crop to PLAY_H.

    Anything else (different width, height < PLAY_H) is skipped.
    """
    img = Image.open(src)
    w, h = img.size
    if w != EXPECTED_W:
        print(
            f"  SKIP {src.name} — expected width {EXPECTED_W}, got {w}",
            file=sys.stderr,
        )
        return False
    if h < PLAY_H:
        print(
            f"  SKIP {src.name} — height {h} < {PLAY_H} (can't crop up to 9:16)",
            file=sys.stderr,
        )
        return False

    # Determine the chrome-trimmed "loose" rectangle. For adb screencap
    # (1080×2400) lop both chromes; for integration_test surface
    # captures (1080×~2337) the status bar is already absent, so only
    # lop the nav pill if there's enough headroom.
    if h >= 2400:
        loose = img.crop((0, STATUS_BAR_PX, w, h - NAV_PILL_PX))
    elif h > PLAY_H + NAV_PILL_PX:
        loose = img.crop((0, 0, w, h - NAV_PILL_PX))
    else:
        loose = img  # too tight to lop anything; play crop will handle it
    loose_path = out_dir / f"{src.stem}-{loose.size[0]}x{loose.size[1]}.png"
    loose.save(loose_path, format="PNG", optimize=True)

    # Play-safe crop: take top PLAY_H from the chrome-trimmed image. Keeps
    # the AppBar + hero + top rec cards intact; loses the bottom rows of
    # the rec list, which is acceptable — they aren't the selling content.
    play = loose.crop((0, 0, PLAY_W, PLAY_H))
    assert play.size == (PLAY_W, PLAY_H), play.size

    # Blot the debug ribbon by overlaying a sampled-color RIGHT
    # TRIANGLE in the top-right corner. Triangle (not rectangle) so
    # the AppBar's `?` help icon — which sits just BELOW the ribbon's
    # hypotenuse — survives the blot.
    cover_color = play.getpixel((SAMPLE_X, SAMPLE_Y))
    draw = ImageDraw.Draw(play)
    leg = DEBUG_RIBBON_LEG_PX
    draw.polygon(
        [
            (PLAY_W - leg, 0),       # top-left of triangle
            (PLAY_W, 0),              # top-right (corner)
            (PLAY_W, leg),            # bottom-right (down the edge)
        ],
        fill=cover_color,
    )

    play_path = out_dir / f"{src.stem}-1080x1920.png"
    play.save(play_path, format="PNG", optimize=True)

    print(f"  OK  {src.name} ({w}×{h}) → {play_path.name} + {loose_path.name}")
    return True


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("input_dir", type=Path, help="dir with raw 1080×2400 PNGs")
    ap.add_argument(
        "--out",
        type=Path,
        default=None,
        help="output dir (default: <input>/processed)",
    )
    args = ap.parse_args()

    if not args.input_dir.is_dir():
        print(f"input not a directory: {args.input_dir}", file=sys.stderr)
        return 2

    out_dir = args.out or (args.input_dir / "processed")
    out_dir.mkdir(parents=True, exist_ok=True)

    pngs = sorted(p for p in args.input_dir.glob("*.png") if p.is_file())
    if not pngs:
        print(f"no PNGs in {args.input_dir}", file=sys.stderr)
        return 1

    print(f"Processing {len(pngs)} PNG(s) → {out_dir}")
    n_ok = sum(1 for p in pngs if crop_one(p, out_dir))
    print(f"\nDone — {n_ok}/{len(pngs)} processed.")
    print(f"Play-safe (1080×1920): use the *-1080x1920.png set.")
    print(f"Loose (1080×2252):     use the *-1080x2252.png set if Play accepts taller.")
    return 0 if n_ok > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
